const std = @import("std");

pub const manifest_path = ".acts/stack.json";
pub const manifest_dir = ".acts";

pub const status_todo = "TODO";
pub const status_in_progress = "IN_PROGRESS";
pub const status_verified = "VERIFIED";
pub const status_in_review = "IN_REVIEW";
pub const status_approved = "APPROVED";
pub const status_merged = "MERGED";

pub const verify_stages = [_][]const u8{ "test", "lint", "typecheck", "build" };

pub const StackError = error{
    NotFound,
    ManifestInvalid,
    ChangeNotFound,
    ChangeExists,
    BranchConflict,
    NotGitRepo,
};

pub fn manifestExists() bool {
    std.fs.cwd().access(manifest_path, .{}) catch return false;
    return true;
}

/// Load the stack manifest as a JSON Value. Caller frees with `parsed.deinit()`.
pub fn load(allocator: std.mem.Allocator) !std.json.Parsed(std.json.Value) {
    const file = std.fs.cwd().openFile(manifest_path, .{}) catch return StackError.NotFound;
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    if (parsed.value != .object) {
        parsed.deinit();
        return StackError.ManifestInvalid;
    }
    return parsed;
}

/// Save a JSON Value to the manifest path.
pub fn save(allocator: std.mem.Allocator, value: std.json.Value) !void {
    std.fs.cwd().makePath(manifest_dir) catch {};
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    try std.json.stringify(value, .{ .whitespace = .indent_2 }, buf.writer());
    try buf.append('\n');
    try std.fs.cwd().writeFile(.{ .sub_path = manifest_path, .data = buf.items });
}

/// Mutable pointer to a change object inside the parsed manifest.
pub fn getChange(v: std.json.Value, id: []const u8) ?*std.json.ObjectMap {
    const changes = v.object.get("changes") orelse return null;
    if (changes != .array) return null;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        if (c.object.get("id")) |idv| {
            if (idv == .string and std.mem.eql(u8, idv.string, id)) return &c.object;
        }
    }
    return null;
}

/// Index of a change in the changes array, or null.
pub fn changeIndex(v: std.json.Value, id: []const u8) ?usize {
    const changes = v.object.get("changes") orelse return null;
    if (changes != .array) return null;
    for (changes.array.items, 0..) |*c, i| {
        if (c.* != .object) continue;
        if (c.object.get("id")) |idv| {
            if (idv == .string and std.mem.eql(u8, idv.string, id)) return i;
        }
    }
    return null;
}

pub fn changeStatus(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    if (m.get("status")) |s| {
        if (s == .string) return s.string;
    }
    return null;
}

pub fn setChangeString(v: std.json.Value, id: []const u8, key: []const u8, value: []const u8) !bool {
    const m = getChange(v, id) orelse return false;
    try m.put(key, .{ .string = value });
    return true;
}

/// Append a note path to a change's `notes` array.
pub fn appendNote(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, note: []const u8) !bool {
    const m = getChange(v, id) orelse return false;
    const gop = try m.getOrPut("notes");
    if (!gop.found_existing) gop.value_ptr.* = .{ .array = std.json.Array.init(allocator) };
    try gop.value_ptr.*.array.append(.{ .string = note });
    return true;
}

/// Record a verify result for a stage: {cmd, ok, exit_code, duration_ms}.
pub fn recordVerify(
    allocator: std.mem.Allocator,
    v: std.json.Value,
    id: []const u8,
    stage: []const u8,
    cmd: []const u8,
    ok: bool,
    exit_code: i32,
    duration_ms: u64,
) !bool {
    const m = getChange(v, id) orelse return false;
    const vgop = try m.getOrPut("verify");
    if (!vgop.found_existing) vgop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    const vm = &vgop.value_ptr.*.object;
    const rgop = try vm.getOrPut(stage);
    if (!rgop.found_existing) rgop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    const rm = &rgop.value_ptr.*.object;
    const cmd_copy = try allocator.dupe(u8, cmd);
    try rm.put("cmd", .{ .string = cmd_copy });
    try rm.put("ok", .{ .bool = ok });
    try rm.put("exit_code", .{ .integer = exit_code });
    try rm.put("duration_ms", .{ .integer = @intCast(duration_ms) });
    return true;
}

