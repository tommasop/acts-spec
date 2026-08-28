const std = @import("std");

pub const CmdResult = struct {
    exit_code: u8,
    stdout: []const u8,
    stderr: []const u8,
};

/// Run a command with args and an explicit environment, capturing output.
pub fn runWithEnv(arena: std.mem.Allocator, argv: []const []const u8, env_map: std.process.EnvMap, max_out: usize) !CmdResult {
    var child = std.process.Child.init(argv, arena);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    child.env_map = &env_map;

    child.spawn() catch |err| {
        return CmdResult{
            .exit_code = 127,
            .stdout = try std.fmt.allocPrint(arena, "", .{}),
            .stderr = try std.fmt.allocPrint(arena, "spawn failed: {s} ({s})", .{ argv[0], @errorName(err) }),
        };
    };

    const stdout_all = child.stdout.?.reader().readAllAlloc(arena, max_out) catch try arena.alloc(u8, 0);
    const stderr_all = child.stderr.?.reader().readAllAlloc(arena, max_out) catch try arena.alloc(u8, 0);

    const term = child.wait() catch return CmdResult{
        .exit_code = 126,
        .stdout = stdout_all,
        .stderr = stderr_all,
    };

    const code: u8 = switch (term) {
        .Exited => |c| @intCast(c),
        else => 126,
    };
    return CmdResult{ .exit_code = code, .stdout = stdout_all, .stderr = stderr_all };
}

/// Run a command with args, capturing output. Returns exit code + trimmed stdout/stderr.
/// Caller owns the returned slices (allocated from `arena`).
pub fn run(arena: std.mem.Allocator, argv: []const []const u8, max_out: usize) !CmdResult {
    var child = std.process.Child.init(argv, arena);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    child.spawn() catch |err| {
        return CmdResult{
            .exit_code = 127,
            .stdout = try std.fmt.allocPrint(arena, "", .{}),
            .stderr = try std.fmt.allocPrint(arena, "spawn failed: {s} ({s})", .{ argv[0], @errorName(err) }),
        };
    };

    const stdout_all = child.stdout.?.reader().readAllAlloc(arena, max_out) catch try arena.alloc(u8, 0);
    const stderr_all = child.stderr.?.reader().readAllAlloc(arena, max_out) catch try arena.alloc(u8, 0);

    const term = child.wait() catch return CmdResult{
        .exit_code = 126,
        .stdout = stdout_all,
        .stderr = stderr_all,
    };

    const code: u8 = switch (term) {
        .Exited => |c| @intCast(c),
        else => 126,
    };
    return CmdResult{ .exit_code = code, .stdout = stdout_all, .stderr = stderr_all };
}

/// Split a command string into argv (shell-like word split, no quoting support needed for our known commands).
pub fn splitArgs(arena: std.mem.Allocator, cmd: []const u8) ![][]const u8 {
    var args = std.ArrayList([]const u8).init(arena);
    var it = std.mem.tokenizeAny(u8, cmd, " \t\r\n");
    while (it.next()) |tok| try args.append(tok);
    return args.toOwnedSlice();
}

pub fn isGitRepo(arena: std.mem.Allocator) bool {
    const res = run(arena, &.{ "git", "rev-parse", "--is-inside-work-tree" }, 256) catch return false;
    return res.exit_code == 0 and std.mem.trim(u8, res.stdout, " \n\r").len > 0;
}

pub fn currentBranch(arena: std.mem.Allocator) !?[]const u8 {
    const res = try run(arena, &.{ "git", "rev-parse", "--abbrev-ref", "HEAD" }, 512);
    if (res.exit_code != 0) return null;
    const b = std.mem.trim(u8, res.stdout, " \n\r");
    if (b.len == 0) return null;
    return b;
}

pub fn branchExists(arena: std.mem.Allocator, branch: []const u8) bool {
    const res = run(arena, &.{ "git", "rev-parse", "--verify", "--quiet", branch }, 512) catch return false;
    return res.exit_code == 0;
}

/// Create branch `name` from `base` and checkout. Pass empty `base` to branch from HEAD.
pub fn createBranch(arena: std.mem.Allocator, name: []const u8, base: []const u8) !CmdResult {
    if (base.len == 0) {
        return run(arena, &.{ "git", "checkout", "-b", name }, 4096);
    }
    return run(arena, &.{ "git", "checkout", "-b", name, base }, 4096);
}

pub fn checkoutBranch(arena: std.mem.Allocator, name: []const u8) !CmdResult {
    return run(arena, &.{ "git", "checkout", name }, 4096);
}

