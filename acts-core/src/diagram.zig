const std = @import("std");
const git = @import("git.zig");
const stack = @import("stack.zig");
const graph = @import("graph.zig");
const archify = @import("archify.zig");

/// `acts diagram` — render a change's architecture impact as an archify
/// diagram. Components are derived from the committed diff (base branch →
/// change branch); `--delta` renders a Before/Delta/After comparison. The
/// renderer is the archify agent skill (`archify/bin/archify.mjs`), located in
/// the standard skill dirs. When it is missing the command degrades to a
/// textual delta summary and hints at `acts archify install`.

const out_root = ".acts/changes";

fn print(comptime fmt: []const u8, args: anytype) void {
    std.io.getStdOut().writer().print(fmt, args) catch {};
}

fn strOf(obj: *const std.json.ObjectMap, key: []const u8) ?[]const u8 {
    if (obj.get(key)) |val| {
        if (val == .string) return val.string;
    }
    return null;
}

fn writeFile(path: []const u8, data: []const u8) !void {
    if (std.fs.path.dirname(path)) |d| std.fs.cwd().makePath(d) catch {};
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = data });
}

fn contains(keys: []const []const u8, key: []const u8) bool {
    for (keys) |k| {
        if (std.mem.eql(u8, k, key)) return true;
    }
    return false;
}

pub const SideKeys = struct {
    /// Component keys present in the base branch (deleted ∪ modified).
    before: [][]const u8,
    /// Component keys present in the change branch (added ∪ modified).
    after: [][]const u8,
};

/// Group changed files into component keys and partition them by which side
/// of the delta they exist on. A component exists in `before` when any of its
/// files existed in base (modified/deleted); in `after` when any exist in the
/// change branch (added/modified).
pub fn partitionComponents(
    allocator: std.mem.Allocator,
    aliases: []const []const u8,
    entries: []const git.FileStatus,
) !SideKeys {
    var before = std.ArrayList([]const u8).init(allocator);
    var after = std.ArrayList([]const u8).init(allocator);
    var before_set = std.StringHashMap(void).init(allocator);
    var after_set = std.StringHashMap(void).init(allocator);

    for (entries) |e| {
        const key = try archify.componentKey(allocator, e.file, aliases);
        const in_before = e.status == 'D' or e.status == 'M' or e.status == 'R' or e.status == 'T' or e.status == 'C';
        const in_after = e.status == 'A' or e.status == 'M' or e.status == 'R' or e.status == 'T' or e.status == 'C';
        if (in_before and !before_set.contains(key)) {
            try before_set.put(key, {});
            try before.append(key);
        }
        if (in_after and !after_set.contains(key)) {
            try after_set.put(key, {});
            try after.append(key);
        }
    }
    return .{ .before = try before.toOwnedSlice(), .after = try after.toOwnedSlice() };
}

/// Dedupe changed files into one component per key. Kind is inferred from the
/// first file that maps to the key (see `archify.kindForPath`).
fn buildComponents(
    allocator: std.mem.Allocator,
    entries: []const git.FileStatus,
    aliases: []const []const u8,
) ![]archify.Component {
    var list = std.ArrayList(archify.Component).init(allocator);
    var seen = std.StringHashMap(void).init(allocator);
    for (entries) |e| {
        const key = try archify.componentKey(allocator, e.file, aliases);
        if (seen.contains(key)) continue;
        try seen.put(key, {});
        try list.append(.{
            .id = try archify.componentId(allocator, key),
            .kind = archify.kindForPath(e.file),
            .label = key,
        });
    }
    return list.toOwnedSlice();
}

fn filterComponents(
    allocator: std.mem.Allocator,
    all: []const archify.Component,
    keys: []const []const u8,
) ![]archify.Component {
    var out = std.ArrayList(archify.Component).init(allocator);
    for (all) |c| {
        if (contains(keys, c.label)) try out.append(c);
    }
    return out.toOwnedSlice();
}

/// Markdown delta summary (added / removed / changed) for PR comments and the
/// degraded no-renderer path.
pub fn buildDeltaSummary(
    allocator: std.mem.Allocator,
    change_id: []const u8,
    components: []const archify.Component,
    before_keys: []const []const u8,
    after_keys: []const []const u8,
) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const w = buf.writer();
    try w.print("## 🗺️ Architecture delta — change {s}\n\n", .{change_id});
    try w.writeAll("| Component | Status | Kind |\n|---|---|---|\n");
    for (components) |c| {
        const in_before = contains(before_keys, c.label);
        const in_after = contains(after_keys, c.label);
        if (!in_before and !in_after) continue;
        const status = if (in_before and in_after) "Changed" else if (in_after) "Added" else "Removed";
        try w.print("| {s} | {s} | {s} |\n", .{ c.label, status, c.kind });
    }
    return buf.toOwnedSlice();
}