pub fn verifyAllPassed(v: std.json.Value, id: []const u8) bool {
    const m = getChange(v, id) orelse return false;
    const verify = m.get("verify") orelse return false;
    if (verify != .object) return false;
    var any = false;
    for (verify_stages) |stage| {
        const r = verify.object.get(stage) orelse continue;
        if (r == .object) {
            any = true;
            if (r.object.get("ok")) |okv| {
                if (okv == .bool and !okv.bool) return false;
            }
        }
    }
    return any;
}

/// Store the base branch SHA at the time verification ran, so callers can
/// detect a stale verification (base moved since verify).
pub fn setVerifyBaseSha(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, sha: []const u8) !bool {
    const m = getChange(v, id) orelse return false;
    const vgop = try m.getOrPut("verify");
    if (!vgop.found_existing) vgop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    try vgop.value_ptr.*.object.put("base_sha", .{ .string = sha });
    return true;
}

pub fn getVerifyBaseSha(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    const verify = m.get("verify") orelse return null;
    if (verify != .object) return null;
    if (verify.object.get("base_sha")) |s| {
        if (s == .string) return s.string;
    }
    return null;
}

/// Set the computed risk tier for a change.
pub fn setRisk(v: std.json.Value, id: []const u8, tier: []const u8) !bool {
    const m = getChange(v, id) orelse return false;
    try m.put("risk", .{ .string = tier });
    return true;
}

pub fn getRisk(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    if (m.get("risk")) |r| {
        if (r == .string) return r.string;
    }
    return null;
}

/// Store CBM-derived risk detail for a change (cross-repo edges, complexity).
pub const RiskMeta = struct {
    cross_repo_edges: usize = 0,
    high_complexity_symbols: usize = 0,
};

pub fn setRiskMeta(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, cross_repo_edges: usize, high_complexity_symbols: usize) !bool {
    const m = getChange(v, id) orelse return false;
    const gop = try m.getOrPut("risk_cbm");
    if (!gop.found_existing) gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    try gop.value_ptr.*.object.put("cross_repo_edges", .{ .integer = @intCast(cross_repo_edges) });
    try gop.value_ptr.*.object.put("high_complexity_symbols", .{ .integer = @intCast(high_complexity_symbols) });
    return true;
}

pub fn getRiskMeta(v: std.json.Value, id: []const u8) RiskMeta {
    var out = RiskMeta{};
    const m = getChange(v, id) orelse return out;
    const r = m.get("risk_cbm") orelse return out;
    if (r != .object) return out;
    if (r.object.get("cross_repo_edges")) |c| {
        if (c == .integer) out.cross_repo_edges = @intCast(c.integer);
    }
    if (r.object.get("high_complexity_symbols")) |c| {
        if (c == .integer) out.high_complexity_symbols = @intCast(c.integer);
    }
    return out;
}

/// Append an approval/rework record to the change's `approvals` audit log.
pub fn appendApproval(
    allocator: std.mem.Allocator,
    v: std.json.Value,
    id: []const u8,
    action: []const u8,
    by: []const u8,
    tier: []const u8,
    note: []const u8,
) !bool {
    const m = getChange(v, id) orelse return false;
    const gop = try m.getOrPut("approvals");
    if (!gop.found_existing) gop.value_ptr.* = .{ .array = std.json.Array.init(allocator) };

    const ts = std.time.timestamp();
    var entry = std.json.ObjectMap.init(allocator);
    try entry.put("action", .{ .string = action });
    try entry.put("by", .{ .string = by });
    try entry.put("tier", .{ .string = tier });
    try entry.put("ts", .{ .integer = @intCast(ts) });
    if (note.len > 0) try entry.put("note", .{ .string = note });

    try gop.value_ptr.*.array.append(.{ .object = entry });
    return true;
}

/// Record a per-change cost (from `acts note --cost`).
pub fn setCost(v: std.json.Value, id: []const u8, cost: f64) !bool {
    const m = getChange(v, id) orelse return false;
    try m.put("cost", .{ .float = cost });
    return true;
}

