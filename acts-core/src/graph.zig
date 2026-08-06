const std = @import("std");
const cbm = @import("cbm.zig");
const git = @import("git.zig");
const stack = @import("stack.zig");
const risk = @import("risk.zig");

/// CBM-backed commands exposed from the Zig binary now that the cbm plugin is
/// removed. CBM tools are available natively via OpenCode MCP; these commands
/// cover the ACTS-domain fleet/bridge/analysis logic that used to live in the
/// plugin (`cbm_repos`, `cbm_index_all`, `cbm_bootstrap`, `cbm_changes`,
/// `acts_memory`, `acts_tech_lead_analysis`).

pub const GraphError = error{
    BinaryNotFound,
    MissingProject,
    NotIndexed,
};

fn bin(allocator: std.mem.Allocator, cwd: []const u8) ![]const u8 {
    return cbm.findBinary(allocator, cwd) orelse {
        std.debug.print("codebase-memory-mcp not found — install with `acts setup --with-cbm`.\n", .{});
        return GraphError.BinaryNotFound;
    };
}

/// Resolve OpenCode references (opencode.json `references`) into {alias, path}.
const Reference = struct { alias: []const u8, path: []const u8 };

fn loadReferences(allocator: std.mem.Allocator, cwd: []const u8) ![]Reference {
    var out = std.ArrayList(Reference).init(allocator);
    const cfg_path = std.fs.path.join(allocator, &.{ cwd, "opencode.json" }) catch return out.toOwnedSlice();
    const content = std.fs.cwd().readFileAlloc(allocator, cfg_path, 1 << 20) catch return out.toOwnedSlice();
    defer allocator.free(content);
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch return out.toOwnedSlice();
    defer parsed.deinit();
    const v = parsed.value;
    if (v != .object) return out.toOwnedSlice();
    const refs = v.object.get("references") orelse return out.toOwnedSlice();
    if (refs != .object) return out.toOwnedSlice();
    var it = refs.object.iterator();
    while (it.next()) |e| {
        const rv = e.value_ptr.*;
        if (rv != .object) continue;
        const p = if (rv.object.get("path")) |x| if (x == .string) x.string else "" else "";
        if (p.len > 0) {
            const abs = std.fs.path.resolve(allocator, &.{ cwd, p }) catch continue;
            out.append(.{ .alias = e.key_ptr.*, .path = abs }) catch continue;
        }
    }
    return out.toOwnedSlice();
}

/// `acts graph repos` — list fleet references.
pub fn cmdRepos(allocator: std.mem.Allocator, cwd: []const u8, json_out: bool) !void {
    const refs = try loadReferences(allocator, cwd);
    if (json_out) {
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();
        var arr = std.json.Array.init(allocator);
        for (refs) |r| {
            var o = std.json.ObjectMap.init(allocator);
            try o.put("alias", .{ .string = r.alias });
            try o.put("path", .{ .string = r.path });
            try arr.append(.{ .object = o });
        }
        const val: std.json.Value = .{ .array = arr };
        try std.json.stringify(val, .{}, buf.writer());
        try std.io.getStdOut().writer().print("{s}\n", .{buf.items});
        return;
    }
    try std.io.getStdOut().writer().print("Fleet repositories (opencode.json references):\n", .{});
    for (refs) |r| {
        try std.io.getStdOut().writer().print("  {s}: {s}\n", .{ r.alias, r.path });
    }
    if (refs.len == 0) {
        try std.io.getStdOut().writer().print("  (none configured)\n", .{});
    }
}

/// `acts graph index --all` — index every reference.
pub fn cmdIndexAll(allocator: std.mem.Allocator, cwd: []const u8) !void {
    const b = try bin(allocator, cwd);
    const refs = try loadReferences(allocator, cwd);
    if (refs.len == 0) {
        try std.io.getStdOut().writer().print("no references configured in opencode.json\n", .{});
        return;
    }
    for (refs) |r| {
        const ok = cbm.ensureIndexed(allocator, b, r.path);
        try std.io.getStdOut().writer().print("  {s}: {s}\n", .{ if (ok) "✓" else "✗", r.alias });
    }
}

/// `acts graph bootstrap` — idempotent install+index (CI / fresh machines).
pub fn cmdBootstrap(allocator: std.mem.Allocator, cwd: []const u8) !void {
    const b = try bin(allocator, cwd);
    const refs = try loadReferences(allocator, cwd);
    if (refs.len == 0) {
        try std.io.getStdOut().writer().print("binary: {s}\nno references configured\n", .{b});
        return;
    }
    try std.io.getStdOut().writer().print("shared graph: {s}\n", .{cbm.cacheDir(allocator)});
    for (refs) |r| {
        const ok = cbm.ensureIndexed(allocator, b, r.path);
        try std.io.getStdOut().writer().print("  {s}: {s}\n", .{ if (ok) "✓" else "✗", r.alias });
    }
}

