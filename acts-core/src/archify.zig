const std = @import("std");
const git = @import("git.zig");

/// archify — a bounded client for the archify agent-skill renderer
/// (tt-a1i/archify). Agents emit typed JSON IR; archify deterministically
/// compiles it into self-contained HTML/SVG. `acts diagram` builds architecture
/// IR from the git diff + CBM graph, validates it, and delivers the HTML.

/// Node type names accepted by archify's architecture schema.
pub const kinds = [_][]const u8{ "frontend", "backend", "database", "cloud", "security", "messagebus", "external" };

pub const Component = struct {
    id: []const u8,
    kind: []const u8,
    label: []const u8,
};

pub const Connection = struct {
    id: []const u8,
    from: []const u8,
    to: []const u8,
    label: ?[]const u8 = null,
};

fn tryJoin(allocator: std.mem.Allocator, parts: []const []const u8) ?[]const u8 {
    return std.fs.path.join(allocator, parts) catch null;
}

/// Search a list of skill roots for `bin/archify.mjs`. Testable without the
/// real renderer installed.
pub fn findRendererIn(allocator: std.mem.Allocator, roots: []const []const u8) ?[]const u8 {
    for (roots) |r| {
        if (r.len == 0) continue;
        const p = tryJoin(allocator, &.{ r, "bin", "archify.mjs" }) orelse continue;
        std.fs.cwd().access(p, .{}) catch continue;
        return p;
    }
    return null;
}

/// Locate the archify renderer in the standard skill install locations
/// (project-local first, then global skill dirs). Mirrors CBM binary discovery.
pub fn findRenderer(allocator: std.mem.Allocator, cwd: []const u8) ?[]const u8 {
    const home = std.posix.getenv("HOME") orelse "";
    const roots = [_][]const u8{
        tryJoin(allocator, &.{ cwd, ".opencode", "skills", "archify" }) orelse "",
        tryJoin(allocator, &.{ cwd, ".agents", "skills", "archify" }) orelse "",
        tryJoin(allocator, &.{ cwd, "archify" }) orelse "",
        tryJoin(allocator, &.{ home, ".config", "opencode", "skills", "archify" }) orelse "",
        tryJoin(allocator, &.{ home, ".agents", "skills", "archify" }) orelse "",
        tryJoin(allocator, &.{ home, ".claude", "skills", "archify" }) orelse "",
    };
    return findRendererIn(allocator, &roots);
}

/// Sanitize a component key into a stable archify node id: lowercase
/// alphanumerics, runs of non-alphanumerics collapse to a single '-'.
pub fn componentId(allocator: std.mem.Allocator, key: []const u8) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    var prev_dash = false;
    for (key) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            try buf.append(std.ascii.toLower(ch));
            prev_dash = false;
        } else if (!prev_dash and buf.items.len > 0) {
            try buf.append('-');
            prev_dash = true;
        }
    }
    return buf.toOwnedSlice();
}

fn containsAny(haystack: []const u8, needles: []const []const u8) bool {
    for (needles) |n| {
        if (std.ascii.indexOfIgnoreCase(haystack, n) != null) return true;
    }
    return false;
}

/// Heuristic node type from a file path. Ordered: database → messagebus →
/// security → frontend → external → cloud → backend. Purely advisory; the
/// agent may override with `--type`.
pub fn kindForPath(file: []const u8) []const u8 {
    if (containsAny(file, &.{
        "/db/",    "/dbs/",    "/repository/", "/repositories/", "/sql/",
        "/migrations/", "/storage/", "database", "postgres", "redis",
    })) return "database";
    if (containsAny(file, &.{ "/queue", "/bus/", "/kafka", "/events/", "/message", "/topic" })) return "messagebus";
    if (containsAny(file, &.{ "/auth", "/security", "/policy", "/permission", "/rbac", "/acl" })) return "security";
    if (containsAny(file, &.{ "/web", "/ui/", "/frontend", "/client", "/app/", "/components/", "/pages/", ".tsx", ".jsx", ".vue", ".svelte" })) return "frontend";
    if (containsAny(file, &.{ "/integration", "/integrations", "/vendor", "/external", "/third", "/adapter" })) return "external";
    if (containsAny(file, &.{ "/cloud", "/deploy/", "/infra/", "/k8s", "/aws", "/terraform", "/helm" })) return "cloud";
    return "backend";
}

