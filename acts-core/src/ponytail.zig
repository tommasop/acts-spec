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

/// Candidate rel paths that prove ponytail is installed — both the project-local
/// layout (`.agents/rules`, `.opencode/…`) and opencode's global layout
/// (`agents/rules`, `command`, `plugin` under `~/.config/opencode`).
const probe_rels = [_][]const u8{
    ".agents/rules/ponytail.md",
    ".opencode/plugins/ponytail-frontmatter.cjs",
    ".opencode/command/ponytail.md",
    "agents/rules/ponytail.md",
    "plugin/ponytail-frontmatter.cjs",
    "command/ponytail.md",
};

/// Search a set of roots (project + global) for any installed ponytail file.
pub fn findPonytailIn(allocator: std.mem.Allocator, roots: []const []const u8) ?[]const u8 {
    for (roots) |r| {
        if (r.len == 0) continue;
        for (probe_rels) |rel| {
            const p = tryJoin(allocator, &.{ r, rel }) orelse continue;
            if (fileExists(p)) return p;
        }
    }
    return null;
}

/// Is ponytail installed for this project, or globally for the machine?
/// Checks project-local dirs first, then opencode's global config dir.
pub fn findPonytail(allocator: std.mem.Allocator, cwd: []const u8) ?[]const u8 {
    const home = std.posix.getenv("HOME") orelse "";
    const roots = [_][]const u8{
        cwd,
        tryJoin(allocator, &.{ home, ".config", "opencode" }) orelse "",
    };
    return findPonytailIn(allocator, &roots);
}

/// Map a ponytail file path to its opencode GLOBAL location under a config root
/// (e.g. `~/.config/opencode`): `.opencode/command/X.md` → `command/X.md`,
/// `.opencode/plugins/X.cjs` → `plugin/X.cjs`, `.agents/X` → `agents/X`.
pub fn globalDestFor(allocator: std.mem.Allocator, config_root: []const u8, rel: []const u8) ?[]const u8 {
    const command_prefix = ".opencode/command/";
    const plugin_prefix = ".opencode/plugins/";
    const agents_prefix = ".agents/";
    if (std.mem.startsWith(u8, rel, command_prefix)) {
        return tryJoin(allocator, &.{ config_root, "command", rel[command_prefix.len..] });
    }
    if (std.mem.startsWith(u8, rel, plugin_prefix)) {
        return tryJoin(allocator, &.{ config_root, "plugin", rel[plugin_prefix.len..] });
    }
    if (std.mem.startsWith(u8, rel, agents_prefix)) {
        return tryJoin(allocator, &.{ config_root, "agents", rel[agents_prefix.len..] });
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

/// Fetch ponytail into opencode's GLOBAL config dir (`~/.config/opencode`) so
/// every project picks it up: commands → `command/`, plugin → `plugin/` (+
/// registered in the global opencode.json), rules → `agents/rules/`.
pub fn installFilesGlobal(allocator: std.mem.Allocator, config_root: []const u8) !usize {
    var written: usize = 0;
    for (ponytail_files) |rel| {
        const dest = globalDestFor(allocator, config_root, rel) orelse continue;
        if (std.fs.path.dirname(dest)) |d| mkdirp(d);
        const url = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ RAW_BASE, rel });
        const res = git.run(allocator, &.{ "curl", "-fsSL", url, "-o", dest }, 1 << 20) catch continue;
        if (res.exit_code == 0 and fileExists(dest)) written += 1;
    }
    if (written > 0) try registerGlobalPlugin(allocator, config_root);
    return written;
}

/// Ensure the global opencode.json `plugin` array includes the ponytail
/// frontmatter plugin (relative to the config root). Creates the file if missing.
pub fn registerGlobalPlugin(allocator: std.mem.Allocator, config_root: []const u8) !void {
    const cfg_path = tryJoin(allocator, &.{ config_root, "opencode.json" }) orelse return;
    const want = "./plugin/ponytail-frontmatter.cjs";

    var root: std.json.ObjectMap = std.json.ObjectMap.init(allocator);
    var parsed: ?std.json.Parsed(std.json.Value) = null;
    defer if (parsed) |*p| p.deinit();

    if (fileExists(cfg_path)) {
        const content = std.fs.cwd().readFileAlloc(allocator, cfg_path, 1 << 20) catch null;
        if (content) |c| {
            defer allocator.free(c);
            const p = std.json.parseFromSlice(std.json.Value, allocator, c, .{}) catch null;
            if (p) |pp| {
                parsed = pp;
                if (pp.value == .object) root = pp.value.object;
            }
        }
    }

    const gop = try root.getOrPut("plugin");
    if (!gop.found_existing) gop.value_ptr.* = .{ .array = std.json.Array.init(allocator) };
    const plugins = &gop.value_ptr.*.array;
    var found = false;
    for (plugins.items) |item| {
        if (item == .string and std.mem.eql(u8, item.string, want)) {
            found = true;
            break;
        }
    }
    if (!found) try plugins.append(.{ .string = want });

    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    const v: std.json.Value = .{ .object = root };
    try std.json.stringify(v, .{ .whitespace = .indent_2 }, buf.writer());
    try buf.append('\n');
    try std.fs.cwd().writeFile(.{ .sub_path = cfg_path, .data = buf.items });
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

test "findPonytailIn finds ponytail under any candidate root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("command");
    try tmp.dir.writeFile(.{ .sub_path = "command/ponytail.md", .data = "# Ponytail\n" });
    const root = try tmp.dir.realpathAlloc(a, ".");
    const roots = [_][]const u8{root};
    try std.testing.expect(findPonytailIn(a, &roots) != null);
}

test "globalDestFor maps ponytail files to opencode global dirs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const root = "/home/test/.config/opencode";
    const cmd = globalDestFor(a, root, ".opencode/command/ponytail-review.md").?;
    try std.testing.expectEqualStrings("/home/test/.config/opencode/command/ponytail-review.md", cmd);
    const plugin = globalDestFor(a, root, ".opencode/plugins/ponytail-frontmatter.cjs").?;
    try std.testing.expectEqualStrings("/home/test/.config/opencode/plugin/ponytail-frontmatter.cjs", plugin);
    const rules = globalDestFor(a, root, ".agents/rules/ponytail.md").?;
    try std.testing.expectEqualStrings("/home/test/.config/opencode/agents/rules/ponytail.md", rules);
    try std.testing.expect(globalDestFor(a, root, ".opencode/skills/other/SKILL.md") == null);
}

test "registerGlobalPlugin ensures the plugin entry in opencode.json" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realpathAlloc(a, ".");
    // Seed an existing global config with an unrelated plugin.
    try tmp.dir.writeFile(.{ .sub_path = "opencode.json", .data = "{\n  \"plugin\": [\"some-plugin\"]\n}\n" });

    try registerGlobalPlugin(a, root);

    const content = try std.fs.cwd().readFileAlloc(a, try std.fs.path.join(a, &.{ root, "opencode.json" }), 1 << 16);
    const parsed = try std.json.parseFromSlice(std.json.Value, a, content, .{});
    const plugin = parsed.value.object.get("plugin").?.array;
    var found = false;
    for (plugin.items) |p| {
        if (p == .string and std.mem.eql(u8, p.string, "./plugin/ponytail-frontmatter.cjs")) found = true;
    }
    try std.testing.expect(found);
}