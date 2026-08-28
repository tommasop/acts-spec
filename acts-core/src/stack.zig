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

pub fn branchOf(v: std.json.Value) ?[]const u8 {
    if (v.object.get("branch")) |b| {
        if (b == .string and b.string.len > 0) return b.string;
    }
    if (v.object.get("base_branch")) |b| {
        if (b == .string and b.string.len > 0) return b.string;
    }
    return null;
}

pub fn integrationBranch(v: std.json.Value) []const u8 {
    if (v.object.get("base_branch")) |b| {
        if (b == .string) return b.string;
    }
    return "";
}

pub fn setBranch(allocator: std.mem.Allocator, v: *std.json.Value, branch: []const u8) !bool {
    _ = allocator;
    try v.object.put("branch", .{ .string = branch });
    return true;
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
    // A forced verification (e.g. failures attributed to files outside this
    // change, or manual evidence recorded when tooling is broken) counts as
    // passed, but is always surfaced via `verify.forced`/`verify.force_reason`.
    if (verify.object.get("forced")) |f| {
        if (f == .bool and f.bool) return true;
    }
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

/// True if this change's verification was forced (overridden) or manual.
pub fn isVerifyForced(v: std.json.Value, id: []const u8) bool {
    const m = getChange(v, id) orelse return false;
    const verify = m.get("verify") orelse return false;
    if (verify != .object) return false;
    if (verify.object.get("forced")) |f| {
        if (f == .bool and f.bool) return true;
    }
    return false;
}

pub fn getVerifyForcedReason(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    const verify = m.get("verify") orelse return null;
    if (verify != .object) return null;
    if (verify.object.get("force_reason")) |r| {
        if (r == .string) return r.string;
    }
    return null;
}

/// Mark a change's verification as forced, recording why. `kind` is
/// "force" (gates ran, failures outside the change) or "manual" (gates skipped).
pub fn setVerifyForced(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, kind: []const u8, reason: []const u8) !bool {
    const m = getChange(v, id) orelse return false;
    const vgop = try m.getOrPut("verify");
    if (!vgop.found_existing) vgop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    const vm = &vgop.value_ptr.*.object;
    try vm.put("forced", .{ .bool = true });
    try vm.put("force_kind", .{ .string = kind });
    try vm.put("force_reason", .{ .string = reason });
    try vm.put("forced_at", .{ .integer = @intCast(std.time.timestamp()) });
    return true;
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

pub fn changeStartSha(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    if (m.get("start_sha")) |s| {
        if (s == .string and s.string.len > 0) return s.string;
    }
    return null;
}

pub fn setChangeStartSha(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, sha: []const u8) !bool {
    _ = allocator;
    const m = getChange(v, id) orelse return false;
    try m.put("start_sha", .{ .string = sha });
    return true;
}

pub fn changeEndSha(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    if (m.get("end_sha")) |s| {
        if (s == .string and s.string.len > 0) return s.string;
    }
    return null;
}

pub fn setChangeEndSha(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, sha: []const u8) !bool {
    _ = allocator;
    const m = getChange(v, id) orelse return false;
    try m.put("end_sha", .{ .string = sha });
    return true;
}

pub fn changeIsLegacy(v: std.json.Value, id: []const u8) bool {
    return legacyChangeBranch(v, id) != null and changeStartSha(v, id) == null;
}

pub fn legacyChangeBranch(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    if (m.get("branch")) |b| {
        if (b == .string and b.string.len > 0) return b.string;
    }
    return null;
}

pub const DiffRange = struct { from: []const u8, to: []const u8 };

pub fn changeDiffRange(v: std.json.Value, id: []const u8) DiffRange {
    if (changeStartSha(v, id)) |start| {
        return .{ .from = start, .to = changeEndSha(v, id) orelse "HEAD" };
    }
    if (legacyChangeBranch(v, id)) |cbranch| {
        return .{ .from = integrationBranch(v), .to = cbranch };
    }
    return .{ .from = "", .to = "" };
}

pub fn stackPrUrl(v: std.json.Value) ?[]const u8 {
    const pr = v.object.get("pr") orelse return null;
    if (pr != .object) return null;
    if (pr.object.get("url")) |u| {
        if (u == .string and u.string.len > 0) return u.string;
    }
    return null;
}

pub fn setStackPrUrl(allocator: std.mem.Allocator, v: *std.json.Value, url: []const u8) !bool {
    const gop = try v.object.getOrPut("pr");
    if (!gop.found_existing) gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    try gop.value_ptr.*.object.put("url", .{ .string = url });
    return true;
}

pub fn allApproved(v: std.json.Value) bool {
    const changes = v.object.get("changes") orelse return false;
    if (changes != .array) return false;
    var any_non_merged = false;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const st = c.object.get("status") orelse continue;
        const s = if (st == .string) st.string else "";
        if (std.mem.eql(u8, s, status_merged)) continue;
        any_non_merged = true;
        if (!std.mem.eql(u8, s, status_approved)) return false;
    }
    return any_non_merged;
}

/// True when every non-merged change has verification evidence that passed.
pub fn allVerified(v: std.json.Value) bool {
    const changes = v.object.get("changes") orelse return false;
    if (changes != .array) return false;
    var any_non_merged = false;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const st = c.object.get("status") orelse continue;
        const s = if (st == .string) st.string else "";
        if (std.mem.eql(u8, s, status_merged)) continue;
        any_non_merged = true;
        if (c.object.get("id")) |idv| {
            if (idv == .string and !verifyAllPassed(v, idv.string)) return false;
        }
    }
    return any_non_merged;
}

