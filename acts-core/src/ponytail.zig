const std = @import("std");
const git = @import("git.zig");

/// ponytail — integrate the "lazy senior dev" minimality skill
/// (DietrichGebert/ponytail). It is a behavioral discipline (YAGNI ladder, reuse
/// over re-implementation, shortest working diff), complementary to ACTS's
/// checkpoint scoping. `acts ponytail install` fetches ponytail's opencode
/// files (rules + slash commands + frontmatter plugin) into the project;
/// `acts review` appends a ponytail minimality checklist to the one PR.

const RAW_BASE = "https://raw.githubusercontent.com/DietrichGebert/ponytail/main";

/// Files (relative to a project root) that make up ponytail's opencode support.
pub const ponytail_files = [_][]const u8{
    ".agents/rules/ponytail.md",
    ".opencode/plugins/ponytail-frontmatter.cjs",
    ".opencode/command/ponytail.md",
    ".opencode/command/ponytail-review.md",
    ".opencode/command/ponytail-audit.md",
    ".opencode/command/ponytail-gain.md",
    ".opencode/command/ponytail-debt.md",
    ".opencode/command/ponytail-help.md",
};

fn tryJoin(allocator: std.mem.Allocator, parts: []const []const u8) ?[]const u8 {
    return std.fs.path.join(allocator, parts) catch null;
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Is ponytail installed for this project? Checks the rules file, the frontmatter
/// plugin, and the command dir. Returns the first hit's path.
pub fn findPonytail(allocator: std.mem.Allocator, cwd: []const u8) ?[]const u8 {
    const candidates = [_][]const u8{
        tryJoin(allocator, &.{ cwd, ".agents", "rules", "ponytail.md" }) orelse "",
        tryJoin(allocator, &.{ cwd, ".opencode", "plugins", "ponytail-frontmatter.cjs" }) orelse "",
        tryJoin(allocator, &.{ cwd, ".opencode", "command", "ponytail.md" }) orelse "",
    };
    for (candidates) |c| {
        if (c.len > 0 and fileExists(c)) return c;
    }
    return null;
}

fn mkdirp(dir: []const u8) void {
    std.fs.cwd().makePath(dir) catch {};
}

/// Fetch all ponytail opencode files from GitHub into `dest_root`.
/// Returns how many files were written. Never errors on a single-file failure
/// (best-effort; prints nothing — caller reports the count).
pub fn installFiles(allocator: std.mem.Allocator, dest_root: []const u8) !usize {
    var written: usize = 0;
    for (ponytail_files) |rel| {
        const dest = tryJoin(allocator, &.{ dest_root, rel }) orelse continue;
        if (std.fs.path.dirname(dest)) |d| mkdirp(d);
        const url = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ RAW_BASE, rel });
        const res = git.run(allocator, &.{ "curl", "-fsSL", url, "-o", dest }, 1 << 20) catch continue;
        if (res.exit_code == 0 and fileExists(dest)) written += 1;
    }
    return written;
}

/// Per-change diff summary for the review checklist.
pub const ChangeStat = struct {
    id: []const u8,
    files: usize,
    additions: usize,
};

/// Build the ponytail minimality review section for the one-PR body: the YAGNI
/// ladder checklist + a per-change diff-stat table. Pure — diff stats are
/// computed by the caller (`cmdReview`).
pub fn reviewSection(
    allocator: std.mem.Allocator,
    v: std.json.Value,
    stats: []const ChangeStat,
) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const w = buf.writer();
    const stitle = if (v.object.get("title")) |s| if (s == .string) s.string else "" else "";
    try w.writeAll("\n## 🎯 Minimality review (ponytail)\n");
    try w.writeAll("> Installed discipline — the best code is the code you never wrote. Verify each change is the smallest thing that works.\n\n");
    try w.writeAll("- [ ] Does this need to be built at all? (YAGNI)\n");
    try w.writeAll("- [ ] Reuses existing helpers / stdlib / installed deps — nothing re-implemented\n");
    try w.writeAll("- [ ] Shortest working diff; deletions over additions; fewest files possible\n");
    try w.writeAll("- [ ] No new dependency unless unavoidable\n");
    try w.writeAll("- [ ] Non-trivial logic leaves ONE runnable check behind\n");
    try w.print("\nStack: {s}\n\n", .{stitle});
    if (stats.len > 0) {
        try w.writeAll("| Change | Files | Additions |\n|---|---|---|\n");
        for (stats) |s| {
            try w.print("| {s} | {d} | {d} |\n", .{ s.id, s.files, s.additions });
        }
    }
    return buf.toOwnedSlice();
}

test "ponytail_files covers rules + commands + plugin" {
    var seen_rules = false;
    var seen_plugin = false;
    var seen_cmd = false;
    for (ponytail_files) |f| {
        if (std.mem.eql(u8, f, ".agents/rules/ponytail.md")) seen_rules = true;
        if (std.mem.eql(u8, f, ".opencode/plugins/ponytail-frontmatter.cjs")) seen_plugin = true;
        if (std.mem.eql(u8, f, ".opencode/command/ponytail.md")) seen_cmd = true;
    }
    try std.testing.expect(seen_rules);
    try std.testing.expect(seen_plugin);
    try std.testing.expect(seen_cmd);
    try std.testing.expect(ponytail_files.len >= 8);
}

test "findPonytail detects installed rules file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath(".agents/rules");
    try tmp.dir.writeFile(.{ .sub_path = ".agents/rules/ponytail.md", .data = "# Ponytail\n" });
    const cwd = try tmp.dir.realpathAlloc(a, ".");
    try std.testing.expect(findPonytail(a, cwd) != null);
    try std.testing.expect(std.mem.endsWith(u8, findPonytail(a, cwd).?, "ponytail.md"));
}

test "reviewSection renders minimality checklist with change stats" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var r = std.json.ObjectMap.init(a);
    try r.put("version", .{ .integer = 3 });
    try r.put("id", .{ .string = "auth" });
    try r.put("title", .{ .string = "Add auth" });
    try r.put("branch", .{ .string = "acts/auth/feature" });
    try r.put("base_branch", .{ .string = "master" });
    var ch = std.json.Array.init(a);
    var c1 = std.json.ObjectMap.init(a);
    try c1.put("id", .{ .string = "c1" });
    try c1.put("status", .{ .string = "VERIFIED" });
    try c1.put("start_sha", .{ .string = "abc" });
    try c1.put("end_sha", .{ .string = "def" });
    try ch.append(.{ .object = c1 });
    try r.put("changes", .{ .array = ch });
    const v: std.json.Value = .{ .object = r };

    const stats = [_]ChangeStat{ .{ .id = "c1", .files = 3, .additions = 42 } };
    const section = try reviewSection(a, v, &stats);
    try std.testing.expect(std.mem.indexOf(u8, section, "ponytail") != null);
    try std.testing.expect(std.mem.indexOf(u8, section, "YAGNI") != null);
    try std.testing.expect(std.mem.indexOf(u8, section, "| c1 | 3 | 42 |") != null);
}