const std = @import("std");

pub const QualityStage = enum { Test, Lint, Typecheck, Build };

pub const QualityStatus = enum { pass, fail, warn, skipped };

pub const QualityResult = struct {
    stage: QualityStage,
    command: []const u8,
    status: QualityStatus,
    exit_code: i32,
    output: []const u8,
    duration_ms: u64,
};

pub const QualityConfig = struct {
    test_cmd: ?[]const u8 = null,
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
        .{ .file = "Makefile", .config = QualityConfig{ .test_cmd = "make test", .lint = "make lint", .typecheck = "make check", .build = "make build" } },
        .{ .file = "package.json", .config = QualityConfig{ .test_cmd = "npm test", .lint = "npm run lint", .typecheck = "npx tsc --noEmit", .build = "npm run build" } },
        .{ .file = "Cargo.toml", .config = QualityConfig{ .test_cmd = "cargo test", .lint = "cargo clippy", .typecheck = "cargo check", .build = "cargo build" } },
        .{ .file = "go.mod", .config = QualityConfig{ .test_cmd = "go test ./...", .lint = "golangci-lint run", .typecheck = null, .build = "go build ./..." } },
        .{ .file = "pyproject.toml", .config = QualityConfig{ .test_cmd = "pytest", .lint = "ruff check .", .typecheck = "mypy .", .build = "python -m build" } },
        .{ .file = "requirements.txt", .config = QualityConfig{ .test_cmd = "pytest", .lint = "ruff check .", .typecheck = "mypy .", .build = null } },
        .{ .file = "pom.xml", .config = QualityConfig{ .test_cmd = "mvn test", .lint = "mvn checkstyle:check", .typecheck = null, .build = "mvn compile" } },
        .{ .file = "build.gradle", .config = QualityConfig{ .test_cmd = "gradle test", .lint = "gradle check", .typecheck = null, .build = "gradle build" } },
        .{ .file = "mix.exs", .config = QualityConfig{ .test_cmd = "mix test", .lint = "mix credo", .typecheck = null, .build = "mix compile" } },
    };

    for (indicators) |ind| {
        std.fs.cwd().access(ind.file, .{}) catch continue;
        return QualityConfig{
            .test_cmd = if (ind.config.test_cmd) |t| try allocator.dupe(u8, t) else null,
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
        if (v == .string and v.string.len > 0) config.test_cmd = try allocator.dupe(u8, v.string);
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

/// Run a single quality gate command, return result
pub fn runStage(allocator: std.mem.Allocator, stage: QualityStage, command: ?[]const u8) !QualityResult {
    if (command == null) {
        return QualityResult{
            .stage = stage,
            .command = try allocator.dupe(u8, "skipped"),
            .status = .skipped,
            .exit_code = 0,
            .output = try allocator.dupe(u8, ""),
            .duration_ms = 0,
        };
    }

    const cmd = command.?;
    const start = try std.time.Instant.now();

    // Parse command into argv (simple space split)
    var argv_list = std.ArrayList([]const u8).init(allocator);
    defer argv_list.deinit();

    var iter = std.mem.split(u8, cmd, " ");
    while (iter.next()) |part| {
        if (part.len > 0) try argv_list.append(part);
    }

    if (argv_list.items.len == 0) {
        return QualityResult{
            .stage = stage,
            .command = try allocator.dupe(u8, cmd),
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
            .command = try allocator.dupe(u8, cmd),
            .status = .fail,
            .exit_code = -1,
            .output = try std.fmt.allocPrint(allocator, "Failed to spawn: {}", .{err}),
            .duration_ms = 0,
        };
    };

    // Read stdout/stderr BEFORE wait to avoid pipe deadlock
    var output_buf = std.ArrayList(u8).init(allocator);
    errdefer output_buf.deinit();

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

    const wait_result = child.wait() catch {
        const output = output_buf.toOwnedSlice() catch "";
        return QualityResult{
            .stage = stage,
            .command = try allocator.dupe(u8, cmd),
            .status = .warn,
            .exit_code = -1,
            .output = output,
            .duration_ms = 0,
        };
    };

    const elapsed = start.since(try std.time.Instant.now()) / std.time.ns_per_ms;

    const exit_code: i32 = switch (wait_result) {
        .Exited => |code| @as(i32, @intCast(code)),
        else => -1,
    };
    const status: QualityStatus = if (exit_code == 0) .pass else if (exit_code >= 100) .warn else .fail;

    return QualityResult{
        .stage = stage,
        .command = try allocator.dupe(u8, cmd),
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
        .{ .stage = .Test, .cmd = config.test_cmd },
        .{ .stage = .Lint, .cmd = config.lint },
        .{ .stage = .Typecheck, .cmd = config.typecheck },
        .{ .stage = .Build, .cmd = config.build },
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