fn runNode(allocator: std.mem.Allocator, renderer: []const u8, args: []const []const u8) !git.CmdResult {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append("node");
    try argv.append(renderer);
    for (args) |a| try argv.append(a);
    return git.run(allocator, argv.items, 1 << 24);
}

fn renderValidate(allocator: std.mem.Allocator, renderer: []const u8, ir_path: []const u8) !bool {
    const res = try runNode(allocator, renderer, &.{ "validate", "architecture", ir_path, "--quality", "showcase", "--json" });
    print("{s}\n", .{std.mem.trim(u8, res.stdout, " \n\r")});
    return res.exit_code == 0;
}

fn renderDeliver(allocator: std.mem.Allocator, renderer: []const u8, ir_path: []const u8, html_path: []const u8) !bool {
    if (!try renderValidate(allocator, renderer, ir_path)) return false;
    const res = try runNode(allocator, renderer, &.{ "deliver", "architecture", ir_path, html_path, "--quality", "showcase", "--json" });
    print("{s}\n", .{std.mem.trim(u8, res.stdout, " \n\r")});
    return res.exit_code == 0;
}

fn renderCompare(allocator: std.mem.Allocator, renderer: []const u8, base_path: []const u8, head_path: []const u8, html_path: []const u8) !bool {
    const res = try runNode(allocator, renderer, &.{ "compare", "architecture", base_path, head_path, html_path, "--json" });
    print("{s}\n", .{std.mem.trim(u8, res.stdout, " \n\r")});
    return res.exit_code == 0;
}

fn loadChange(allocator: std.mem.Allocator, id: []const u8) !struct { parsed: std.json.Parsed(std.json.Value), branch: []const u8, base: []const u8, ctitle: []const u8 } {
    var parsed = try stack.load(allocator);
    errdefer parsed.deinit();
    const v = parsed.value;
    const change = stack.getChange(v, id) orelse return error.ChangeNotFound;
    const branch = strOf(change, "branch") orelse "";
    const base = strOf(&v.object, "base_branch") orelse "";
    const ctitle = strOf(change, "title") orelse id;
    return .{ .parsed = parsed, .branch = branch, .base = base, .ctitle = ctitle };
}

fn prUrlOf(allocator: std.mem.Allocator, id: []const u8) ?[]const u8 {
    var parsed = stack.load(allocator) catch return null;
    defer parsed.deinit();
    const change = stack.getChange(parsed.value, id) orelse return null;
    const pr = change.get("pr") orelse return null;
    if (pr != .object) return null;
    const url = pr.object.get("url") orelse return null;
    if (url != .string) return null;
    return allocator.dupe(u8, url.string) catch null;
}

