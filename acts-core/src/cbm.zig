const std = @import("std");
const git = @import("git.zig");

/// Shared CBM (codebase-memory-mcp) client used by the Zig binary.
/// CBM is itself an MCP server; we invoke it via its `cli <tool> [flags]`
/// interface (the raw-JSON arg form is deprecated, so we use flags).
/// All Zig-side code intelligence (`acts graph`, `acts tech-lead`,
/// `acts doc-risk`) goes through this module.

pub const CbmError = error{
    BinaryNotFound,
    ToolFailed,
    ParseFailed,
};

/// Binary discovery, in priority order (matches acts setup + the old plugin):
///   1. ~/.cache/codebase-memory-mcp/bin/   (CBM's own install root)
///   2. ~/.local/bin / $PATH
///   3. <cwd>/.acts/bin/                    (legacy project-local)
pub fn findBinary(allocator: std.mem.Allocator, cwd: []const u8) ?[]const u8 {
    const name = if (@import("builtin").os.tag == .windows) "codebase-memory-mcp.exe" else "codebase-memory-mcp";
    const home = std.posix.getenv("HOME") orelse "";
    const candidates = [_][]const u8{
        tryJoin(allocator, &.{ home, ".cache", "codebase-memory-mcp", "bin", name }) orelse "",
        tryJoin(allocator, &.{ home, ".local", "bin", name }) orelse "",
        tryJoin(allocator, &.{ cwd, ".acts", "bin", name }) orelse "",
    };
    for (candidates) |c| {
        if (c.len > 0) {
            std.fs.cwd().access(c, .{}) catch continue;
            return c;
        }
    }
    // PATH fallback
    const which = git.run(allocator, &.{ "which", name }, 512) catch return null;
    if (which.exit_code == 0) {
        const t = std.mem.trim(u8, which.stdout, " \n\r");
        if (t.len > 0) return t;
    }
    return null;
}

fn tryJoin(allocator: std.mem.Allocator, parts: []const []const u8) ?[]const u8 {
    return std.fs.path.join(allocator, parts) catch null;
}

/// The shared graph cache root (one store for the whole fleet).
pub fn cacheDir(allocator: std.mem.Allocator) []const u8 {
    const home = std.posix.getenv("HOME") orelse "~";
    return tryJoin(allocator, &.{ home, ".cache", "codebase-memory-mcp" }) orelse "";
}

/// Run a CBM cli tool with flags. Returns stdout on success.
/// `args` is a list of already-built `--flag value` pairs.
pub fn runTool(allocator: std.mem.Allocator, bin: []const u8, tool: []const u8, args: []const []const u8) ![]const u8 {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();
    try argv.append(bin);
    try argv.append("cli");
    try argv.append(tool);
    for (args) |a| try argv.append(a);

    const cache = cacheDir(allocator);
    var env_map = std.process.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("CBM_CACHE_DIR", cache);

    const res = try git.runWithEnv(allocator, argv.items, env_map, 1 << 24);
    if (res.exit_code != 0) {
        const err = std.mem.trim(u8, res.stderr, " \n\r");
        if (err.len > 0) return CbmError.ToolFailed;
        return CbmError.ToolFailed;
    }
    return res.stdout;
}

/// list_projects → array of {name, root_path}
pub const Project = struct {
    name: []const u8,
    root_path: []const u8,
};

pub fn listProjects(allocator: std.mem.Allocator, bin: []const u8) ![]Project {
    const raw = try runTool(allocator, bin, "list_projects", &.{});
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch return CbmError.ParseFailed;
    defer parsed.deinit();
    const v = parsed.value;
    if (v != .object) return CbmError.ParseFailed;
    const projects = v.object.get("projects") orelse return CbmError.ParseFailed;
    if (projects != .array) return CbmError.ParseFailed;

    var out = std.ArrayList(Project).init(allocator);
    for (projects.array.items) |p| {
        if (p != .object) continue;
        const name = if (p.object.get("name")) |n| if (n == .string) n.string else "" else "";
        const root = if (p.object.get("root_path")) |r| if (r == .string) r.string else "" else "";
        if (name.len > 0) try out.append(.{ .name = name, .root_path = root });
    }
    return out.toOwnedSlice();
}

/// Is the given repo path already indexed?
pub fn isIndexed(allocator: std.mem.Allocator, bin: []const u8, repo_path: []const u8) bool {
    const projects = listProjects(allocator, bin) catch return false;
    for (projects) |p| {
        if (std.mem.eql(u8, p.root_path, repo_path)) return true;
    }
    return false;
}