pub fn getCost(v: std.json.Value, id: []const u8) ?f64 {
    const m = getChange(v, id) orelse return null;
    if (m.get("cost")) |c| {
        if (c == .float) return c.float;
        if (c == .integer) return @floatFromInt(c.integer);
    }
    return null;
}

pub fn setPrUrl(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, url: []const u8) !bool {
    const m = getChange(v, id) orelse return false;
    const gop = try m.getOrPut("pr");
    if (!gop.found_existing) gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    try gop.value_ptr.*.object.put("url", .{ .string = url });
    return true;
}

pub fn setPrApproved(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, approved: bool) !bool {
    const m = getChange(v, id) orelse return false;
    const gop = try m.getOrPut("pr");
    if (!gop.found_existing) gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    try gop.value_ptr.*.object.put("approved", .{ .bool = approved });
    return true;
}

pub fn setCheckpoint(v: std.json.Value, id: []const u8, summary: []const u8) !bool {
    const m = getChange(v, id) orelse return false;
    try m.put("checkpoint", .{ .string = summary });
    return true;
}

pub fn getCheckpoint(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    if (m.get("checkpoint")) |c| {
        if (c == .string) return c.string;
    }
    return null;
}

/// The parent change id (or null) for a change.
pub fn parentOf(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    if (m.get("parent")) |p| {
        if (p == .string) return p.string;
    }
    return null;
}

/// The id of the current top of the stack (last non-merged change in insertion order).
pub fn topChange(v: std.json.Value) ?[]const u8 {
    const changes = v.object.get("changes") orelse return null;
    if (changes != .array or changes.array.items.len == 0) return null;
    var top: ?[]const u8 = null;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        if (c.object.get("status")) |s| {
            if (s == .string and std.mem.eql(u8, s.string, status_merged)) continue;
        }
        if (c.object.get("id")) |idv| {
            if (idv == .string) top = idv.string;
        }
    }
    return top;
}

/// Basic structural validation. Returns error messages joined in `out`.
pub fn validate(allocator: std.mem.Allocator, v: std.json.Value) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    const root = &v.object;

    if (root.get("version")) |ver| {
        if (ver != .integer or ver.integer != 2) {
            try out.writer().print("manifest version must be 2 (got {any})\n", .{ver});
        }
    } else {
        try out.appendSlice("missing 'version'\n");
    }
    if (root.get("id") == null) try out.appendSlice("missing 'id'\n");
    if (root.get("base_branch") == null) try out.appendSlice("missing 'base_branch'\n");
    if (root.get("title") == null) try out.appendSlice("missing 'title'\n");

    const changes = root.get("changes") orelse {
        try out.appendSlice("missing 'changes'\n");
        return out.toOwnedSlice();
    };
    if (changes != .array) {
        try out.appendSlice("'changes' must be an array\n");
        return out.toOwnedSlice();
    }

    for (changes.array.items) |*c| {
        if (c.* != .object) {
            try out.appendSlice("change entry is not an object\n");
            continue;
        }
        const id = c.object.get("id") orelse {
            try out.appendSlice("change missing 'id'\n");
            continue;
        };
        const id_str = if (id == .string) id.string else "";
        if (c.object.get("title") == null) try out.writer().print("change {s}: missing 'title'\n", .{id_str});
        if (c.object.get("status") == null) try out.writer().print("change {s}: missing 'status'\n", .{id_str});
        if (c.object.get("branch") == null) try out.writer().print("change {s}: missing 'branch'\n", .{id_str});
        if (c.object.get("acceptance") != null) {
            if (c.object.get("acceptance").? != .array) {
                try out.writer().print("change {s}: 'acceptance' must be array\n", .{id_str});
            }
        }
        if (c.object.get("parent") != null and c.object.get("parent").? != .null and c.object.get("parent").? != .string) {
            try out.writer().print("change {s}: 'parent' must be string or null\n", .{id_str});
        }
    }
    return out.toOwnedSlice();
}
