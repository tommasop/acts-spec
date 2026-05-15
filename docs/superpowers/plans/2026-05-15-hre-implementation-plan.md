# Human Review Experience (HRE) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the basic `acts review` terminal prompt with a structured, vim-navigable review interface showing agent rationale, quality gate results, multi-file diffs with hunk navigation, and previous rejection context.

**Architecture:** Extract review logic into a new `review.zig` module. Add a `quality.zig` module for auto-detecting and running quality gates. Extend `db.zig` with rationale and rejection queries. Keep `main.zig` as thin command dispatch.

**Tech Stack:** Zig 0.13.0, POSIX termios for raw terminal input, ANSI escape sequences for display, SQLite for data queries, git for diff generation.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `acts-core/src/quality.zig` | Create | Auto-detect project type, run quality gate commands |
| `acts-core/src/review.zig` | Create | Review orchestration, diff parsing, terminal UI, navigation |
| `acts-core/src/db.zig` | Modify | Add `getRationale`, `getPreviousRejections`, `getFilesForTask` |
| `acts-core/src/main.zig` | Modify | Replace `handleReview` to call `review.run()` |

---

### Task 1: Quality Gate Module

**Files:**
- Create: `acts-core/src/quality.zig`

- [ ] **Step 1: Create quality.zig with project type detection and quality gate execution**

```zig
const std = @import("std");

pub const QualityStage = enum { test, lint, typecheck, build };

pub const QualityResult = struct {
    stage: QualityStage,
    command: []const u8,
    status: enum { pass, fail, warn, skipped },
    exit_code: i32,
    output: []const u8,
    duration_ms: u64,
};

pub const QualityConfig = struct {
    test: ?[]const u8 = null,
    lint: ?[]const u8 = null,
    typecheck: ?[]const u8 = null,
    build: ?[]const u8 = null,
};

/// Detect project type and return quality gate commands
pub fn detectQualityGate(allocator: std.mem.Allocator) !QualityConfig {
    const indicators = [_]struct {
        file: []const u8,
        config: QualityConfig,
    }{
        .{ .file = "Makefile", .config = QualityConfig{ .test = "make test", .lint = "make lint", .typecheck = "make check", .build = "make build" } },
        .{ .file = "package.json", .config = QualityConfig{ .test = "npm test", .lint = "npm run lint", .typecheck = "npx tsc --noEmit", .build = "npm run build" } },
        .{ .file = "Cargo.toml", .config = QualityConfig{ .test = "cargo test", .lint = "cargo clippy", .typecheck = "cargo check", .build = "cargo build" } },
        .{ .file = "go.mod", .config = QualityConfig{ .test = "go test ./...", .lint = "golangci-lint run", .typecheck = null, .build = "go build ./..." } },
        .{ .file = "pyproject.toml", .config = QualityConfig{ .test = "pytest", .lint = "ruff check .", .typecheck = "mypy .", .build = "python -m build" } },
        .{ .file = "requirements.txt", .config = QualityConfig{ .test = "pytest", .lint = "ruff check .", .typecheck = "mypy .", .build = null } },
        .{ .file = "pom.xml", .config = QualityConfig{ .test = "mvn test", .lint = "mvn checkstyle:check", .typecheck = null, .build = "mvn compile" } },
        .{ .file = "build.gradle", .config = QualityConfig{ .test = "gradle test", .lint = "gradle check", .typecheck = null, .build = "gradle build" } },
        .{ .file = "mix.exs", .config = QualityConfig{ .test = "mix test", .lint = "mix credo", .typecheck = null, .build = "mix compile" } },
    };

    for (indicators) |ind| {
        std.fs.cwd().access(ind.file, .{}) catch continue;
        return QualityConfig{
            .test = if (ind.config.test) |t| try allocator.dupe(u8, t) else null,
            .lint = if (ind.config.lint) |l| try allocator.dupe(u8, l) else null,
            .typecheck = if (ind.config.typecheck) |tc| try allocator.dupe(u8, tc) else null,
            .build = if (ind.config.build) |b| try allocator.dupe(u8, b) else null,
        };
    }

    return QualityConfig{};
}

/// Load quality gate config from .acts/acts.json if present
pub fn loadQualityConfig(allocator: std.mem.Allocator) !?QualityConfig {
    const file = std.fs.cwd().openFile(".acts/acts.json", .{}) catch return null;
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 65536);
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const qg = parsed.value.object.get("quality_gate") orelse return null;
    if (qg != .object) return null;

    var config = QualityConfig{};

    if (qg.object.get("test")) |v| {
        if (v == .string and v.string.len > 0) config.test = try allocator.dupe(u8, v.string);
    }
    if (qg.object.get("lint")) |v| {
        if (v == .string and v.string.len > 0) config.lint = try allocator.dupe(u8, v.string);
    }
    if (qg.object.get("typecheck")) |v| {
        if (v == .string and v.string.len > 0) config.typecheck = try allocator.dupe(u8, v.string);
    }
    if (qg.object.get("build")) |v| {
        if (v == .string and v.string.len > 0) config.build = try allocator.dupe(u8, v.string);
    }

    return config;
}

/// Run a single quality gate command with timeout, return result
pub fn runStage(allocator: std.mem.Allocator, stage: QualityStage, command: ?[]const u8) !QualityResult {
    if (command == null) {
        return QualityResult{
            .stage = stage,
            .command = "skipped",
            .status = .skipped,
            .exit_code = 0,
            .output = try allocator.dupe(u8, ""),
            .duration_ms = 0,
        };
    }

    const cmd = command.?;
    const start = try std.time.Instant.now();

    // Parse command into argv (simple space split, no shell escaping needed for our use case)
    var argv_list = std.ArrayList([]const u8).init(allocator);
    defer argv_list.deinit();

    var iter = std.mem.split(u8, cmd, " ");
    while (iter.next()) |part| {
        if (part.len > 0) try argv_list.append(part);
    }

    if (argv_list.items.len == 0) {
        return QualityResult{
            .stage = stage,
            .command = cmd,
            .status = .skipped,
            .exit_code = 0,
            .output = try allocator.dupe(u8, ""),
            .duration_ms = 0,
        };
    }

    var child = std.process.Child.init(argv_list.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    child.spawn() catch |err| {
        return QualityResult{
            .stage = stage,
            .command = cmd,
            .status = .fail,
            .exit_code = -1,
            .output = try std.fmt.allocPrint(allocator, "Failed to spawn: {}", .{err}),
            .duration_ms = 0,
        };
    };

    const wait_result = child.wait() catch |err| {
        return QualityResult{
            .stage = stage,
            .command = cmd,
            .status = .warn,
            .exit_code = -1,
            .output = try std.fmt.allocPrint(allocator, "Wait failed: {}", .{err}),
            .duration_ms = 0,
        };
    };

    const elapsed = start.since(try std.time.Instant.now()) / std.time.ns_per_ms;

    // Capture output
    var output_buf = std.ArrayList(u8).init(allocator);
    defer output_buf.deinit();

    if (child.stdout) |out| {
        const stdout_data = out.reader().readAllAlloc(allocator, 32768) catch "";
        defer allocator.free(stdout_data);
        try output_buf.writer().writeAll(stdout_data);
    }
    if (child.stderr) |err_pipe| {
        const stderr_data = err_pipe.reader().readAllAlloc(allocator, 32768) catch "";
        defer allocator.free(stderr_data);
        try output_buf.writer().writeAll(stderr_data);
    }

    const exit_code: i32 = if (wait_result.Exited) |code| @intCast(code) else -1;
    const status: enum { pass, fail, warn, skipped } = if (exit_code == 0) .pass else if (exit_code >= 100) .warn else .fail;

    return QualityResult{
        .stage = stage,
        .command = cmd,
        .status = status,
        .exit_code = exit_code,
        .output = try output_buf.toOwnedSlice(),
        .duration_ms = elapsed,
    };
}

/// Run all quality gates and return results
pub fn runAllQualityGates(allocator: std.mem.Allocator) ![]QualityResult {
    // Try to load config from acts.json first, fall back to auto-detect
    const config = try loadQualityConfig(allocator) orelse try detectQualityGate(allocator);

    var results = std.ArrayList(QualityResult).init(allocator);

    const stages = [_]struct {
        stage: QualityStage,
        cmd: ?[]const u8,
    }{
        .{ .stage = .test, .cmd = config.test },
        .{ .stage = .lint, .cmd = config.lint },
        .{ .stage = .typecheck, .cmd = config.typecheck },
        .{ .stage = .build, .cmd = config.build },
    };

    for (stages) |s| {
        const result = try runStage(allocator, s.stage, s.cmd);
        try results.append(result);
    }

    return results.toOwnedSlice();
}

/// Free all quality results
pub fn freeQualityResults(allocator: std.mem.Allocator, results: []QualityResult) void {
    for (results) |r| {
        allocator.free(r.output);
        allocator.free(r.command);
    }
    allocator.free(results);
}
```