pub fn unapprovedChanges(allocator: std.mem.Allocator, v: std.json.Value) ![][]const u8 {
    var out = std.ArrayList([]const u8).init(allocator);
    const changes = v.object.get("changes") orelse return out.toOwnedSlice();
    if (changes != .array) return out.toOwnedSlice();
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const st = c.object.get("status") orelse continue;
        const s = if (st == .string) st.string else "";
        if (std.mem.eql(u8, s, status_merged)) continue;
        if (std.mem.eql(u8, s, status_approved)) continue;
        if (c.object.get("id")) |idv| {
            if (idv == .string) try out.append(idv.string);
        }
    }
    return out.toOwnedSlice();
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

    var ver: i64 = 0;
    if (root.get("version")) |verv| {
        if (verv == .integer) ver = verv.integer;
    }
    if (ver != 2 and ver != 3) {
        try out.writer().print("manifest version must be 2 or 3 (got {any})\n", .{root.get("version")});
    }
    if (root.get("id") == null) try out.appendSlice("missing 'id'\n");
    if (root.get("title") == null) try out.appendSlice("missing 'title'\n");
    if (ver == 3 and root.get("branch") == null) try out.appendSlice("missing 'branch'\n");
    if (root.get("base_branch") == null) try out.appendSlice("missing 'base_branch'\n");

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
        const has_branch = c.object.get("branch") != null;
        const has_start = c.object.get("start_sha") != null;
        if (!has_branch and !has_start) {
            try out.writer().print("change {s}: missing 'branch' (legacy v2) or 'start_sha' (v3)\n", .{id_str});
        }
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