/// `acts graph span <id>` — map a change's files to the repos it spans.
pub fn cmdSpan(allocator: std.mem.Allocator, cwd: []const u8, change_id: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;
    const change = stack.getChange(v, change_id) orelse return error.ChangeNotFound;
    const branch = if (change.get("branch")) |x| if (x == .string) x.string else "" else "";
    const base = if (v.object.get("base_branch")) |x| if (x == .string) x.string else "" else "";

    const files = try git.diffNameOnly(allocator, base, branch);
    const refs = try loadReferences(allocator, cwd);

    var repos = std.StringHashMap(void).init(allocator);
    for (files) |f| {
        for (refs) |r| {
            const alias_seg = try std.fmt.allocPrint(allocator, "/{s}/", .{r.alias});
            const alias_start = try std.fmt.allocPrint(allocator, "{s}/", .{r.alias});
            if (std.mem.startsWith(u8, f, r.path) or
                std.mem.indexOf(u8, f, alias_seg) != null or
                std.mem.startsWith(u8, f, alias_start))
            {
                repos.put(r.alias, {}) catch {};
            }
        }
    }
    try std.io.getStdOut().writer().print("Change {s} spans: ", .{change_id});
    var first = true;
    var it = repos.keyIterator();
    while (it.next()) |k| {
        if (!first) try std.io.getStdOut().writer().print(", ", .{});
        try std.io.getStdOut().writer().print("{s}", .{k.*});
        first = false;
    }
    if (first) try std.io.getStdOut().writer().print("(none)", .{});
    try std.io.getStdOut().writer().print("\n", .{});
}

/// `acts tech-lead <id>` — pre-flight risk report for a change (replaces
/// acts_tech_lead_analysis). Combines change context + CBM graph intelligence.
pub fn cmdTechLead(allocator: std.mem.Allocator, cwd: []const u8, change_id: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;
    const change = stack.getChange(v, change_id) orelse return error.ChangeNotFound;
    const branch = if (change.get("branch")) |x| if (x == .string) x.string else "" else "";
    const base = if (v.object.get("base_branch")) |x| if (x == .string) x.string else "" else "";
    const title = if (change.get("title")) |x| if (x == .string) x.string else "" else "";
    const status = if (change.get("status")) |x| if (x == .string) x.string else "" else "";

    const b = bin(allocator, cwd) catch {
        try std.io.getStdOut().writer().print(
            "# Tech Lead Pre-Flight Report: {s}\n\n**Change:** {s}\n**Status:** {s}\n\ncodebase-memory-mcp not installed — install with `acts setup --with-cbm`.\n",
            .{ change_id, title, status },
        );
        return;
    };

    const files = try git.diffNameOnly(allocator, base, branch);
    const refs = try loadReferences(allocator, cwd);
    _ = refs;

    try std.io.getStdOut().writer().print("# Tech Lead Pre-Flight Report: {s}\n\n", .{change_id});
    try std.io.getStdOut().writer().print("**Change:** {s}\n", .{title});
    try std.io.getStdOut().writer().print("**Status:** {s}\n", .{status});
    try std.io.getStdOut().writer().print("**Files:** {d}\n\n", .{files.len});

    // For each changed file, find the repo (best-effort via path prefix).
    var riskSummary = [_]u32{0, 0, 0, 0}; // LOW, MEDIUM, HIGH, CRITICAL
    var line_count: usize = 0;

    for (files) |f| {
        const repo = findRepoForFile(allocator, cwd, f);
        if (repo == null) continue;
        const projects = cbm.listProjects(allocator, b) catch {
            try std.io.getStdOut().writer().print("(graph unavailable — not indexed? run `acts graph index --all`)\n", .{});
            return;
        };
        // Find the project whose root matches the repo path
        for (projects) |p| {
            if (std.mem.eql(u8, p.root_path, repo.?)) {
                const syms = cbm.searchSymbols(allocator, b, p.name, ".*", 20) catch &[_]cbm.Symbol{};
                for (syms) |s| {
                    const tier = classifySymbol(s);
                    const rank = tier.rank();
                    riskSummary[rank - 1] += 1;
                    if (line_count < 20) {
                        try std.io.getStdOut().writer().print(
                            "| {s} | {s} | complexity {d} | in {d} / out {d} | loop {d} |\n",
                            .{ s.name, tier.label(), s.complexity, s.in_degree, s.out_degree, s.loop_depth },
                        );
                        line_count += 1;
                    }
                }
                break;
            }
        }
    }

    try std.io.getStdOut().writer().print("\n## Risk Summary\n", .{});
    try std.io.getStdOut().writer().print("| LOW | MEDIUM | HIGH | CRITICAL |\n|---|---|---|---|\n", .{});
    try std.io.getStdOut().writer().print("| {d} | {d} | {d} | {d} |\n", .{ riskSummary[0], riskSummary[1], riskSummary[2], riskSummary[3] });
}

fn findRepoForFile(allocator: std.mem.Allocator, cwd: []const u8, file: []const u8) ?[]const u8 {
    const refs = loadReferences(allocator, cwd) catch return null;
    var best: ?[]const u8 = null;
    for (refs) |r| {
        if (std.mem.startsWith(u8, file, r.path)) {
            if (best == null or r.path.len > best.?.len) best = r.path;
        }
    }
    return best;
}

fn classifySymbol(s: cbm.Symbol) risk.RiskTier {
    if (s.out_degree >= 2 or s.complexity >= 30) return .CRITICAL;
    if (s.out_degree >= 1 or s.complexity >= 15 or s.loop_depth >= 2) return .HIGH;
    if (s.complexity >= 8 or s.in_degree >= 3) return .MEDIUM;
    return .LOW;
}