- [ ] **Step 2: Verify quality.zig compiles**

Run: `cd acts-core && zig build 2>&1`
Expected: Compiles without errors (review.zig doesn't exist yet but quality.zig should compile as a standalone module)

Note: Since quality.zig isn't imported yet, test by running: `cd acts-core && zig build test 2>&1`

---

### Task 2: Database Extensions

**Files:**
- Modify: `acts-core/src/db.zig`

- [ ] **Step 1: Add getRationale method to db.zig**

Add after the `listDecisions` function in db.zig. Find the closing brace of `listDecisions` and add:

```zig
    pub fn getRationale(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) !?[]u8 {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT reason FROM decisions WHERE task_id = ? AND topic = 'rationale' ORDER BY created_at DESC LIMIT 1";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const val = c.sqlite3_column_text(stmt, 0);
            if (val != null) return try allocator.dupe(u8, std.mem.span(val));
        }
        return null;
    }
```

- [ ] **Step 2: Add Rejection struct and getPreviousRejections method**

Add after `getRationale`:

```zig
    pub const Rejection = struct {
        approved_by: []const u8,
        created_at: []const u8,
        comment: ?[]const u8 = null,
    };

    pub fn getPreviousRejections(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) ![]Rejection {
        var rejections = std.ArrayList(Rejection).init(allocator);

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT approved_by, created_at FROM gate_checkpoints WHERE task_id = ? AND gate_type = 'task-review' AND status = 'changes_requested' ORDER BY created_at DESC";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            rejections.deinit();
            return error.QueryFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);

        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const by = try allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(stmt, 0)));
            const at = try allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(stmt, 1)));
            try rejections.append(Rejection{
                .approved_by = by,
                .created_at = at,
            });
        }

        return rejections.toOwnedSlice();
    }

    pub fn freeRejections(allocator: std.mem.Allocator, rejections: []Rejection) void {
        for (rejections) |r| {
            allocator.free(r.approved_by);
            allocator.free(r.created_at);
            if (r.comment) |c| allocator.free(c);
        }
        allocator.free(rejections);
    }
```

- [ ] **Step 3: Add getFilesForTask method**

Add after `freeRejections`:

```zig
    pub fn getFilesForTask(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) ![][]const u8 {
        var files = std.ArrayList([]const u8).init(allocator);

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT file_path FROM task_files WHERE task_id = ? ORDER BY file_path";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            files.deinit();
            return error.QueryFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);

        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const fp = try allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(stmt, 0)));
            try files.append(fp);
        }

        return files.toOwnedSlice();
    }

    pub fn freeFiles(allocator: std.mem.Allocator, files: [][]const u8) void {
        for (files) |f| allocator.free(f);
        allocator.free(files);
    }
```

- [ ] **Step 4: Verify db.zig compiles**

Run: `cd acts-core && zig build 2>&1`
Expected: Compiles without errors

---

### Task 3: Review Module - Diff Parsing and Context Gathering

**Files:**
- Create: `acts-core/src/review.zig`

- [ ] **Step 1: Create review.zig with diff parsing and risk assessment**

```zig
const std = @import("std");
const db = @import("db.zig");
const quality = @import("quality.zig");

const c = @cImport({
    @cInclude("sqlite3.h");
});

// ============================================================
// Data Structures
// ============================================================

pub const DiffHunk = struct {
    header: []const u8,
    old_start: usize,
    new_start: usize,
    old_count: usize,
    new_count: usize,
    lines: []const u8,
};

pub const FileDiff = struct {
    file_path: []const u8,
    additions: usize,
    deletions: usize,
    hunks: []DiffHunk,
    risk: enum { low, medium, high },
    annotation: ?[]const u8 = null,
};

pub const ReviewContext = struct {
    task_id: []const u8,
    task_title: []const u8,
    rationale: ?[]const u8 = null,
    rejections: []db.Rejection,
    files: []FileDiff,
    quality_results: []quality.QualityResult,
};

// ============================================================
// ANSI Colors
// ============================================================

const ansi = struct {
    pub const reset = "\x1b[0m";
    pub const green = "\x1b[32m";
    pub const red = "\x1b[31m";
    pub const cyan = "\x1b[36m";
    pub const yellow = "\x1b[33m";
    pub const white = "\x1b[37m";
    pub const dim = "\x1b[2m";
    pub const bold = "\x1b[1m";
    pub const bg_blue = "\x1b[44m";
    pub const cursor_hide = "\x1b[?25l";
    pub const cursor_show = "\x1b[?25h";
    pub const clear = "\x1b[2J\x1b[H";
};

// ============================================================
// Risk Assessment
// ============================================================

const high_risk_patterns = [_][]const u8{
    "auth", "db", "config", "schema", "security", "crypto", "middleware", "router",
};

const low_risk_patterns = [_][]const u8{
    "test", "spec", "mock", ".md", ".txt",
};

fn assessRisk(file_path: []const u8, additions: usize, deletions: usize) enum { low, medium, high } {
    const lower = std.ascii.allocLowerString(std.heap.page_allocator, file_path) catch return .medium;
    defer std.heap.page_allocator.free(lower);

    var level: usize = 0;

    // File type weight
    for (high_risk_patterns) |pat| {
        if (std.mem.indexOf(u8, lower, pat) != null) {
            level = 2;
            break;
        }
    }
    if (level == 0) {
        for (low_risk_patterns) |pat| {
            if (std.mem.endsWith(u8, lower, pat)) {
                level = 0;
                break;
            }
        } else {
            level = 1;
        }
    }

    // Lines changed
    if (additions + deletions > 100) {
        level = @min(level + 1, 2);
    }

    return switch (level) {
        0 => .low,
        1 => .medium,
        else => .high,
    };
}

fn riskLabel(risk: enum { low, medium, high }) []const u8 {
    return switch (risk) {
        .low => "LOW",
        .medium => "MEDIUM",
        .high => "HIGH",
    };
}

fn riskColor(risk: enum { low, medium, high }) []const u8 {
    return switch (risk) {
        .low => ansi.green,
        .medium => ansi.yellow,
        .high => ansi.red,
    };
}

// ============================================================
// Diff Parsing
// ============================================================

fn parseDiff(allocator: std.mem.Allocator, diff_output: []const u8, files: [][]const u8) ![]FileDiff {
    var result = std.ArrayList(FileDiff).init(allocator);

    var lines = std.mem.split(u8, diff_output, "\n");
    var current_file: ?[]const u8 = null;
    var current_additions: usize = 0;
    var current_deletions: usize = 0;
    var hunk_list = std.ArrayList(DiffHunk).init(allocator);
    var hunk_lines = std.ArrayList(u8).init(allocator);
    var in_hunk = false;
    var hunk_header_start: usize = 0;

    // Helper to finalize current file
    const finalizeFile = struct {
        fn inner(
            alloc: std.mem.Allocator,
            r: *std.ArrayList(FileDiff),
            f: []const u8,
            add: usize,
            del: usize,
            hl: *std.ArrayList(DiffHunk),
            hlines: *std.ArrayList(u8),
            ih: bool,
        ) !void {
            if (f.len == 0) return;

            var hunks = try hl.toOwnedSlice();
            if (ih and hlines.items.len > 0) {
                // Add trailing hunk if any
                const last_hunk_lines = try alloc.dupe(u8, hlines.items);
                try hl.append(DiffHunk{
                    .header = "",
                    .old_start = 0,
                    .new_start = 0,
                    .old_count = 0,
                    .new_count = 0,
                    .lines = last_hunk_lines,
                });
                hunks = try hl.toOwnedSlice();
            }

            try r.append(FileDiff{
                .file_path = try alloc.dupe(u8, f),
                .additions = add,
                .deletions = del,
                .hunks = hunks,
                .risk = assessRisk(f, add, del),
            });
        }
    }.inner;

    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "diff --git")) {
            // Finalize previous file
            if (current_file) |cf| {
                try finalizeFile(allocator, &result, cf, current_additions, current_deletions, &hunk_list, &hunk_lines, in_hunk);
                hunk_list = std.ArrayList(DiffHunk).init(allocator);
                hunk_lines = std.ArrayList(u8).init(allocator);
                in_hunk = false;
            }
            current_additions = 0;
            current_deletions = 0;
        } else if (std.mem.startsWith(u8, line, "+++ b/")) {
            current_file = line[6..];
        } else if (std.mem.startsWith(u8, line, "@@")) {
            // Parse hunk header: @@ -old_start,old_count +new_start,new_count @@
            if (in_hunk and hunk_lines.items.len > 0) {
                const prev_lines = try allocator.dupe(u8, hunk_lines.items);
                try hunk_list.append(DiffHunk{
                    .header = "",
                    .old_start = 0,
                    .new_start = 0,
                    .old_count = 0,
                    .new_count = 0,
                    .lines = prev_lines,
                });
                hunk_lines.clearRetainingCapacity();
            }

            in_hunk = true;
            hunk_header_start = 0;

            // Parse @@ -X,Y +A,B @@
            var parts = std.mem.split(u8, line, " ");
            var idx: usize = 0;
            while (parts.next()) |part| : (idx += 1) {
                if (idx == 1 and part.len > 1) {
                    // -X,Y
                    const nums = part[1..];
                    if (std.mem.indexOf(u8, nums, ",")) |comma| {
                        current_file = current_file; // silence unused
                    }
                }
            }

            try hunk_lines.writer().writeAll(line);
            try hunk_lines.writer().writeByte('\n');
        } else if (in_hunk) {
            if (std.mem.startsWith(u8, line, "+")) {
                current_additions += 1;
            } else if (std.mem.startsWith(u8, line, "-")) {
                current_deletions += 1;
            }
            try hunk_lines.writer().writeAll(line);
            try hunk_lines.writer().writeByte('\n');
        }
    }

    // Finalize last file
    if (current_file) |cf| {
        try finalizeFile(allocator, &result, cf, current_additions, current_deletions, &hunk_list, &hunk_lines, in_hunk);
    }

    return result.toOwnedSlice();
}

fn freeFileDiffs(allocator: std.mem.Allocator, diffs: []FileDiff) void {
    for (diffs) |d| {
        allocator.free(d.file_path);
        if (d.annotation) |a| allocator.free(a);
        for (d.hunks) |h| {
            allocator.free(h.header);
            allocator.free(h.lines);
        }
        allocator.free(d.hunks);
    }
    allocator.free(diffs);
}

// ============================================================
// Context Gathering
// ============================================================

pub fn gatherContext(allocator: std.mem.Allocator, database: *db.Database, task_id: []const u8) !ReviewContext {
    // Get task details
    const task_json = try database.getTask(allocator, task_id);
    defer allocator.free(task_json);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, task_json, .{});
    defer parsed.deinit();

    var task_title: []const u8 = task_id;
    if (parsed.value == .object) {
        if (parsed.value.object.get("title")) |t| {
            if (t == .string) task_title = try allocator.dupe(u8, t.string);
        }
    }

    // Get rationale
    const rationale = try database.getRationale(allocator, task_id);

    // Get previous rejections
    const rejections = try database.getPreviousRejections(allocator, task_id);

    // Get files
    const file_paths = try database.getFilesForTask(allocator, task_id);

    // Run quality gates
    const quality_results = try quality.runAllQualityGates(allocator);

    // Get diff
    var diff_argv = std.ArrayList([]const u8).init(allocator);
    defer diff_argv.deinit();
    try diff_argv.append("git");
    try diff_argv.append("diff");
    try diff_argv.append("--cached");

    var diff_child = std.process.Child.init(diff_argv.items, allocator);
    diff_child.stdin_behavior = .Ignore;
    diff_child.stdout_behavior = .Pipe;
    diff_child.stderr_behavior = .Pipe;
    diff_child.spawn() catch {};
    const diff_output = if (diff_child.stdout) |out|
        out.reader().readAllAlloc(allocator, 262144) catch ""
    else
        "";

    const file_diffs = try parseDiff(allocator, diff_output, file_paths);
    allocator.free(diff_output);
    db.Database.freeFiles(allocator, file_paths);

    return ReviewContext{
        .task_id = try allocator.dupe(u8, task_id),
        .task_title = task_title,
        .rationale = rationale,
        .rejections = rejections,
        .files = file_diffs,
        .quality_results = quality_results,
    };
}

pub fn freeContext(allocator: std.mem.Allocator, ctx: ReviewContext) void {
    allocator.free(ctx.task_id);
    allocator.free(ctx.task_title);
    if (ctx.rationale) |r| allocator.free(r);
    db.Database.freeRejections(allocator, ctx.rejections);
    freeFileDiffs(allocator, ctx.files);
    quality.freeQualityResults(allocator, ctx.quality_results);
}
```

- [ ] **Step 2: Verify review.zig compiles**

Run: `cd acts-core && zig build 2>&1`
Expected: Compiles without errors (review.zig isn't imported yet, but should compile as a module)

---

### Task 4: Review Module - Terminal Display and Interactive Navigation

**Files:**
- Modify: `acts-core/src/review.zig`

- [ ] **Step 1: Add terminal display functions to review.zig**

Append to review.zig:

```zig
// ============================================================
// Terminal Display
// ============================================================

fn qualityStatusChar(status: enum { pass, fail, warn, skipped }) []const u8 {
    return switch (status) {
        .pass => "\x1b[32m✓\x1b[0m",
        .fail => "\x1b[31m✗\x1b[0m",
        .warn => "\x1b[33m⚠\x1b[0m",
        .skipped => "-",
    };
}

fn qualityStatusColor(status: enum { pass, fail, warn, skipped }) []const u8 {
    return switch (status) {
        .pass => ansi.green,
        .fail => ansi.red,
        .warn => ansi.yellow,
        .skipped => ansi.dim,
    };
}

fn displayOverview(writer: anytype, ctx: *const ReviewContext) !void {
    try writer.print("{s}{s}Review: {s} — {s}{s}\n", .{ ansi.bold, ansi.cyan, ctx.task_id, ctx.task_title, ansi.reset });
    try writer.writeAll("=============================================\n\n");

    // Quality gate results
    try writer.print("{s}Quality Gate:{s}  ", .{ ansi.bold, ansi.reset });
    var first_q = true;
    for (ctx.quality_results) |qr| {
        if (!first_q) try writer.writeAll("  ");
        first_q = false;
        try writer.print("{s} {s} ({d}.{d}s){s}", .{
            qualityStatusChar(qr.status),
            @tagName(qr.stage),
            qr.duration_ms / 1000,
            (qr.duration_ms % 1000) / 100,
            ansi.reset,
        });
    }
    try writer.writeAll("\n\n");

    // Rationale
    if (ctx.rationale) |rat| {
        try writer.print("{s}Agent Rationale:{s}\n  \"{s}\"\n\n", .{ ansi.bold, ansi.reset, rat });
    }

    // Previous rejections
    if (ctx.rejections.len > 0) {
        try writer.print("{s}Previous Rejections: {d}{s}\n", .{ ansi.bold, ctx.rejections.len, ansi.reset });
        for (ctx.rejections) |rej| {
            try writer.print("  - Rejected by {s} on {s}\n", .{ rej.approved_by, rej.created_at });
        }
        try writer.writeAll("\n");
    }

    // File list
    try writer.print("{s}Files ({d}):{s}\n", .{ ansi.bold, ctx.files.len, ansi.reset });
    for (ctx.files, 0..) |f, i| {
        try writer.print("  {s}{d}{s}. {s}", .{ ansi.bold, i + 1, ansi.reset, f.file_path });
        // Padding
        const name_len = f.file_path.len;
        const pad = if (name_len < 40) 40 - name_len else 0;
        var p: usize = 0;
        while (p < pad) : (p += 1) try writer.writeByte(' ');

        try writer.print("{s}+{d} -{d}{s}   ", .{ ansi.dim, f.additions, f.deletions, ansi.reset });
        try writer.print("{s}[{s}]{s}   ", .{ riskColor(f.risk), riskLabel(f.risk), ansi.reset });
        try writer.writeAll("\n");
    }
    try writer.writeAll("\n");
}

fn displayFileHeader(writer: anytype, file: *const FileDiff, current: usize, total: usize) !void {
    try writer.print("{s}{s}─── {d}/{d}: {s} ─────────────────────────────────────────────{s}\n", .{
        ansi.cyan, ansi.bold, current, total, file.file_path, ansi.reset,
    });
    try writer.print("{s}Risk: {s}{s}{s} — {s}{s}\n\n", .{
        ansi.bold,
        riskColor(file.risk), riskLabel(file.risk), ansi.reset,
        ansi.dim, fileAnnotation(file), ansi.reset,
    });
}

fn fileAnnotation(file: *const FileDiff) []const u8 {
    if (file.annotation) |a| return a;
    return switch (file.risk) {
        .high => "Modifies critical path code",
        .medium => "Standard change",
        .low => "Low-risk file",
    };
}

fn displayHunk(writer: anytype, hunk: *const DiffHunk, hunk_idx: usize, total_hunks: usize) !void {
    try writer.print("{s}{s}─── Hunk {d}/{d}{s} ───────────────────────────────────────────────{s}\n", .{
        ansi.cyan, ansi.bold, hunk_idx + 1, total_hunks, if (hunk.header.len > 0) hunk.header else "", ansi.reset,
    });

    var hunk_lines = std.mem.split(u8, hunk.lines, "\n");
    while (hunk_lines.next()) |line| {
        if (line.len == 0) continue;
        switch (line[0]) {
            '+' => try writer.print("{s}{s}{s}\n", .{ ansi.green, line, ansi.reset }),
            '-' => try writer.print("{s}{s}{s}\n", .{ ansi.red, line, ansi.reset }),
            '@' => try writer.print("{s}{s}{s}\n", .{ ansi.cyan, line, ansi.reset }),
            else => try writer.print("{s}{s}{s}\n", .{ ansi.dim, line, ansi.reset }),
        }
    }
    try writer.writeAll("\n");
}

fn displayStatusBar(writer: anytype, file_idx: usize, file_count: usize, hunk_idx: usize, hunk_count: usize) !void {
    try writer.print("{s}{s} {s} j/k scroll  ]c/[c hunks  ]f/[f files  a approve  r reject  q quit  ? help {s}\n", .{
        ansi.bg_blue, ansi.white,
        if (file_count > 0) std.fmt.allocPrint(std.heap.page_allocator, "File {d}/{d}, Hunk {d}/{d}", .{ file_idx + 1, file_count, hunk_idx + 1, hunk_count }) catch "",
        ansi.reset,
    });
}

fn displayHelp(writer: anytype) !void {
    try writer.writeAll("\n");
    try writer.print("{s}Navigation:{s}\n", .{ ansi.bold, ansi.reset });
    try writer.writeAll("  j/k          Line down/up\n");
    try writer.writeAll("  Ctrl-d/u     Half-page down/up\n");
    try writer.writeAll("  gg/G         Go to top/bottom\n");
    try writer.print("{s}Hunks:{s}\n", .{ ansi.bold, ansi.reset });
    try writer.writeAll("  ]c/[c        Next/previous hunk\n");
    try writer.print("{s}Files:{s}\n", .{ ansi.bold, ansi.reset });
    try writer.writeAll("  ]f/[f        Next/previous file\n");
    try writer.writeAll("  :files       Show file overview\n");
    try writer.print("{s}Actions:{s}\n", .{ ansi.bold, ansi.reset });
    try writer.writeAll("  a            Approve and quit\n");
    try writer.writeAll("  r            Reject and quit\n");
    try writer.writeAll("  q            Quit without decision\n");
    try writer.writeAll("  :qa          Approve and quit (alt)\n");
    try writer.writeAll("  :cq          Reject and quit (alt)\n");
    try writer.print("{s}Context:{s}\n", .{ ansi.bold, ansi.reset });
    try writer.writeAll("  Ctrl-g       Show position\n");
    try writer.writeAll("  ?            Toggle this help\n");
    try writer.writeAll("\nPress any key to continue...\n");
}

// ============================================================
// Raw Terminal Mode
// ============================================================

pub fn enterRawMode() !std.posix.termios {
    const stdin = std.io.getStdIn();
    const orig = try std.posix.tcgetattr(stdin.handle);
    var raw = orig;
    raw.lflag &= ~@as(std.posix.tcflag_t, @bitCast(std.posix.Termios.Lflag.ECHO | std.posix.Termios.Lflag.ICANON));
    raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
    raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
    try std.posix.tcsetattr(stdin.handle, .FLUSH, raw);
    return orig;
}

pub fn restoreMode(orig: std.posix.termios) void {
    const stdin = std.io.getStdIn();
    std.posix.tcsetattr(stdin.handle, .FLUSH, orig) catch {};
}

// ============================================================
// Key Parsing
// ============================================================

pub const Key = union(enum) {
    char: u8,
    escape_sequence: []const u8,
    ctrl_g,
    ctrl_d,
    ctrl_u,
    enter,
    timeout,
};

fn readKey(allocator: std.mem.Allocator) !Key {
    const stdin = std.io.getStdIn();
    var buf: [1]u8 = undefined;
    const bytes_read = try stdin.read(&buf);
    if (bytes_read == 0) return Key{ .timeout = {} };

    const byte = buf[0];

    if (byte == 27) { // ESC
        // Check for escape sequence
        var seq_buf: [16]u8 = undefined;
        var seq_len: usize = 1;
        seq_buf[0] = 27;

        // Non-blocking read for next bytes
        const next_read = stdin.read(seq_buf[1..]) catch 0;
        if (next_read > 0) {
            seq_len += next_read;
            const seq = try allocator.dupe(u8, seq_buf[0..seq_len]);
            return Key{ .escape_sequence = seq };
        }
        return Key{ .char = 27 };
    }

    if (byte == 3) return Key{ .ctrl_g = {} }; // Ctrl-C, treat as quit
    if (byte == 7) return Key{ .ctrl_g = {} }; // Ctrl-G
    if (byte == 4) return Key{ .ctrl_d = {} }; // Ctrl-D
    if (byte == 21) return Key{ .ctrl_u = {} }; // Ctrl-U
    if (byte == 13 or byte == 10) return Key{ .enter = {} };

    return Key{ .char = byte };
}

// ============================================================
// Interactive Review Loop
// ============================================================

pub fn interactiveReview(allocator: std.mem.Allocator, ctx: *const ReviewContext) !enum { approved, rejected, cancelled } {
    const stdout = std.io.getStdOut().writer();

    // Check terminal size
    var winsize: std.posix.winsize = undefined;
    const ws_rc = std.posix.ioctl(std.io.getStdOut().handle, std.posix.T.IOCGWINSZ, @intFromPtr(&winsize));
    if (ws_rc != 0 or winsize.ws_col < 40) {
        try stdout.writeAll("Error: Terminal too small for review (minimum 40 columns)\n");
        return .cancelled;
    }

    // Enter raw mode
    const orig_mode = enterRawMode() catch |err| {
        try stdout.print("Error: Could not enter raw mode: {}\n", .{err});
        return .cancelled;
    };
    defer restoreMode(orig_mode);

    // Clear screen and hide cursor
    try stdout.writeAll(ansi.clear);
    try stdout.writeAll(ansi.cursor_hide);
    defer {
        stdout.writeAll(ansi.cursor_show) catch {};
        stdout.writeAll(ansi.reset) catch {};
    }

    var current_file: usize = 0;
    var current_hunk: usize = 0;
    var scroll_offset: usize = 0;
    var show_help = false;
    var prev_char: ?u8 = null; // For multi-key sequences (gg, ]c, [c, ]f, [f)

    // Count total hunks
    var total_hunks: usize = 0;
    for (ctx.files) |f| {
        total_hunks += f.hunks.len;
    }

    // Main loop
    while (true) {
        // Clear and redraw
        try stdout.writeAll(ansi.clear);

        if (show_help) {
            try displayHelp(stdout);
        } else if (ctx.files.len == 0) {
            try displayOverview(stdout, ctx);
            try stdout.writeAll("No files recorded for this task. Review manually.\n\n");
            try displayStatusBar(stdout, 0, 0, 0, 0);
        } else {
            try displayOverview(stdout, ctx);

            const file = &ctx.files[current_file];
            try displayFileHeader(stdout, file, current_file + 1, ctx.files.len);

            if (file.hunks.len > 0) {
                if (current_hunk < file.hunks.len) {
                    try displayHunk(stdout, &file.hunks[current_hunk], current_hunk, file.hunks.len);
                }
            } else {
                try stdout.writeAll("No hunks detected for this file.\n\n");
            }

            try displayStatusBar(stdout, current_file, ctx.files.len, current_hunk, file.hunks.len);
        }

        // Read key
        const key = readKey(allocator) catch continue;

        switch (key) {
            .char => |c| {
                // Check for two-key sequences with previous char
                if (prev_char) |prev| {
                    // ]c = next hunk, [c = prev hunk, ]f = next file, [f = prev file
                    if ((prev == ']' or prev == '[') and (c == 'c' or c == 'f')) {
                        if (prev == ']' and c == 'c') {
                            // Next hunk
                            if (ctx.files.len > 0) {
                                const file = &ctx.files[current_file];
                                if (current_hunk + 1 < file.hunks.len) {
                                    current_hunk += 1;
                                } else if (current_file + 1 < ctx.files.len) {
                                    current_file += 1;
                                    current_hunk = 0;
                                }
                            }
                        } else if (prev == '[' and c == 'c') {
                            // Prev hunk
                            if (current_hunk > 0) {
                                current_hunk -= 1;
                            } else if (current_file > 0) {
                                current_file -= 1;
                                const pf = &ctx.files[current_file];
                                if (pf.hunks.len > 0) current_hunk = pf.hunks.len - 1;
                            }
                        } else if (prev == ']' and c == 'f') {
                            // Next file
                            if (current_file + 1 < ctx.files.len) {
                                current_file += 1;
                                current_hunk = 0;
                            }
                        } else if (prev == '[' and c == 'f') {
                            // Prev file
                            if (current_file > 0) {
                                current_file -= 1;
                                current_hunk = 0;
                            }
                        }
                        prev_char = null;
                        continue;
                    }
                    // gg = go to top
                    if (prev == 'g' and c == 'g') {
                        current_file = 0;
                        current_hunk = 0;
                        scroll_offset = 0;
                        prev_char = null;
                        continue;
                    }
                }

                switch (c) {
                    'a' => return .approved,
                    'r' => return .rejected,
                    'q' => return .cancelled,
                    '?', 'h' => show_help = !show_help,
                    'j' => scroll_offset += 1,
                    'k' => if (scroll_offset > 0) scroll_offset -= 1,
                    'g' => {
                        // First g of gg - store and wait for next char
                        prev_char = 'g';
                        continue;
                    },
                    'G' => {
                        // Go to last hunk of last file
                        if (ctx.files.len > 0) {
                            current_file = ctx.files.len - 1;
                            const last_file = &ctx.files[current_file];
                            if (last_file.hunks.len > 0) {
                                current_hunk = last_file.hunks.len - 1;
                            }
                        }
                    },
                    '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                        const num = c - '0';
                        if (num <= ctx.files.len and num > 0) {
                            current_file = num - 1;
                            current_hunk = 0;
                        }
                    },
                    ']', '[' => {
                        // First char of ]c/[c/]f/[f - store and wait
                        prev_char = c;
                        continue;
                    },
                    ':' => {
                        // Ex-mode: read command
                        try stdout.writeAll("\n:");
                        var cmd_buf: [32]u8 = undefined;
                        var cmd_len: usize = 0;
                        while (cmd_len < cmd_buf.len) : (cmd_len += 1) {
                            const k = readKey(allocator) catch continue;
                            if (k == .enter) break;
                            if (k == .char) |ch| {
                                cmd_buf[cmd_len] = ch;
                                try stdout.writeByte(ch);
                            }
                        }
                        const cmd = cmd_buf[0..cmd_len];
                        if (std.mem.eql(u8, cmd, "qa")) return .approved;
                        if (std.mem.eql(u8, cmd, "cq")) return .rejected;
                        if (std.mem.eql(u8, cmd, "q")) return .cancelled;
                        if (std.mem.eql(u8, cmd, "files")) {
                            // Show file overview - already shown at top
                        }
                        if (std.mem.eql(u8, cmd, "n") and current_file + 1 < ctx.files.len) {
                            current_file += 1;
                            current_hunk = 0;
                        }
                        if (std.mem.eql(u8, cmd, "N") and current_file > 0) {
                            current_file -= 1;
                            current_hunk = 0;
                        }
                    },
                    else => {},
                }
            },
            .escape_sequence => |seq| {
                defer allocator.free(seq);
                // Handle arrow keys and other terminal escape sequences
                // ESC [ A = Up, ESC [ B = Down, ESC [ C = Right, ESC [ D = Left
                if (seq.len >= 3 and seq[0] == 27 and seq[1] == 91) {
                    switch (seq[2]) {
                        'A' => if (scroll_offset > 0) scroll_offset -= 1,
                        'B' => scroll_offset += 1,
                        else => {},
                    }
                }
            },
            .ctrl_g => {
                // Show position
                try stdout.writeAll(ansi.clear);
                try displayOverview(stdout, ctx);
                try stdout.print("\n{s}Position: File {d}/{d}, Hunk {d}/{d}{s}\n\nPress any key...", .{
                    ansi.bold, current_file + 1, ctx.files.len, current_hunk + 1,
                    if (ctx.files.len > 0) ctx.files[current_file].hunks.len else 0,
                    ansi.reset,
                });
                _ = readKey(allocator) catch continue;
            },
            .ctrl_d => scroll_offset += 10,
            .ctrl_u => if (scroll_offset >= 10) scroll_offset -= 10 else scroll_offset = 0,
            .enter => {},
            .timeout => {},
        }

        // Reset prev_char for non-matched keys (already handled above for matched sequences)
        if (prev_char != null) {
            // Only reset if we didn't continue above (i.e., this was a standalone key)
            // The continue statements above prevent reaching here for multi-key sequences
            prev_char = null;
        }
    }
}

// ============================================================
// Main Entry Point
// ============================================================

pub fn run(allocator: std.mem.Allocator, database: *db.Database, task_id: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    // Verify task has approved review gate
    const has_review = try database.hasApprovedReviewGate(task_id);
    if (has_review) {
        try stdout.print("Task {s} already has an approved task-review gate.\n", .{task_id});
        return;
    }

    // Gather context
    var ctx = try gatherContext(allocator, database, task_id);
    defer freeContext(allocator, ctx);

    // Check if task has no files
    if (ctx.files.len == 0) {
        try stdout.print("\nReviewing task: {s}\n", .{ctx.task_id});
        try stdout.writeAll("========================================\n\n");
        try stdout.writeAll("No files recorded for this task.\n");
        try stdout.writeAll("Review the changes manually, then:\n");
        try stdout.print("  acts approve {s}   # or: acts reject {s}\n\n", .{ ctx.task_id, ctx.task_id });
    }

    // Run interactive review
    const decision = try interactiveReview(allocator, &ctx);

    const user = std.process.getEnvVarOwned(allocator, "USER") catch blk: {
        break :blk try allocator.dupe(u8, "developer");
    };
    defer allocator.free(user);

    switch (decision) {
        .approved => {
            try database.addGate(task_id, "task-review", "approved", user);
            try stdout.print("\n{s}Task-review gate approved by {s}.{s}\n", .{ ansi.green, user, ansi.reset });
        },
        .rejected => {
            try database.addGate(task_id, "task-review", "changes_requested", null);
            try stdout.writeAll("\nChanges requested. Gate marked as 'changes_requested'.\n");
        },
        .cancelled => {
            try stdout.writeAll("\nReview cancelled. No changes made.\n");
        },
    }
}
```

- [ ] **Step 2: Verify review.zig compiles**

Run: `cd acts-core && zig build 2>&1`
Expected: Compiles without errors

---

### Task 5: Wire Up main.zig

**Files:**
- Modify: `acts-core/src/main.zig`

- [ ] **Step 1: Replace handleReview function**

Find the existing `handleReview` function (lines 509-646 in main.zig) and replace it entirely with:

```zig
// ============================================================
// Review (enhanced HRE)
// ============================================================

fn handleReview(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts review <task-id>\n", .{});
        std.process.exit(1);
    }
    const task_id = args[0];

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    // Verify task exists
    _ = database.getTask(allocator, task_id) catch |err| {
        if (err == error.TaskNotFound) {
            std.debug.print("Error: Task {s} not found\n", .{task_id});
            std.process.exit(1);
        }
        std.debug.print("Error: {}\n", .{err});
        std.process.exit(1);
    };

    const review = @import("review.zig");
    review.run(allocator, &database, task_id) catch |err| {
        std.debug.print("Error during review: {}\n", .{err});
        std.process.exit(1);
    };
}
```

- [ ] **Step 2: Add review-queue command if not present**

Check if `handleReviewQueue` exists in main.zig. If not, add after `handleReject`:

```zig
// ============================================================
// Review Queue
// ============================================================

fn handleReviewQueue(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var story_id: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--story") and i + 1 < args.len) {
            story_id = args[i + 1];
            i += 1;
        }
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const stdout = std.io.getStdOut().writer();

    var stmt: ?*c.sqlite3_stmt = null;
    const sql = "SELECT rq.task_id, rq.requested_by, rq.requested_at, rq.status, t.title " ++
        "FROM review_queue rq JOIN tasks t ON t.id = rq.task_id " ++
        "WHERE rq.status = 'pending' " ++
        "ORDER BY rq.requested_at ASC";
    const rc = c.sqlite3_prepare_v2(database.db, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        std.debug.print("Error: Could not query review queue\n", .{});
        std.process.exit(1);
    }
    defer _ = c.sqlite3_finalize(stmt);

    if (story_id) |sid| {
        // Filter by story - rebuild query
        _ = c.sqlite3_finalize(stmt);
        const filtered_sql = "SELECT rq.task_id, rq.requested_by, rq.requested_at, rq.status, t.title " ++
            "FROM review_queue rq JOIN tasks t ON t.id = rq.task_id " ++
            "WHERE rq.status = 'pending' AND t.story_id = ? " ++
            "ORDER BY rq.requested_at ASC";
        _ = c.sqlite3_prepare_v2(database.db, filtered_sql, -1, &stmt, null);
        _ = c.sqlite3_bind_text(stmt, 1, sid.ptr, @intCast(sid.len), c.SQLITE_STATIC);
    }

    try stdout.print("{s}{s:<12} {s:<20} {s:<12} {s}{s}\n", .{
        "\x1b[1m", "Task", "Requested By", "Date", "Status", "Title", "\x1b[0m",
    });
    try stdout.writeAll("─────────────────────────────────────────────────────────────\n");

    var count: usize = 0;
    while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
        count += 1;
        const tid = std.mem.span(c.sqlite3_column_text(stmt, 0));
        const by = std.mem.span(c.sqlite3_column_text(stmt, 1));
        const at = std.mem.span(c.sqlite3_column_text(stmt, 2));
        const status = std.mem.span(c.sqlite3_column_text(stmt, 3));
        const title = std.mem.span(c.sqlite3_column_text(stmt, 4));

        try stdout.print("{s:<12} {s:<20} {s:<12} {s:<10} {s}\n", .{
            tid, by, at, status, title,
        });
    }

    if (count == 0) {
        try stdout.writeAll("\nNo pending reviews.\n");
    } else {
        try stdout.print("\n{d} pending review(s).\n", .{count});
    }
}
```

- [ ] **Step 3: Verify main.zig compiles**

Run: `cd acts-core && zig build 2>&1`
Expected: Compiles without errors

- [ ] **Step 4: Verify acts review command works**

Run: `cd acts-core && ./zig-out/bin/acts --help | grep review`
Expected: Shows `review <task-id>             Review task changes (enhanced HRE)`

---

### Task 6: Integration Test and Build Verification

**Files:**
- No new files

- [ ] **Step 1: Build release binary**

Run: `cd acts-core && zig build release -Dversion=1.1.0 2>&1`
Expected: Builds successfully

- [ ] **Step 2: Test help output**

Run: `./zig-out/bin/acts --help`
Expected: Shows all commands including review with updated description

- [ ] **Step 3: Test quality detection in a test project**

Run:
```bash
cd /tmp && mkdir -p acts-hre-test && cd acts-hre-test && git init
echo '{"name":"test"}' > package.json
../../acts-core/zig-out/bin/acts init TEST-1
../../acts-core/zig-out/bin/acts task create T1 --title "Test task" --story TEST-1
../../acts-core/zig-out/bin/acts gate add --task T1 --type approve --status approved --by tester
../../acts-core/zig-out/bin/acts task update T1 --status IN_PROGRESS --assigned-to tester
echo "console.log('hello');" > index.js
git add index.js
../../acts-core/zig-out/bin/acts review T1
```
Expected: Shows review overview with quality gate detection for package.json (npm test, npm run lint, etc.), file list with index.js, and interactive navigation

- [ ] **Step 4: Cross-compile verification**

Run: `cd acts-core && zig build cross -Dversion=1.1.0 2>&1`
Expected: All 4 cross-compiled binaries build successfully

- [ ] **Step 5: Commit**

```bash
git add acts-core/src/quality.zig acts-core/src/review.zig acts-core/src/db.zig acts-core/src/main.zig
git commit -m "feat: implement Human Review Experience (HRE) with vim navigation and quality gates"
```
