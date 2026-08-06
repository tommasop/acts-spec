const std = @import("std");
const cbm = @import("cbm.zig");
const risk = @import("risk.zig");

/// Static heuristic risk analysis of a spec/plan document, merged with CBM
/// code-intelligence. `acts doc-risk <file>` evaluates the document and
/// highlights the major painpoints.

const Category = struct {
    name: []const u8,
    score: u32, // 0-100
};

const CategoryDef = struct {
    name: []const u8,
    patterns: []const []const u8,
    weight: u32,
};

const categories = [_]CategoryDef{
    .{ .name = "Scope & size", .weight = 1, .patterns = &.{ "api", "endpoint", "database", "schema", "migration", "service", "component", "module", "integration" } },
    .{ .name = "Ambiguity", .weight = 3, .patterns = &.{ "etc", "etc.", "some", "maybe", "possibly", "probably", "eventually", "later", "sometime", "placeholder", "tbd", "todo", "fixme", "and so on", "more" } },
    .{ .name = "Tech debt / migration", .weight = 3, .patterns = &.{ "legacy", "rewrite", "refactor", "migration", "deprecat", "replatform", "tech debt", "monolith" } },
    .{ .name = "Integration & deps", .weight = 2, .patterns = &.{ "integrate", "third-party", "third party", "webhook", "depends on", "blocked by", "dependency", "sync", "asynchronous", "queue" } },
    .{ .name = "Concurrency / data", .weight = 2, .patterns = &.{ "concurrent", "race", "atomic", "eventual", "idempotent", "transaction", "consisten", "ordering", "deadlock" } },
    .{ .name = "Security / compliance", .weight = 3, .patterns = &.{ "auth", "authorization", "payment", "billing", "pii", "compliance", "gdpr", "encrypt", "secret", "token" } },
    .{ .name = "Testability", .weight = 2, .patterns = &.{ "verify", "returns", "assert", "test", "should ", "expect" } },
};

const TestableWords = struct { matches: u32, words: u32 };

/// Extract a document (from a local path or URL) and analyze it.
pub fn analyze(allocator: std.mem.Allocator, content: []const u8) ![]u8 {
    const words = countWords(content);
    const lower = toLower(allocator, content);
    defer allocator.free(lower);

    // Score each category by pattern hits (weighted).
    var scored: [categories.len]Category = undefined;
    for (categories, 0..) |cat, i| {
        var hits: u32 = 0;
        for (cat.patterns) |p| {
            var it = std.mem.window(u8, lower, p.len, 1);
            while (it.next()) |w| {
                if (std.mem.eql(u8, w, p)) hits += 1;
            }
        }
        // Testability: presence of concrete criteria lowers risk; absence raises it.
        if (std.mem.eql(u8, cat.name, "Testability")) {
            const base: u32 = if (hits > 0) 30 else 70;
            scored[i] = .{ .name = cat.name, .score = @min(100, base + cat.weight * 5) };
        } else {
            const s = @min(100, hits * cat.weight * 10);
            scored[i] = .{ .name = cat.name, .score = s };
        }
    }

    // Painpoint lines: lines matching high-risk / ambiguous patterns.
    const painpoints = try extractPainpoints(allocator, content);

    // Overall tier = worst category.
    var worst: risk.RiskTier = .LOW;
    var worst_score: u32 = 0;
    for (scored) |c| {
        if (c.score > worst_score) {
            worst_score = c.score;
            worst = if (c.score >= 80) .CRITICAL else if (c.score >= 60) .HIGH else if (c.score >= 35) .MEDIUM else .LOW;
        }
    }
    _ = words;

    // Build the report.
    var out = std.ArrayList(u8).init(allocator);
    try out.writer().print("Overall risk: {s} (worst category {d}/100)\n\n", .{ worst.label(), worst_score });
    try out.appendSlice("| Category | Score | Tier |\n");
    try out.appendSlice("|---|---|---|\n");
    for (scored) |c| {
        const t = if (c.score >= 80) "CRITICAL" else if (c.score >= 60) "HIGH" else if (c.score >= 35) "MEDIUM" else "LOW";
        try out.writer().print("| {s} | {d} | {s} |\n", .{ c.name, c.score, t });
    }
    try out.appendSlice("\n## Major Painpoints\n");
    if (painpoints.len == 0) {
        try out.appendSlice("- (none detected)\n");
    } else {
        var i: usize = 1;
        for (painpoints) |p| {
            try out.writer().print("{d}. [HIGH] \"{s}\"\n", .{ i, p });
            i += 1;
        }
    }
    return out.toOwnedSlice();
}

fn countWords(s: []const u8) usize {
    var n: usize = 0;
    var in_word = false;
    for (s) |ch| {
        const w = std.ascii.isAlphanumeric(ch);
        if (w and !in_word) {
            n += 1;
            in_word = true;
        } else if (!w) {
            in_word = false;
        }
    }
    return n;
}

fn toLower(allocator: std.mem.Allocator, s: []const u8) []u8 {
    const out = allocator.alloc(u8, s.len) catch return &[_]u8{};
    for (s, 0..) |ch, i| out[i] = std.ascii.toLower(ch);
    return out;
}

fn extractPainpoints(allocator: std.mem.Allocator, content: []const u8) ![][]const u8 {
    var out = std.ArrayList([]const u8).init(allocator);
    var it = std.mem.splitScalar(u8, content, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len == 0) continue;
        const lower = toLower(allocator, t);
        defer allocator.free(lower);
        // Flag lines that mention legacy/migration/integration or ambiguity.
        if (std.mem.indexOf(u8, lower, "legacy") != null or
            std.mem.indexOf(u8, lower, "migration") != null or
            std.mem.indexOf(u8, lower, "refactor") != null or
            std.mem.indexOf(u8, lower, "integrate") != null or
            std.mem.indexOf(u8, lower, "etc") != null or
            std.mem.indexOf(u8, lower, "tbd") != null or
            std.mem.indexOf(u8, lower, "maybe") != null or
            std.mem.indexOf(u8, lower, "depends on") != null or
            std.mem.indexOf(u8, lower, "cross-repo") != null)
        {
            out.append(t) catch {};
        }
    }
    // Cap to the top 10 painpoints.
    if (out.items.len > 10) {
        out.shrinkRetainingCapacity(10);
    }
    return out.toOwnedSlice();
}

test "extractPainpoints flags legacy/migration lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const doc =
        \\Migrate the legacy auth service to OAuth2.
        \\Add a login page with email and password.
        \\Improve performance etc.
    ;
    const p = try extractPainpoints(a, doc);
    try std.testing.expect(p.len >= 2);
    var found_legacy = false;
    var found_etc = false;
    for (p) |x| {
        if (std.mem.indexOf(u8, x, "legacy") != null) found_legacy = true;
        if (std.mem.indexOf(u8, x, "etc") != null) found_etc = true;
    }
    try std.testing.expect(found_legacy);
    try std.testing.expect(found_etc);
}

test "analyze returns a report with an overall tier" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const doc =
        \\Migrate the legacy billing service to the new platform.
        \\Depends on the payments team's webhook.
        \\Improve performance etc.
    ;
    const report = try analyze(a, doc);
    try std.testing.expect(std.mem.indexOf(u8, report, "Overall risk:") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Major Painpoints") != null);
}