/// Map a changed file to a component key: a configured reference alias
/// (`<alias>/…` cross-repo path) if the file lives in one, else its top-level
/// directory. Multiple files collapse to one component node per key.
pub fn componentKey(allocator: std.mem.Allocator, file: []const u8, aliases: []const []const u8) ![]const u8 {
    for (aliases) |alias| {
        if (alias.len == 0) continue;
        const seg = try std.fmt.allocPrint(allocator, "../{s}/", .{alias});
        if (std.mem.startsWith(u8, file, seg)) return allocator.dupe(u8, alias);
        const seg2 = try std.fmt.allocPrint(allocator, "{s}/", .{alias});
        if (std.mem.startsWith(u8, file, seg2)) return allocator.dupe(u8, alias);
    }
    if (std.mem.indexOfScalar(u8, file, '/')) |idx| {
        if (idx > 0) return allocator.dupe(u8, file[0..idx]);
    }
    return allocator.dupe(u8, file);
}

/// Compile components + connections into archify architecture IR (JSON).
/// The exact field set matches archify's `architecture` schema so `validate`
/// and `compare` accept it out of the box. Components are placed on a
/// deterministic grid (archify requires explicit `pos` when no layout mode).
pub fn buildArchitectureIR(
    allocator: std.mem.Allocator,
    title: []const u8,
    out_name: []const u8,
    components: []const Component,
    connections: []const Connection,
) ![]const u8 {
    var root = std.json.ObjectMap.init(allocator);
    try root.put("schema_version", .{ .integer = 1 });
    try root.put("diagram_type", .{ .string = "architecture" });

    var meta = std.json.ObjectMap.init(allocator);
    try meta.put("title", .{ .string = title });
    try meta.put("output", .{ .string = out_name });
    try meta.put("quality_profile", .{ .string = "showcase" });
    try root.put("meta", .{ .object = meta });

    const per_row: usize = 4;
    const gap_x: i64 = 170;
    const gap_y: i64 = 130;

    var comps = std.json.Array.init(allocator);
    for (components, 0..) |c, i| {
        const col: i64 = @intCast(@mod(i, per_row));
        const row: i64 = @intCast(@divTrunc(i, per_row));
        var o = std.json.ObjectMap.init(allocator);
        try o.put("id", .{ .string = c.id });
        try o.put("type", .{ .string = c.kind });
        try o.put("label", .{ .string = c.label });
        var pos = std.json.Array.init(allocator);
        try pos.append(.{ .integer = 40 + col * gap_x });
        try pos.append(.{ .integer = 60 + row * gap_y });
        try o.put("pos", .{ .array = pos });
        try comps.append(.{ .object = o });
    }
    try root.put("components", .{ .array = comps });

    var conns = std.json.Array.init(allocator);
    for (connections) |cn| {
        var o = std.json.ObjectMap.init(allocator);
        try o.put("id", .{ .string = cn.id });
        try o.put("from", .{ .string = cn.from });
        try o.put("to", .{ .string = cn.to });
        if (cn.label) |l| try o.put("label", .{ .string = l });
        try conns.append(.{ .object = o });
    }
    try root.put("connections", .{ .array = conns });

    var buf = std.ArrayList(u8).init(allocator);
    const v: std.json.Value = .{ .object = root };
    try std.json.stringify(v, .{ .whitespace = .indent_2 }, buf.writer());
    return buf.toOwnedSlice();
}

/// Whether the archify renderer is installed for this project.
pub fn available(allocator: std.mem.Allocator, cwd: []const u8) bool {
    return findRenderer(allocator, cwd) != null;
}

/// Build argv for the archify `npx skills add` install (used by
/// `acts archify install` and `acts setup --with-archify`).
pub fn installCmdArgs() []const []const u8 {
    return &[_][]const u8{
        "npx", "-y", "skills", "add",
        "tt-a1i/archify", "--skill", "archify",
        "--agent", "opencode", "--copy", "--yes",
    };
}

