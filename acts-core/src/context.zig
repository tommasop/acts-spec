const std = @import("std");
const stack = @import("stack.zig");
const git = @import("git.zig");

/// Build a scoped context pack for a change. This is the durable task state an
/// agent consumes at session start: acceptance criteria, verification status,
/// checkpoint, notes, changed files, commit history, and parent chain.
pub fn buildContextPack(
    allocator: std.mem.Allocator,
    v: std.json.Value,
    change_id: []const u8,
) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);

    const root = &v.object;
    const stack_id = if (root.get("id")) |s| if (s == .string) s.string else "" else "";
    const title = if (root.get("title")) |s| if (s == .string) s.string else "" else "";

    const m = stack.getChange(v, change_id) orelse return error.ChangeNotFound;
    const change_title = if (m.get("title")) |s| if (s == .string) s.string else "" else "";
    const status = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
    const branch = if (m.get("branch")) |s| if (s == .string) s.string else "" else "";
    const base_branch = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";

    try out.writer().print(
        \\# ACTS Context Pack
        \\
        \\## Stack
        \\- id: {s}
        \\- title: {s}
        \\- base branch: {s}
        \\
        \\## Change: {s}
        \\- title: {s}
        \\- status: {s}
        \\- branch: {s}
        \\
    , .{ stack_id, title, base_branch, change_id, change_title, status, branch });

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

    // Parent chain (context continuity: what came before this change)
    try out.appendSlice("\n## Parent Chain\n");
    var cur: ?[]const u8 = stack.parentOf(v, change_id);
    if (cur == null) {
        try out.appendSlice("- (first change in stack)\n");
    } else {
        while (cur) |cid| {
            const pm = stack.getChange(v, cid) orelse break;
            const pt = if (pm.get("title")) |s| if (s == .string) s.string else "" else "";
            const ps = if (pm.get("status")) |s| if (s == .string) s.string else "" else "";
            try out.writer().print("- {s}: {s} ({s})\n", .{ cid, pt, ps });
            cur = stack.parentOf(v, cid);
        }
    }

    // Verification status
    try out.appendSlice("\n## Verification\n");
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

    // Changed files (blast radius from git)
    if (branch.len > 0) {
        const files = git.changedFilesSince(allocator, base_branch) catch &[_][]const u8{};
        try out.appendSlice("\n## Changed Files\n");
        if (files.len == 0) {
            try out.appendSlice("- (no changes yet)\n");
        } else {
            for (files) |f| {
                try out.writer().print("- {s}\n", .{f});
            }
        }
    }

    // Commit history
    if (branch.len > 0) {
        const log = git.gitLogOneline(allocator, base_branch, 10) catch "";
        if (log.len > 0) {
            try out.writer().print("\n## Commits (since {s})\n{s}\n", .{ base_branch, log });
        }
    }

    return out.toOwnedSlice();
}