/// Committed-only files changed between two refs (e.g. base branch and a change
/// branch). Unlike `changedFilesSince`, this ignores uncommitted/untracked files
/// so ownership can be attributed precisely to committed work.
pub fn diffNameOnly(arena: std.mem.Allocator, from: []const u8, to: []const u8) ![][]const u8 {
    var out = std.ArrayList([]const u8).init(arena);
    const res = try run(arena, &.{ "git", "diff", "--name-only", from, to }, 65536);
    if (res.exit_code == 0) {
        var it = std.mem.tokenizeAny(u8, res.stdout, " \n\r");
        while (it.next()) |f| try out.append(f);
    }
    return out.toOwnedSlice();
}

/// Files changed between `base` and the current working tree (uncommitted + committed since base).
pub fn changedFilesSince(arena: std.mem.Allocator, base: []const u8) ![][]const u8 {
    var out = std.ArrayList([]const u8).init(arena);
    const res = try run(arena, &.{ "git", "diff", "--name-only", base, "HEAD" }, 65536);
    if (res.exit_code == 0) {
        var it = std.mem.tokenizeAny(u8, res.stdout, " \n\r");
        while (it.next()) |f| try out.append(f);
    }
    // Include untracked+uncommitted
    const st = try run(arena, &.{ "git", "status", "--porcelain" }, 65536);
    if (st.exit_code == 0) {
        var it = std.mem.tokenizeAny(u8, st.stdout, "\n");
        while (it.next()) |line| {
            if (line.len < 4) continue;
            const p = line[3..];
            var found = false;
            for (out.items) |f| {
                if (std.mem.eql(u8, f, p)) {
                    found = true;
                    break;
                }
            }
            if (!found) try out.append(p);
        }
    }
    return out.toOwnedSlice();
}

pub fn gitCommit(arena: std.mem.Allocator, message: []const u8) !CmdResult {
    return run(arena, &.{ "git", "commit", "-m", message }, 4096);
}

pub fn hasTool(arena: std.mem.Allocator, name: []const u8) bool {
    const res = run(arena, &.{ name, "--version" }, 512) catch return false;
    return res.exit_code == 0;
}

pub const Tool = struct {
    git_spice: bool,
    gh: bool,
};

/// Detect git-spice specifically. The `gs` binary name collides with Ghostscript,
/// so we verify the version output actually names git-spice.
pub fn hasGitSpice(arena: std.mem.Allocator) bool {
    const res = run(arena, &.{ "gs", "--version" }, 512) catch return false;
    if (res.exit_code != 0) return false;
    const out = std.mem.trim(u8, res.stdout, " \n\r");
    if (out.len == 0) return false;
    // git-spice prints "gs version 0.x" (or similar); Ghostscript prints "GPL Ghostscript ...".
    if (std.ascii.indexOfIgnoreCase(out, "ghostscript") != null) return false;
    return std.ascii.indexOfIgnoreCase(out, "gs") != null;
}

pub fn detectTools(arena: std.mem.Allocator) Tool {
    return .{ .git_spice = hasGitSpice(arena), .gh = hasTool(arena, "gh") };
}

/// Name of the default remote (e.g. "origin"), or null if none configured.
pub fn defaultRemote(arena: std.mem.Allocator) ?[]const u8 {
    const res = run(arena, &.{ "git", "remote" }, 512) catch return null;
    if (res.exit_code != 0) return null;
    var it = std.mem.tokenizeAny(u8, res.stdout, " \n\r");
    return it.next();
}

/// Push the current branch (or `branch`) to `remote` with upstream tracking.
pub fn pushBranch(arena: std.mem.Allocator, remote: []const u8, branch: []const u8) !CmdResult {
    return run(arena, &.{ "git", "push", "-u", remote, branch }, 8192);
}

/// Whether the current branch has an upstream already.
pub fn hasUpstream(arena: std.mem.Allocator) bool {
    const res = run(arena, &.{ "git", "rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}" }, 512) catch return false;
    return res.exit_code == 0;
}

pub fn gitCommitCountOnBranch(arena: std.mem.Allocator, base: []const u8) !usize {
    const res = try run(arena, &.{ "git", "rev-list", "--count", base, "..HEAD" }, 512);
    if (res.exit_code != 0) return 0;
    return std.fmt.parseInt(usize, std.mem.trim(u8, res.stdout, " \n\r"), 10) catch 0;
}