test "componentId sanitizes keys into stable ids" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("auth-service-api", try componentId(a, "Auth Service/API"));
    try std.testing.expectEqualStrings("src-hooks", try componentId(a, "src/hooks"));
    try std.testing.expectEqualStrings("web", try componentId(a, "Web"));
    try std.testing.expectEqualStrings("api-server", try componentId(a, "api_server..2"));
}

test "kindForPath classifies by directory heuristics" {
    try std.testing.expectEqualStrings("database", kindForPath("src/db/postgres.zig"));
    try std.testing.expectEqualStrings("database", kindForPath("lib/repository/user_repo.zig"));
    try std.testing.expectEqualStrings("messagebus", kindForPath("src/queue/worker.zig"));
    try std.testing.expectEqualStrings("security", kindForPath("auth/policies.zig"));
    try std.testing.expectEqualStrings("frontend", kindForPath("web/App.tsx"));
    try std.testing.expectEqualStrings("frontend", kindForPath("ui/components/Button.tsx"));
    try std.testing.expectEqualStrings("external", kindForPath("integrations/stripe/client.zig"));
    try std.testing.expectEqualStrings("cloud", kindForPath("deploy/cloud/k8s.yaml"));
    try std.testing.expectEqualStrings("backend", kindForPath("src/handlers/user.zig"));
    try std.testing.expectEqualStrings("backend", kindForPath("misc/other.zig"));
}

test "componentKey maps cross-repo alias or top-level dir" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const aliases = [_][]const u8{ "magic", "ui-payments" };
    try std.testing.expectEqualStrings("magic", try componentKey(a, "magic/lib/foo.zig", &aliases));
    try std.testing.expectEqualStrings("ui-payments", try componentKey(a, "ui-payments/app/App.tsx", &aliases));
    try std.testing.expectEqualStrings("src", try componentKey(a, "src/handlers/user.zig", &aliases));
    try std.testing.expectEqualStrings("misc", try componentKey(a, "misc/other.zig", &aliases));
}

test "findRendererIn locates bin/archify.mjs under a root" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.makePath("archify/bin");
    try tmp.dir.writeFile(.{ .sub_path = "archify/bin/archify.mjs", .data = "#!/usr/bin/env node\n" });

    const root = try tmp.dir.realpathAlloc(a, "archify");
    const roots = [_][]const u8{root};
    const found = findRendererIn(a, &roots);
    try std.testing.expect(found != null);
    try std.testing.expect(std.mem.endsWith(u8, found.?, "bin/archify.mjs"));
}

test "buildArchitectureIR emits valid architecture IR JSON" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const comps = [_]Component{
        .{ .id = "api", .kind = "backend", .label = "API Server" },
        .{ .id = "db", .kind = "database", .label = "PostgreSQL" },
    };
    const conns = [_]Connection{
        .{ .id = "api-to-db", .from = "api", .to = "db", .label = "SQL" },
    };
    const ir = try buildArchitectureIR(a, "Change impact", "impact.html", &comps, &conns);

    const parsed = try std.json.parseFromSlice(std.json.Value, a, ir, .{});
    const v = parsed.value;
    try std.testing.expect(v == .object);
    try std.testing.expectEqualStrings("architecture", v.object.get("diagram_type").?.string);
    const meta = v.object.get("meta").?.object;
    try std.testing.expectEqualStrings("Change impact", meta.get("title").?.string);
    try std.testing.expectEqualStrings("showcase", meta.get("quality_profile").?.string);
    const comps_arr = v.object.get("components").?.array;
    try std.testing.expectEqual(@as(usize, 2), comps_arr.items.len);
    try std.testing.expectEqualStrings("api", comps_arr.items[0].object.get("id").?.string);
    try std.testing.expectEqualStrings("backend", comps_arr.items[0].object.get("type").?.string);
    const pos = comps_arr.items[0].object.get("pos").?.array;
    try std.testing.expectEqual(@as(usize, 2), pos.items.len);
    try std.testing.expect(pos.items[0] == .integer);
    const conns_arr = v.object.get("connections").?.array;
    try std.testing.expectEqual(@as(usize, 1), conns_arr.items.len);
    try std.testing.expectEqualStrings("api", conns_arr.items[0].object.get("from").?.string);
    try std.testing.expectEqualStrings("db", conns_arr.items[0].object.get("to").?.string);
}