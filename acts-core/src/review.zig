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

pub const RiskLevel = enum { low, medium, high };

pub const FileDiff = struct {
    file_path: []const u8,
    additions: usize,
    deletions: usize,
    hunks: []DiffHunk,
    risk: RiskLevel,
    annotation: ?[]const u8 = null,
};

pub const ReviewContext = struct {
    task_id: []const u8,
    task_title: []const u8,
    rationale: ?[]const u8 = null,
    rejections: []db.Database.Rejection,
    files: []FileDiff,
    quality_results: []quality.QualityResult,
};

// ============================================================
// ANSI Colors
// ============================================================

pub const ansi = struct {
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

fn assessRisk(file_path: []const u8, additions: usize, deletions: usize) RiskLevel {
    var lower_buf: [256]u8 = undefined;
    const lower = if (file_path.len <= lower_buf.len)
        blk: {
            const copied = std.ascii.lowerString(&lower_buf, file_path);
            break :blk copied;
        }
    else
        file_path;

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

pub fn riskLabel(risk: RiskLevel) []const u8 {
    return switch (risk) {
        .low => "LOW",
        .medium => "MEDIUM",
        .high => "HIGH",
    };
}

pub fn riskColor(risk: RiskLevel) []const u8 {
    return switch (risk) {
        .low => ansi.green,
        .medium => ansi.yellow,
        .high => ansi.red,
    };
}

// ============================================================
// Diff Parsing
// ============================================================

fn parseDiff(allocator: std.mem.Allocator, diff_output: []const u8) ![]FileDiff {
    var result = std.ArrayList(FileDiff).init(allocator);
    errdefer {
        for (result.items) |f| {
            allocator.free(f.file_path);
            for (f.hunks) |h| allocator.free(h.lines);
            allocator.free(f.hunks);
        }
        result.deinit();
    }

    var lines = std.mem.split(u8, diff_output, "\n");
    var current_file: ?[]const u8 = null;
    var current_additions: usize = 0;
    var current_deletions: usize = 0;
    var hunk_list = std.ArrayList(DiffHunk).init(allocator);
    defer {
        for (hunk_list.items) |h| allocator.free(h.lines);
        hunk_list.deinit();
    }
    var hunk_lines = std.ArrayList(u8).init(allocator);
    defer hunk_lines.deinit();
    var in_hunk = false;

    // Helper to finalize current file — builds hunks slice WITHOUT toOwnedSlice UB
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

            // If there's a trailing partial hunk, finalize it first
            if (ih and hlines.items.len > 0) {
                const last_hunk_lines = try alloc.dupe(u8, hlines.items);
                try hl.append(DiffHunk{
                    .header = "",
                    .old_start = 0,
                    .new_start = 0,
                    .old_count = 0,
                    .new_count = 0,
                    .lines = last_hunk_lines,
                });
                hlines.clearRetainingCapacity();
            }

            // Now safely take ownership of hunks
            const hunks = try hl.toOwnedSlice();

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

    var task_title: []const u8 = try allocator.dupe(u8, task_id);
    errdefer allocator.free(task_title);
    if (parsed.value == .object) {
        if (parsed.value.object.get("title")) |t| {
            if (t == .string) {
                allocator.free(task_title);
                task_title = try allocator.dupe(u8, t.string);
            }
        }
    }

    // Get rationale
    const rationale = try database.getRationale(allocator, task_id);
    errdefer if (rationale) |r| allocator.free(r);

    // Get previous rejections
    const rejections = try database.getPreviousRejections(allocator, task_id);
    errdefer db.Database.freeRejections(allocator, rejections);

    // Get files
    const file_paths = try database.getFilesForTask(allocator, task_id);
    errdefer db.Database.freeFiles(allocator, file_paths);

    // Run quality gates
    const quality_results = try quality.runAllQualityGates(allocator);
    errdefer quality.freeQualityResults(allocator, quality_results);

    // Get diff — run git and properly wait to avoid zombies
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

    // Read stdout first (before wait to avoid pipe deadlock)
    const diff_output = if (diff_child.stdout) |out|
        out.reader().readAllAlloc(allocator, 262144) catch ""
    else
        "";
    defer allocator.free(diff_output);

    // Wait for child to finish (prevents zombie)
    _ = diff_child.wait() catch {};

    const file_diffs = try parseDiff(allocator, diff_output);
    errdefer freeFileDiffs(allocator, file_diffs);

    // Free file_paths now that we've parsed the diff
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

// ============================================================
// Terminal Display
// ============================================================

fn qualityStatusChar(status: quality.QualityStatus) []const u8 {
    return switch (status) {
        .pass => "\x1b[32m✓\x1b[0m",
        .fail => "\x1b[31m✗\x1b[0m",
        .warn => "\x1b[33m⚠\x1b[0m",
        .skipped => "-",
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
    try writer.print("{s}Risk: {s}{s}{s} — {s}{s}{s}\n\n", .{
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
        switch (line.len) {
            0 => try writer.writeAll("\n"),
            else => switch (line[0]) {
                '+' => try writer.print("{s}{s}{s}\n", .{ ansi.green, line, ansi.reset }),
                '-' => try writer.print("{s}{s}{s}\n", .{ ansi.red, line, ansi.reset }),
                '@' => try writer.print("{s}{s}{s}\n", .{ ansi.cyan, line, ansi.reset }),
                else => try writer.print("{s}{s}{s}\n", .{ ansi.dim, line, ansi.reset }),
            },
        }
    }
    try writer.writeAll("\n");
}

fn displayStatusBar(writer: anytype, file_idx: usize, file_count: usize, hunk_idx: usize, hunk_count: usize) !void {
    var pos_buf: [64]u8 = undefined;
    const pos_str = if (file_count > 0)
        std.fmt.bufPrint(&pos_buf, "File {d}/{d}, Hunk {d}/{d}", .{ file_idx + 1, file_count, hunk_idx + 1, hunk_count }) catch ""
    else
        "";
    try writer.print("{s}{s} {s} j/k scroll  ]c/[c hunks  ]f/[f files  a approve  r reject  q quit  ? help {s}\n", .{
        ansi.bg_blue, ansi.white, pos_str, ansi.reset,
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
    @field(raw.lflag, "ECHO") = false;
    @field(raw.lflag, "ICANON") = false;
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
    ctrl_c,
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

    if (byte == 27) {
        var seq_buf: [16]u8 = undefined;
        var seq_len: usize = 1;
        seq_buf[0] = 27;
        const next_read = stdin.read(seq_buf[1..]) catch 0;
        if (next_read > 0) {
            seq_len += next_read;
            const seq = try allocator.dupe(u8, seq_buf[0..seq_len]);
            return Key{ .escape_sequence = seq };
        }
        return Key{ .char = 27 };
    }

    if (byte == 3) return Key{ .ctrl_c = {} }; // Ctrl-C
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
    const ws_rc = std.os.linux.ioctl(std.io.getStdOut().handle, std.os.linux.T.IOCGWINSZ, @intFromPtr(&winsize));
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
    var prev_char: ?u8 = null;

    // Main loop
    while (true) {
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

        const key = readKey(allocator) catch continue;

        switch (key) {
            .char => |ch| {
                if (prev_char) |prev| {
                    if ((prev == ']' or prev == '[') and (ch == 'c' or ch == 'f')) {
                        if (prev == ']' and ch == 'c') {
                            if (ctx.files.len > 0) {
                                const file = &ctx.files[current_file];
                                if (current_hunk + 1 < file.hunks.len) {
                                    current_hunk += 1;
                                } else if (current_file + 1 < ctx.files.len) {
                                    current_file += 1;
                                    current_hunk = 0;
                                }
                            }
                        } else if (prev == '[' and ch == 'c') {
                            if (current_hunk > 0) {
                                current_hunk -= 1;
                            } else if (current_file > 0) {
                                current_file -= 1;
                                const pf = &ctx.files[current_file];
                                if (pf.hunks.len > 0) current_hunk = pf.hunks.len - 1;
                            }
                        } else if (prev == ']' and ch == 'f') {
                            if (current_file + 1 < ctx.files.len) {
                                current_file += 1;
                                current_hunk = 0;
                            }
                        } else if (prev == '[' and ch == 'f') {
                            if (current_file > 0) {
                                current_file -= 1;
                                current_hunk = 0;
                            }
                        }
                        prev_char = null;
                        continue;
                    }
                    if (prev == 'g' and ch == 'g') {
                        current_file = 0;
                        current_hunk = 0;
                        scroll_offset = 0;
                        prev_char = null;
                        continue;
                    }
                }

                switch (ch) {
                    'a' => return .approved,
                    'r' => return .rejected,
                    'q' => return .cancelled,
                    '?', 'h' => { show_help = !show_help; },
                    'j' => { scroll_offset += 1; },
                    'k' => { if (scroll_offset > 0) scroll_offset -= 1; },
                    'g' => {
                        prev_char = 'g';
                        continue;
                    },
                    'G' => {
                        if (ctx.files.len > 0) {
                            current_file = ctx.files.len - 1;
                            const last_file = &ctx.files[current_file];
                            if (last_file.hunks.len > 0) {
                                current_hunk = last_file.hunks.len - 1;
                            }
                        }
                    },
                    '1', '2', '3', '4', '5', '6', '7', '8', '9' => {
                        const num = ch - '0';
                        if (num <= ctx.files.len and num > 0) {
                            current_file = num - 1;
                            current_hunk = 0;
                        }
                    },
                    ']', '[' => {
                        prev_char = ch;
                        continue;
                    },
                    ':' => {
                        try stdout.writeAll("\n:");
                        var cmd_buf: [32]u8 = undefined;
                        var cmd_len: usize = 0;
                        while (cmd_len < cmd_buf.len) : (cmd_len += 1) {
                            const k = readKey(allocator) catch continue;
                            if (k == .enter) break;
                            if (k == .char) {
                                cmd_buf[cmd_len] = k.char;
                                try stdout.writeByte(k.char);
                            }
                        }
                        const cmd = cmd_buf[0..cmd_len];
                        if (std.mem.eql(u8, cmd, "qa")) return .approved;
                        if (std.mem.eql(u8, cmd, "cq")) return .rejected;
                        if (std.mem.eql(u8, cmd, "q")) return .cancelled;
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
                if (seq.len >= 3 and seq[0] == 27 and seq[1] == 91) {
                    switch (seq[2]) {
                        'A' => { if (scroll_offset > 0) scroll_offset -= 1; },
                        'B' => { scroll_offset += 1; },
                        else => {},
                    }
                }
            },
            .ctrl_g => {
                try stdout.writeAll(ansi.clear);
                try displayOverview(stdout, ctx);
                try stdout.print("\n{s}Position: File {d}/{d}, Hunk {d}/{d}{s}\n\nPress any key...", .{
                    ansi.bold, current_file + 1, ctx.files.len, current_hunk + 1,
                    if (ctx.files.len > 0) ctx.files[current_file].hunks.len else 0,
                    ansi.reset,
                });
                _ = readKey(allocator) catch continue;
            },
            .ctrl_c => return .cancelled,
            .ctrl_d => scroll_offset += 10,
            .ctrl_u => { if (scroll_offset >= 10) scroll_offset -= 10 else scroll_offset = 0; },
            .enter => {},
            .timeout => {},
        }

        if (prev_char != null) {
            prev_char = null;
        }
    }
}

// ============================================================
// Main Entry Point
// ============================================================

pub fn run(allocator: std.mem.Allocator, database: *db.Database, task_id: []const u8) !void {
    const stdout = std.io.getStdOut().writer();

    const has_review = try database.hasApprovedReviewGate(task_id);
    if (has_review) {
        try stdout.print("Task {s} already has an approved task-review gate.\n", .{task_id});
        return;
    }

    var ctx = try gatherContext(allocator, database, task_id);
    defer freeContext(allocator, ctx);

    if (ctx.files.len == 0) {
        try stdout.print("\nReviewing task: {s}\n", .{ctx.task_id});
        try stdout.writeAll("========================================\n\n");
        try stdout.writeAll("No files recorded for this task.\n");
        try stdout.writeAll("Review the changes manually, then:\n");
        try stdout.print("  acts approve {s}   # or: acts reject {s}\n\n", .{ ctx.task_id, ctx.task_id });
    }

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