test "v3 manifest validates and legacy v2 still validates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // v3 fixture
    var r3 = std.json.ObjectMap.init(a);
    try r3.put("version", .{ .integer = 3 });
    try r3.put("id", .{ .string = "auth" });
    try r3.put("title", .{ .string = "Add auth" });
    try r3.put("branch", .{ .string = "acts/auth/feature" });
    try r3.put("base_branch", .{ .string = "master" });
    var ch3 = std.json.Array.init(a);
    var c3 = std.json.ObjectMap.init(a);
    try c3.put("id", .{ .string = "c1" });
    try c3.put("title", .{ .string = "JWT" });
    try c3.put("status", .{ .string = "TODO" });
    try c3.put("start_sha", .{ .string = "abc" });
    try ch3.append(.{ .object = c3 });
    try r3.put("changes", .{ .array = ch3 });
    const v3: std.json.Value = .{ .object = r3 };
    const problems3 = try validate(a, v3);
    try std.testing.expectEqual(@as(usize, 0), std.mem.trim(u8, problems3, " \n\r").len);

    // v2 fixture (per-change branch, no start_sha) still validates
    var r2 = std.json.ObjectMap.init(a);
    try r2.put("version", .{ .integer = 2 });
    try r2.put("id", .{ .string = "legacy" });
    try r2.put("title", .{ .string = "Legacy" });
    try r2.put("base_branch", .{ .string = "acts/legacy/base" });
    var ch2 = std.json.Array.init(a);
    var c2 = std.json.ObjectMap.init(a);
    try c2.put("id", .{ .string = "c1" });
    try c2.put("title", .{ .string = "JWT" });
    try c2.put("status", .{ .string = "MERGED" });
    try c2.put("branch", .{ .string = "acts/legacy/c1-jwt" });
    try ch2.append(.{ .object = c2 });
    try r2.put("changes", .{ .array = ch2 });
    const v2: std.json.Value = .{ .object = r2 };
    const problems2 = try validate(a, v2);
    try std.testing.expectEqual(@as(usize, 0), std.mem.trim(u8, problems2, " \n\r").len);

    // v3 change missing both branch and start_sha → error
    var cbad = std.json.ObjectMap.init(a);
    try cbad.put("id", .{ .string = "c2" });
    try cbad.put("title", .{ .string = "Bad" });
    try cbad.put("status", .{ .string = "TODO" });
    var chbad = std.json.Array.init(a);
    try chbad.append(.{ .object = cbad });
    try r3.put("changes", .{ .array = chbad });
    const vbad: std.json.Value = .{ .object = r3 };
    const problems_bad = try validate(a, vbad);
    try std.testing.expect(std.mem.indexOf(u8, problems_bad, "branch") != null or std.mem.indexOf(u8, problems_bad, "start_sha") != null);
}

test "branchOf and changeDiffRange resolve v3 checkpoints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var r = std.json.ObjectMap.init(a);
    try r.put("version", .{ .integer = 3 });
    try r.put("branch", .{ .string = "acts/auth/feature" });
    try r.put("base_branch", .{ .string = "master" });
    var ch = std.json.Array.init(a);
    var c = std.json.ObjectMap.init(a);
    try c.put("id", .{ .string = "c1" });
    try c.put("status", .{ .string = "TODO" });
    try c.put("start_sha", .{ .string = "abc" });
    try c.put("end_sha", .{ .string = "def" });
    try ch.append(.{ .object = c });
    try r.put("changes", .{ .array = ch });
    const v: std.json.Value = .{ .object = r };

    try std.testing.expectEqualStrings("acts/auth/feature", branchOf(v).?);
    try std.testing.expectEqualStrings("master", integrationBranch(v));
    const range = changeDiffRange(v, "c1");
    try std.testing.expectEqualStrings("abc", range.from);
    try std.testing.expectEqualStrings("def", range.to);
    try std.testing.expect(allApproved(v) == false);
    const un = try unapprovedChanges(a, v);
    try std.testing.expectEqual(@as(usize, 1), un.len);
    try std.testing.expectEqualStrings("c1", un[0]);
}

test "setStackPrUrl roundtrips and allApproved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var r = std.json.ObjectMap.init(a);
    try r.put("version", .{ .integer = 3 });
    try r.put("branch", .{ .string = "acts/auth/feature" });
    try r.put("base_branch", .{ .string = "master" });
    var ch = std.json.Array.init(a);
    var c1 = std.json.ObjectMap.init(a);
    try c1.put("id", .{ .string = "c1" });
    try c1.put("status", .{ .string = "APPROVED" });
    try ch.append(.{ .object = c1 });
    var c2 = std.json.ObjectMap.init(a);
    try c2.put("id", .{ .string = "c2" });
    try c2.put("status", .{ .string = "APPROVED" });
    try ch.append(.{ .object = c2 });
    try r.put("changes", .{ .array = ch });
    var v: std.json.Value = .{ .object = r };

    _ = try setStackPrUrl(a, &v, "https://github.com/x/pull/9");
    try std.testing.expectEqualStrings("https://github.com/x/pull/9", stackPrUrl(v).?);
    try std.testing.expect(allApproved(v));
}