/// Best-effort: index a repo (fast mode) if not already indexed.
/// Returns true if the repo is indexed afterward.
pub fn ensureIndexed(allocator: std.mem.Allocator, bin: []const u8, repo_path: []const u8) bool {
    if (isIndexed(allocator, bin, repo_path)) return true;
    const args = [_][]const u8{ "--repo-path", repo_path, "--mode", "fast" };
    _ = runTool(allocator, bin, "index_repository", &args) catch return false;
    return isIndexed(allocator, bin, repo_path);
}

/// Cross-repo call counts for a symbol (via trace_path cross_service mode).
pub const Trace = struct {
    callers: u32 = 0,
    callees: u32 = 0,
    cross_repo: u32 = 0,
};

pub fn traceSymbol(allocator: std.mem.Allocator, bin: []const u8, project: []const u8, function_name: []const u8) Trace {
    const args = [_][]const u8{
        "--project", project,
        "--function-name", function_name,
        "--mode", "cross_service",
    };
    const raw = runTool(allocator, bin, "trace_path", &args) catch return .{};
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch return .{};
    defer parsed.deinit();
    const v = parsed.value;
    if (v != .object) return .{};
    var t = Trace{};
    if (v.object.get("callers")) |c| {
        if (c == .array) t.callers = @intCast(@min(c.array.items.len, 0xffff));
    }
    if (v.object.get("callees")) |c| {
        if (c == .array) t.callees = @intCast(@min(c.array.items.len, 0xffff));
    }
    // Cross-repo edges appear in cross_repo_callers / cross_repo_edges.
    if (v.object.get("cross_repo_callers")) |c| {
        if (c == .array) t.cross_repo += @intCast(@min(c.array.items.len, 0xffff));
    }
    if (v.object.get("cross_repo_edges")) |c| {
        if (c == .integer) t.cross_repo += @intCast(@min(@as(u64, @intCast(c.integer)), 0xffff));
    }
    return t;
}

/// `get_architecture` hotspots summary for a project.
pub fn hotspots(allocator: std.mem.Allocator, bin: []const u8, project: []const u8) []const u8 {
    const args = [_][]const u8{ "--project", project, "--aspects", "hotspots" };
    const raw = runTool(allocator, bin, "get_architecture", &args) catch return "";
    return raw;
}

/// Extract just the name (qualified_name) from a search_graph result.
pub const Symbol = struct {
    name: []const u8,
    qualified_name: []const u8,
    file_path: []const u8,
    complexity: u32 = 0,
    out_degree: u32 = 0,
    in_degree: u32 = 0,
    loop_depth: u32 = 0,
};

pub fn searchSymbols(
    allocator: std.mem.Allocator,
    bin: []const u8,
    project: []const u8,
    name_pattern: []const u8,
    limit: usize,
) ![]Symbol {
    const lim = try std.fmt.allocPrint(allocator, "{d}", .{limit});
    const args = [_][]const u8{ "--project", project, "--name-pattern", name_pattern, "--label", "Function", "--limit", lim };
    const raw = try runTool(allocator, bin, "search_graph", &args);
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, raw, .{}) catch return CbmError.ParseFailed;
    defer parsed.deinit();
    const v = parsed.value;
    if (v != .object) return CbmError.ParseFailed;
    const results = v.object.get("results") orelse return CbmError.ParseFailed;
    if (results != .array) return CbmError.ParseFailed;

    var out = std.ArrayList(Symbol).init(allocator);
    for (results.array.items) |r| {
        if (r != .object) continue;
        out.append(.{
            .name = if (r.object.get("name")) |x| if (x == .string) x.string else "" else "",
            .qualified_name = if (r.object.get("qualified_name")) |x| if (x == .string) x.string else "" else "",
            .file_path = if (r.object.get("file_path")) |x| if (x == .string) x.string else "" else "",
            .complexity = if (r.object.get("complexity")) |x| if (x == .integer) @intCast(x.integer) else 0 else 0,
            .out_degree = if (r.object.get("out_degree")) |x| if (x == .integer) @intCast(x.integer) else 0 else 0,
            .in_degree = if (r.object.get("in_degree")) |x| if (x == .integer) @intCast(x.integer) else 0 else 0,
            .loop_depth = if (r.object.get("loop_depth")) |x| if (x == .integer) @intCast(x.integer) else 0 else 0,
        }) catch {};
    }
    return out.toOwnedSlice();
}

test "cacheDir resolves under HOME" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const c = cacheDir(a);
    try std.testing.expect(std.mem.indexOf(u8, c, ".cache") != null);
    try std.testing.expect(std.mem.indexOf(u8, c, "codebase-memory-mcp") != null);
}