pub fn gitLogOneline(arena: std.mem.Allocator, base: []const u8, max: usize) ![]const u8 {
    const n = try std.fmt.allocPrint(arena, "{d}", .{max});
    const res = try run(arena, &.{ "git", "log", "--oneline", "-n", n, base, "..HEAD" }, 16384);
    if (res.exit_code != 0) return "";
    return std.mem.trim(u8, res.stdout, " \n\r");
}

/// Full SHA of a branch/ref (e.g. the base branch). Empty on failure.
pub fn refSha(arena: std.mem.Allocator, ref: []const u8) ![]const u8 {
    const res = try run(arena, &.{ "git", "rev-parse", ref }, 512);
    if (res.exit_code != 0) return "";
    return std.mem.trim(u8, res.stdout, " \n\r");
}

test "parseNameStatus splits --name-status output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const out =
        \\A	src/new.zig
        \\M	old.zig
        \\D	gone.zig
        \\R100	a.zig	b.zig
        \\C075	c.zig	d.zig
    ;
    const entries = try parseNameStatus(a, out);
    try std.testing.expectEqual(@as(usize, 5), entries.len);
    try std.testing.expectEqual(@as(u8, 'A'), entries[0].status);
    try std.testing.expectEqualStrings("src/new.zig", entries[0].file);
    try std.testing.expectEqual(@as(u8, 'M'), entries[1].status);
    try std.testing.expectEqualStrings("old.zig", entries[1].file);
    try std.testing.expectEqual(@as(u8, 'D'), entries[2].status);
    try std.testing.expectEqualStrings("gone.zig", entries[2].file);
    // Renames/copies resolve to the NEW path.
    try std.testing.expectEqual(@as(u8, 'R'), entries[3].status);
    try std.testing.expectEqualStrings("b.zig", entries[3].file);
    try std.testing.expectEqual(@as(u8, 'C'), entries[4].status);
    try std.testing.expectEqualStrings("d.zig", entries[4].file);
}

pub const FileStatus = struct {
    /// One of 'A' (added), 'M' (modified), 'D' (deleted), 'R' (renamed),
    /// 'C' (copied), 'T' (type change), 'U' (unmerged).
    status: u8,
    /// Path relative to repo root (for renames/copies: the NEW path).
    file: []const u8,
};

/// Parse `git diff --name-status` output into entries. Rename/copy lines
/// (`R100\told\tnew`) resolve to the new path so the caller sees the current
/// tree position of every touched file.
pub fn parseNameStatus(arena: std.mem.Allocator, stdout: []const u8) ![]FileStatus {
    var out = std.ArrayList(FileStatus).init(arena);
    var it = std.mem.tokenizeAny(u8, stdout, "\n");
    while (it.next()) |line| {
        if (line.len < 2) continue;
        const status = line[0];
        var rest = line[1..];
        if (rest.len > 0 and rest[0] == ' ') rest = rest[1..];
        if (status == 'R' or status == 'C') {
            var fields = std.mem.tokenizeScalar(u8, rest, '\t');
            _ = fields.next(); // old path
            if (fields.next()) |newpath| {
                try out.append(.{ .status = status, .file = newpath });
            }
            continue;
        }
        if (rest.len > 0) try out.append(.{ .status = status, .file = rest });
    }
    return out.toOwnedSlice();
}

/// Committed-only name-status between two refs (base and a change branch):
/// which files were Added/Modified/Deleted. Used by `acts diagram` to derive
/// the Before (base) and After (head) component sets.
pub fn diffNameStatus(arena: std.mem.Allocator, from: []const u8, to: []const u8) ![]FileStatus {
    const res = try run(arena, &.{ "git", "diff", "--name-status", from, to }, 65536);
    if (res.exit_code != 0) return &[_]FileStatus{};
    return parseNameStatus(arena, res.stdout);
}

/// Count of added lines between base and HEAD (for risk heuristics).
pub fn diffAdditions(arena: std.mem.Allocator, base: []const u8) !usize {
    const res = try run(arena, &.{ "git", "diff", "--numstat", base, "HEAD" }, 65536);
    if (res.exit_code != 0) return 0;
    var total: usize = 0;
    var it = std.mem.tokenizeAny(u8, res.stdout, "\n");
    while (it.next()) |line| {
        var f = std.mem.tokenizeAny(u8, line, "\t ");
        if (f.next()) |add| {
            if (std.mem.eql(u8, add, "-")) continue;
            total += std.fmt.parseInt(usize, add, 10) catch 0;
        }
    }
    return total;
}
