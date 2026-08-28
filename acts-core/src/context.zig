const std = @import("std");
const stack = @import("stack.zig");
const git = @import("git.zig");

/// Build a scoped context pack for a change. This is the durable task state an
/// agent consumes at session start: acceptance criteria, verification status,
/// checkpoint, notes, changed files, commit history, and preceding changes.
pub fn buildContextPack(
    allocator: std.mem.Allocator,
    v: std.json.Value,
    change_id: []const u8,
) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);

    const root = &v.object;
    const stack_id = if (root.get("id")) |s| if (s == .string) s.string else "" else "";
    const title = if (root.get("title")) |s| if (s == .string) s.string else "" else "";
    const feat = stack.branchOf(v) orelse "";
    const integ = stack.integrationBranch(v);

    const m = stack.getChange(v, change_id) orelse return error.ChangeNotFound;
    const change_title = if (m.get("title")) |s| if (s == .string) s.string else "" else "";
    const status = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
    const range = stack.changeDiffRange(v, change_id);

    try out.writer().print(
        \\# ACTS Context Pack
        \\
        \\## Stack
        \\- id: {s}
        \\- title: {s}
        \\- feature branch: {s} (off {s})
        \\
        \\## Change: {s}
        \\- title: {s}
        \\- status: {s}
        \\- range: {s}..{s}
        \\
    , .{ stack_id, title, feat, integ, change_id, change_title, status, range.from, range.to });

    // Acceptance criteria
    try out.appendSlice("\n## Acceptance Criteria\n");
    if (m.get("acceptance")) |acc| {
        if (acc == .array) {
            if (acc.array.items.len == 0) {
                try out.appendSlice("- (none recorded)\n");
            } else {
                for (acc.array.items) |item| {
                    const s = if (item == .string) item.string else "?";
                    try out.writer().print("- {s}\n", .{s});
                }
            }
        } else {
            try out.appendSlice("- (none recorded)\n");
        }
    } else {
        try out.appendSlice("- (none recorded)\n");
    }

    // Preceding changes (context continuity: what came before this checkpoint)
    try out.appendSlice("\n## Preceding Changes\n");
    var prev_found = false;
    if (root.get("changes")) |changes| {
        if (changes == .array) {
            for (changes.array.items) |*c| {
                if (c.* != .object) continue;
                const pm = &c.*.object;
                const pcid = if (pm.get("id")) |x| if (x == .string) x.string else "" else "";
                if (std.mem.eql(u8, pcid, change_id)) break;
                const pt = if (pm.get("title")) |x| if (x == .string) x.string else "" else "";
                const ps = if (pm.get("status")) |x| if (x == .string) x.string else "" else "";
                try out.writer().print("- {s}: {s} ({s})\n", .{ pcid, pt, ps });
                prev_found = true;
            }
        }
    }
    if (!prev_found) try out.appendSlice("- (first change in stack)\n");

    // Verification status
    try out.appendSlice("\n## Verification\n");
    if (stack.isVerifyForced(v, change_id)) {
        try out.appendSlice("> ⚠️ FORCED verification (overridden)\n");
        if (stack.getVerifyForcedReason(v, change_id)) |reason| {
            try out.writer().print("> Reason: {s}\n", .{reason});
        }
    }
    if (m.get("verify")) |ver| {
        if (ver == .object) {
            for (stack.verify_stages) |stage| {
                if (ver.object.get(stage)) |r| {
                    if (r == .object) {
                        const ok = if (r.object.get("ok")) |o| o == .bool and o.bool else false;
                        const cmd = if (r.object.get("cmd")) |c| if (c == .string) c.string else "" else "";
                        try out.writer().print("- {s}: {s} ({s})\n", .{ stage, if (ok) "PASS" else "FAIL", cmd });
                    }
                }
            }
        }
    } else {
        try out.appendSlice("- not verified yet\n");
    }

    // Checkpoint
    if (stack.getCheckpoint(v, change_id)) |cp| {
        try out.writer().print("\n## Checkpoint\n{s}\n", .{cp});
    }

    // Notes (session summaries)
    try out.appendSlice("\n## Session Notes\n");
    if (m.get("notes")) |notes| {
        if (notes == .array) {
            if (notes.array.items.len == 0) {
                try out.appendSlice("- (no session notes)\n");
            } else {
                for (notes.array.items) |n| {
                    const s = if (n == .string) n.string else "?";
                    try out.writer().print("- {s}\n", .{s});
                }
            }
        }
    } else {
        try out.appendSlice("- (no session notes)\n");
    }

    // Changed files (blast radius from the checkpoint range)
    if (range.from.len > 0) {
        const files = if (stack.changeEndSha(v, change_id) != null)
            (git.diffNameOnly(allocator, range.from, range.to) catch &[_][]const u8{})
        else
            (git.changedFilesSince(allocator, range.from) catch &[_][]const u8{});
        try out.appendSlice("\n## Changed Files\n");
        if (files.len == 0) {
            try out.appendSlice("- (no changes yet)\n");
        } else {
            for (files) |f| {
                try out.writer().print("- {s}\n", .{f});
            }
        }
    }

    // Commit history since the checkpoint start
    if (range.from.len > 0) {
        const log = git.gitLogOneline(allocator, range.from, 10) catch "";
        if (log.len > 0) {
            try out.writer().print("\n## Commits (since {s})\n{s}\n", .{ range.from, log });
        }
    }

    return out.toOwnedSlice();
}