/// Render the change's architecture diagram (delta if `delta`, else a single
/// impact map). Returns the HTML path, or null when the renderer is missing
/// (the command prints the degraded textual delta instead).
pub fn cmdDiagram(allocator: std.mem.Allocator, cwd: []const u8, id: []const u8, delta: bool) !?[]const u8 {
    const loaded = try loadChange(allocator, id);
    defer loaded.parsed.deinit();
    const branch = loaded.branch;
    const base = loaded.base;
    const ctitle = loaded.ctitle;

    const entries = try git.diffNameStatus(allocator, base, branch);
    if (entries.len == 0) {
        print("change {s}: no committed diff vs base ({s}) — nothing to diagram.\n", .{ id, base });
        return null;
    }

    const aliases = graph.referenceAliases(allocator, cwd);
    const components = try buildComponents(allocator, entries, aliases);
    const sides = try partitionComponents(allocator, aliases, entries);

    const renderer = archify.findRenderer(allocator, cwd);
    if (renderer == null) {
        const summary = try buildDeltaSummary(allocator, id, components, sides.before, sides.after);
        print("archify renderer not installed — `acts diagram` degraded to a textual delta.\n", .{});
        print("{s}\n", .{summary});
        print("hint: run `acts archify install` (or `acts setup --with-archify`) to render HTML diagrams.\n", .{});
        return null;
    }

    const out_dir = try std.fs.path.join(allocator, &.{ out_root, id, "archify" });
    std.fs.cwd().makePath(out_dir) catch {};

    if (delta) {
        const before_comps = try filterComponents(allocator, components, sides.before);
        const after_comps = try filterComponents(allocator, components, sides.after);
        const base_title = try std.fmt.allocPrint(allocator, "{s} (before)", .{ctitle});
        const head_title = try std.fmt.allocPrint(allocator, "{s} (after)", .{ctitle});
        const base_ir = try archify.buildArchitectureIR(allocator, base_title, "base.html", before_comps, &.{});
        const head_ir = try archify.buildArchitectureIR(allocator, head_title, "head.html", after_comps, &.{});
        const base_path = try std.fs.path.join(allocator, &.{ out_dir, "base.json" });
        const head_path = try std.fs.path.join(allocator, &.{ out_dir, "head.json" });
        try writeFile(base_path, base_ir);
        try writeFile(head_path, head_ir);
        const html_path = try std.fmt.allocPrint(allocator, "{s}/delta-{s}.html", .{ out_dir, id });
        if (!try renderCompare(allocator, renderer.?, base_path, head_path, html_path)) return null;
        print("delta HTML: {s}\n", .{html_path});
        return html_path;
    }

    // Single impact map (change branch side; fall back to all components when
    // the change only deleted things).
    const after_comps = try filterComponents(allocator, components, sides.after);
    const comps = if (after_comps.len > 0) after_comps else components;
    const ir = try archify.buildArchitectureIR(allocator, ctitle, "architecture.html", comps, &.{});
    const ir_path = try std.fs.path.join(allocator, &.{ out_dir, "architecture.json" });
    try writeFile(ir_path, ir);
    const html_path = try std.fmt.allocPrint(allocator, "{s}/architecture-{s}.html", .{ out_dir, id });
    if (!try renderDeliver(allocator, renderer.?, ir_path, html_path)) return null;
    print("architecture HTML: {s}\n", .{html_path});
    return html_path;
}

fn extractPngPath(stdout: []const u8) ?[]const u8 {
    var it = std.mem.tokenizeAny(u8, stdout, "\" \n");
    while (it.next()) |tok| {
        if (std.mem.endsWith(u8, tok, ".png")) return tok;
    }
    return null;
}

fn rawUrlFromGist(allocator: std.mem.Allocator, gist_url: []const u8, png_path: []const u8) ?[]const u8 {
    const prefix = "https://gist.github.com/";
    if (!std.mem.startsWith(u8, gist_url, prefix)) return null;
    const rest = gist_url[prefix.len..];
    var it = std.mem.tokenizeScalar(u8, rest, '/');
    const user = it.next() orelse return null;
    const gid = it.next() orelse return null;
    const base = std.fs.path.basename(png_path);
    return std.fmt.allocPrint(allocator, "https://gist.githubusercontent.com/{s}/{s}/raw/{s}", .{ user, gid, base }) catch null;
}

/// Post the architecture-delta comment to the change's PR (best-effort, never
/// blocks). Inline PNG via `visual-check` + a public gist when Chrome is
/// available; otherwise the markdown summary + HTML link.
pub fn attachToPr(allocator: std.mem.Allocator, cwd: []const u8, id: []const u8, delta: bool) !void {
    const pr_url = prUrlOf(allocator, id) orelse {
        print("attach: no PR recorded for {s} — run `acts review` first.\n", .{id});
        return;
    };
    const tools = git.detectTools(allocator);
    if (!tools.gh) {
        print("attach: `gh` not available — cannot comment on the PR.\n", .{});
        return;
    }

    const html_path = try cmdDiagram(allocator, cwd, id, delta);
    if (html_path == null) return;

    var body = std.ArrayList(u8).init(allocator);
    const w = body.writer();

    // Best-effort inline PNG: visual-check (needs Chrome) → public gist → raw URL.
    if (archify.findRenderer(allocator, cwd)) |renderer| {
        const vc = try runNode(allocator, renderer, &.{ "visual-check", html_path.?, "--json" });
        if (vc.exit_code == 0) {
            if (extractPngPath(vc.stdout)) |png| {
                const gist = try git.run(allocator, &.{ "gh", "gist", "create", png, "--public" }, 65536);
                if (gist.exit_code == 0) {
                    const gist_url = std.mem.trim(u8, gist.stdout, " \n\r");
                    if (rawUrlFromGist(allocator, gist_url, png)) |raw| {
                        try w.print("![architecture delta]({s})\n\n", .{raw});
                    }
                }
            }
        }
    }

    // Build the markdown delta summary (reloads the change).
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;
    const change = stack.getChange(v, id) orelse return error.ChangeNotFound;
    const branch = strOf(change, "branch") orelse "";
    const base = strOf(&v.object, "base_branch") orelse "";
    const entries = try git.diffNameStatus(allocator, base, branch);
    const aliases = graph.referenceAliases(allocator, cwd);
    const components = try buildComponents(allocator, entries, aliases);
    const sides = try partitionComponents(allocator, aliases, entries);
    const summary = try buildDeltaSummary(allocator, id, components, sides.before, sides.after);
    try w.writeAll(summary);
    try w.print("\n\nSelf-contained HTML: `{s}`\n", .{html_path.?});

    const comment_path = try std.fs.path.join(allocator, &.{ out_root, id, "archify", "pr-comment.md" });
    try writeFile(comment_path, body.items);
    const res = try git.run(allocator, &.{ "gh", "pr", "comment", pr_url, "--body-file", comment_path }, 65536);
    if (res.exit_code == 0) {
        print("attached architecture delta to {s}\n", .{pr_url});
    } else {
        print("attach: gh pr comment failed: {s}\n", .{std.mem.trim(u8, res.stderr, " \n\r")});
    }
}

