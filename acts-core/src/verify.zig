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

/// Detect project type and return quality gate commands.
/// Order matters: more specific language indicators (package.json, Cargo.toml,
/// go.mod, …) are checked BEFORE a bare Makefile, because a Makefile often
/// contains unrelated targets. If the project has both, we prefer the language
/// toolchain's conventions.
pub fn detectQualityGate(allocator: std.mem.Allocator) !QualityConfig {
    const indicators = [_]struct {
        file: []const u8,
        config: QualityConfig,
    }{
        .{ .file = "package.json", .config = QualityConfig{ .test_cmd = "npm test", .lint = "npm run lint", .typecheck = "npx tsc --noEmit", .build = "npm run build" } },
        .{ .file = "Cargo.toml", .config = QualityConfig{ .test_cmd = "cargo test", .lint = "cargo clippy", .typecheck = "cargo check", .build = "cargo build" } },
        .{ .file = "go.mod", .config = QualityConfig{ .test_cmd = "go test ./...", .lint = "golangci-lint run", .typecheck = null, .build = "go build ./..." } },
        .{ .file = "pyproject.toml", .config = QualityConfig{ .test_cmd = "pytest", .lint = "ruff check .", .typecheck = "mypy .", .build = "python -m build" } },
        .{ .file = "requirements.txt", .config = QualityConfig{ .test_cmd = "pytest", .lint = "ruff check .", .typecheck = "mypy .", .build = null } },
        .{ .file = "pom.xml", .config = QualityConfig{ .test_cmd = "mvn test", .lint = "mvn checkstyle:check", .typecheck = null, .build = "mvn compile" } },
        .{ .file = "build.gradle", .config = QualityConfig{ .test_cmd = "gradle test", .lint = "gradle check", .typecheck = null, .build = "gradle build" } },
        .{ .file = "mix.exs", .config = QualityConfig{ .test_cmd = "mix test", .lint = "mix credo", .typecheck = null, .build = "mix compile" } },
        .{ .file = "Makefile", .config = QualityConfig{ .test_cmd = "make test", .lint = "make lint", .typecheck = "make check", .build = "make build" } },
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

/// Run a single quality gate command, return result.
/// Uses a poll-based reader with a deadline so commands that spawn background
/// processes (which inherit the stdout/stderr pipe and keep it open) cannot
/// hang ACTS forever. On timeout the child is killed and a failure is returned.
pub fn runStage(allocator: std.mem.Allocator, stage: QualityStage, command: ?[]const u8) !QualityResult {
    const stage_timeout_ms = stageTimeoutMs();
    return runStageTimeout(allocator, stage, command, stage_timeout_ms);
}

fn stageTimeoutMs() u64 {
    // Allow override via ACTS_VERIFY_TIMEOUT_MS; default 5 minutes per stage.
    if (std.posix.getenv("ACTS_VERIFY_TIMEOUT_MS")) |s| {
        return std.fmt.parseInt(u64, s, 10) catch default_verify_timeout_ms;
    }
    return default_verify_timeout_ms;
}

const default_verify_timeout_ms: u64 = 300_000; // 5 minutes

/// Set O_NONBLOCK on a file descriptor so a pipe read returns error.WouldBlock
/// instead of blocking when the pipe is open but empty (e.g. a background
/// process inherited the write end).
fn setNonBlocking(fd: std.posix.fd_t) !void {
    const flags = try std.posix.fcntl(fd, std.posix.F.GETFL, 0);
    const nonblock_bit = @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK");
    _ = try std.posix.fcntl(fd, std.posix.F.SETFL, flags | nonblock_bit);
}

fn runStageTimeout(allocator: std.mem.Allocator, stage: QualityStage, command: ?[]const u8, timeout_ms: u64) !QualityResult {
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

    // If the command contains shell metacharacters (&&, |, >, ;), run it via `sh -c`
    // so chained commands work. Otherwise exec directly (no shell overhead).
    const has_shell = std.mem.indexOfAny(u8, cmd, "&|><;`$\n") != null;

    var argv_list = std.ArrayList([]const u8).init(allocator);
    defer argv_list.deinit();

    if (has_shell) {
        try argv_list.append("sh");
        try argv_list.append("-c");
        try argv_list.append(cmd);
    } else {
        var iter = std.mem.split(u8, cmd, " ");
        while (iter.next()) |part| {
            if (part.len > 0) try argv_list.append(part);
        }
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
            .output = try std.fmt.allocPrint(allocator, "Failed to spawn: {s}", .{@errorName(err)}),
            .duration_ms = 0,
        };
    };

    // Make the pipe read-ends non-blocking so `read` never hangs. This is
    // critical for commands that spawn background processes which inherit the
    // pipe and keep it open after the child exits: without O_NONBLOCK, a read
    // on an open-but-empty pipe would block forever.
    if (child.stdout) |out| {
        setNonBlocking(out.handle) catch {};
    }
    if (child.stderr) |err_pipe| {
        setNonBlocking(err_pipe.handle) catch {};
    }

    const deadline_ns = (try std.time.Instant.now()).since(start) + timeout_ms * std.time.ns_per_ms;

    var stdout_buf = std.ArrayList(u8).init(allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(allocator);
    defer stderr_buf.deinit();

    var stdout_done = false;
    var stderr_done = false;
    var exited = false;
    var exit_status: u32 = 0;
    var timed_out = false;

    while (true) {
        // Reap the child if it has exited (non-blocking).
        if (!exited) {
            const wr = std.posix.waitpid(child.id, std.posix.W.NOHANG);
            if (wr.pid != 0) {
                exited = true;
                exit_status = wr.status;
            }
        }

        // Build the pollfd set from whichever pipes are still open.
        var fds: [2]std.posix.pollfd = undefined;
        var nfds: usize = 0;
        var stdout_idx: ?usize = null;
        var stderr_idx: ?usize = null;
        if (child.stdout) |out| {
            if (!stdout_done) {
                fds[nfds] = .{ .fd = out.handle, .events = std.posix.POLL.IN, .revents = 0 };
                stdout_idx = nfds;
                nfds += 1;
            }
        }
        if (child.stderr) |err_pipe| {
            if (!stderr_done) {
                fds[nfds] = .{ .fd = err_pipe.handle, .events = std.posix.POLL.IN, .revents = 0 };
                stderr_idx = nfds;
                nfds += 1;
            }
        }

        // If the child has exited, drain what's buffered with a short grace
        // period, then finish. We do NOT wait for EOF: background processes
        // spawned by the command may inherit the pipe and keep it open forever.
        if (exited) {
            // One last short poll (200ms) to pick up trailing output.
            var grace_fds: [2]std.posix.pollfd = undefined;
            var gnfds: usize = 0;
            if (child.stdout) |out| {
                if (!stdout_done) {
                    grace_fds[gnfds] = .{ .fd = out.handle, .events = std.posix.POLL.IN, .revents = 0 };
                    gnfds += 1;
                }
            }
            if (child.stderr) |err_pipe| {
                if (!stderr_done) {
                    grace_fds[gnfds] = .{ .fd = err_pipe.handle, .events = std.posix.POLL.IN, .revents = 0 };
                    gnfds += 1;
                }
            }
            if (gnfds > 0) {
                _ = std.posix.poll(grace_fds[0..gnfds], 200) catch 0;
                if (child.stdout) |out| {
                    if (!stdout_done) {
                        var buf: [8192]u8 = undefined;
                        const n = out.read(&buf) catch 0;
                        if (n > 0) try stdout_buf.appendSlice(buf[0..n]);
                    }
                }
                if (child.stderr) |err_pipe| {
                    if (!stderr_done) {
                        var buf: [8192]u8 = undefined;
                        const n = err_pipe.read(&buf) catch 0;
                        if (n > 0) try stderr_buf.appendSlice(buf[0..n]);
                    }
                }
            }
            break;
        }

        // Check timeout before blocking on poll.
        const now = try std.time.Instant.now();
        if (now.since(start) >= deadline_ns) {
            timed_out = true;
            break;
        }

        if (nfds == 0) {
            // No pipes left but child hasn't exited yet — wait briefly.
            std.time.sleep(10 * std.time.ns_per_ms);
            continue;
        }

        const remaining_ms: i32 = @intCast(@min((deadline_ns - now.since(start)) / std.time.ns_per_ms, 1000));
        const nready = std.posix.poll(fds[0..nfds], remaining_ms) catch 0;
        if (nready == 0) continue;

        // Read available data from each ready pipe (poll said readable).
        if (!stdout_done) if (child.stdout) |out| {
            if (stdout_idx) |idx| {
                const rev = fds[idx].revents;
                if (rev & (std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR) != 0) {
                    var buf: [8192]u8 = undefined;
                    const n = out.read(&buf) catch blk: {
                        stdout_done = true;
                        break :blk 0;
                    };
                    if (n > 0) {
                        try stdout_buf.appendSlice(buf[0..n]);
                    } else {
                        stdout_done = true;
                    }
                }
            }
        };
        if (!stderr_done) if (child.stderr) |err_pipe| {
            if (stderr_idx) |idx| {
                const rev = fds[idx].revents;
                if (rev & (std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR) != 0) {
                    var buf: [8192]u8 = undefined;
                    const n = err_pipe.read(&buf) catch blk: {
                        stderr_done = true;
                        break :blk 0;
                    };
                    if (n > 0) {
                        try stderr_buf.appendSlice(buf[0..n]);
                    } else {
                        stderr_done = true;
                    }
                }
            }
        };
    }

    // If timed out, kill the child so nothing keeps running.
    if (timed_out and !exited) {
        std.posix.kill(child.id, std.posix.SIG.KILL) catch {};
        // Give it a moment to die, then reap.
        const wr = std.posix.waitpid(child.id, std.posix.W.NOHANG);
        if (wr.pid != 0) {
            exited = true;
            exit_status = wr.status;
        }
    }

    const elapsed = (try std.time.Instant.now()).since(start) / std.time.ns_per_ms;

    var output_buf = std.ArrayList(u8).init(allocator);
    defer output_buf.deinit();
    try output_buf.appendSlice(stdout_buf.items);
    if (stderr_buf.items.len > 0) {
        try output_buf.writer().print("\n[stderr]\n{s}\n", .{stderr_buf.items});
    }
    if (timed_out) {
        try output_buf.writer().print("\n[timed out after {d}s]\n", .{timeout_ms / 1000});
    }

    const exit_code: i32 = if (timed_out) -1 else if (exited and std.posix.W.IFEXITED(exit_status))
        std.posix.W.EXITSTATUS(exit_status)
    else
        -1;
    const status: QualityStatus = if (timed_out) .fail else if (exit_code == 0) .pass else if (exit_code >= 100) .warn else .fail;

    const out_str = try allocator.alloc(u8, output_buf.items.len);
    @memcpy(out_str, output_buf.items);
    return QualityResult{
        .stage = stage,
        .command = try allocator.dupe(u8, cmd),
        .status = status,
        .exit_code = exit_code,
        .output = out_str,
        .duration_ms = elapsed,
    };
}

/// Run all quality gates and return results
pub fn runAllQualityGates(allocator: std.mem.Allocator) ![]QualityResult {
    // Try to load config from acts.json first, fall back to auto-detect
    const config = try loadQualityConfig(allocator) orelse try detectQualityGate(allocator);
    defer freeQualityConfig(allocator, config);

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

    const result_slice = try allocator.alloc(QualityResult, results.items.len);
    @memcpy(result_slice, results.items);
    results.deinit();
    return result_slice;
}

pub fn freeQualityConfig(allocator: std.mem.Allocator, config: QualityConfig) void {
    if (config.test_cmd) |v| allocator.free(v);
    if (config.lint) |v| allocator.free(v);
    if (config.typecheck) |v| allocator.free(v);
    if (config.build) |v| allocator.free(v);
}

/// Free all quality results
pub fn freeQualityResults(allocator: std.mem.Allocator, results: []QualityResult) void {
    for (results) |r| {
        allocator.free(r.output);
        allocator.free(r.command);
    }
    allocator.free(results);
}