/// `acts archify install` — install the archify renderer via `npx skills add`
/// into the project's `.opencode/skills/`. Idempotent; also usable after setup.
pub fn cmdArchifyInstall(allocator: std.mem.Allocator, cwd: []const u8) !void {
    if (archify.findRenderer(allocator, cwd)) |r| {
        print("archify renderer already installed: {s}\n", .{r});
        return;
    }
    if (!git.hasTool(allocator, "node")) {
        print("error: `node` not found — required to run the archify renderer.\n", .{});
        return error.ToolMissing;
    }
    if (!git.hasTool(allocator, "npx")) {
        print("error: `npx` not found — required to install archify.\n", .{});
        return error.ToolMissing;
    }
    print("installing archify skill via npx (this downloads the renderer)…\n", .{});
    const res = try git.run(allocator, archify.installCmdArgs(), 1 << 24);
    if (res.exit_code != 0) {
        print("npx skills add failed: {s}\n", .{std.mem.trim(u8, res.stderr, " \n\r")});
        return error.InstallFailed;
    }
    if (archify.findRenderer(allocator, cwd)) |r| {
        print("archify installed: {s}\n", .{r});
    } else {
        print("note: install ran but no renderer found under `.opencode/skills/archify` — re-run `acts archify install` or install manually.\n", .{});
    }
}

/// Whole-stack diagram (Phase 4 implements rendering). Stub keeps cmdReview compiling.
pub fn cmdStackDiagram(allocator: std.mem.Allocator, cwd: []const u8, delta: bool, attach: bool) !void {
    _ = allocator;
    _ = cwd;
    _ = delta;
    _ = attach;
}

test "partitionComponents derives before/after side keys" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const aliases = [_][]const u8{"magic"};

    const entries = [_]git.FileStatus{
        .{ .status = 'A', .file = "src/a/one.zig" },
        .{ .status = 'M', .file = "src/b/two.zig" },
        .{ .status = 'D', .file = "src/c/three.zig" },
        .{ .status = 'A', .file = "magic/lib/foo.zig" },
    };
    const sides = try partitionComponents(a, &aliases, &entries);
    try std.testing.expectEqual(@as(usize, 2), sides.before.len);
    try std.testing.expectEqualStrings("src/b", sides.before[0]);
    try std.testing.expectEqualStrings("src/c", sides.before[1]);
    try std.testing.expectEqual(@as(usize, 3), sides.after.len);
    try std.testing.expectEqualStrings("src/a", sides.after[0]);
    try std.testing.expectEqualStrings("src/b", sides.after[1]);
    try std.testing.expectEqualStrings("magic", sides.after[2]);
}

test "buildDeltaSummary renders markdown table with statuses" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const comps = [_]archify.Component{
        .{ .id = "src-a", .kind = "backend", .label = "src/a" },
        .{ .id = "src-b", .kind = "backend", .label = "src/b" },
        .{ .id = "src-c", .kind = "backend", .label = "src/c" },
    };
    const before = [_][]const u8{ "src/b", "src/c" };
    const after = [_][]const u8{ "src/a", "src/b" };

    const summary = try buildDeltaSummary(a, "my-change", &comps, &before, &after);
    try std.testing.expect(std.mem.indexOf(u8, summary, "| src/a | Added | backend |") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "| src/b | Changed | backend |") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "| src/c | Removed | backend |") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "my-change") != null);
}