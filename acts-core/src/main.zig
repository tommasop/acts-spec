const std = @import("std");
const build_options = @import("build_options");

const stack = @import("stack.zig");
const git = @import("git.zig");
const context = @import("context.zig");
const verify = @import("verify.zig");

const version_str = build_options.version;

const usage_text =
    \\ACTS v2.0 — Git-native coordination protocol
    \\
    \\Usage: acts <command> [args]
    \\
    \\Stack lifecycle:
    \\  stack create <id> [-t <title>]          Start a new stack (base branch + manifest)
    \\  stack status                            Show stack and change status tree
    \\  stack land                              Merge approved changes bottom-up
    \\
    \\Change lifecycle:
    \\  change add <id> -t <title> [--accept <criteria>]
    \\                                          Add a change (branch) on top of the stack
    \\  change status [<id>]                    Show change details
    \\  verify [<id>] [--all]                   Run quality gates, record evidence
    \\  review <id>                             Submit stacked PR (requires verify to pass)
    \\  approve <id>                            Mark change approved (after human PR review)
    \\  rework <id>                             Reopen for rework (clears approval)
    \\
    \\Context continuity:
    \\  context [<id>]                          Emit scoped context pack for a change
    \\  note <id> -m <text>                     Append a session note
    \\  checkpoint <id> -s <summary>            Record a status checkpoint
    \\  redirect <id> --accept <criteria>       Update scope mid-flight without context loss
    \\
    \\Coordination:
    \\  scope <id> <file>                       Check file ownership (derived from diffs)
    \\  validate                                Validate manifest + branch consistency
    \\  version                                 Show version
    \\  help                                    Show this help
    \\
;

const Args = struct {
    allocator: std.mem.Allocator,
    positional: std.ArrayList([]const u8),
    flags: std.StringHashMap([]const u8),
    bool_flags: std.StringHashMap(void),

    fn init(allocator: std.mem.Allocator) Args {
        return .{
            .allocator = allocator,
            .positional = std.ArrayList([]const u8).init(allocator),
            .flags = std.StringHashMap([]const u8).init(allocator),
            .bool_flags = std.StringHashMap(void).init(allocator),
        };
    }

    fn deinit(self: *Args) void {
        self.positional.deinit();
        self.flags.deinit();
        self.bool_flags.deinit();
    }

    fn flag(self: *const Args, name: []const u8) ?[]const u8 {
        return self.flags.get(name);
    }

    fn has(self: *const Args, name: []const u8) bool {
        return self.bool_flags.contains(name);
    }
};

fn parseArgs(allocator: std.mem.Allocator, argv: []const []const u8) !Args {
    var args = Args.init(allocator);
    errdefer args.deinit();

    const long_value_flags = [_][]const u8{ "--title", "--accept", "--message", "-t", "-m" };
    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];
        if (a.len > 0 and a[0] == '-') {
            var is_value = false;
            for (long_value_flags) |f| {
                if (std.mem.eql(u8, a, f)) {
                    is_value = true;
                    break;
                }
            }
            if (is_value) {
                if (i + 1 < argv.len) {
                    try args.flags.put(a, argv[i + 1]);
                    i += 1;
                } else {
                    try args.flags.put(a, "");
                }
            } else if (std.mem.eql(u8, a, "--all") or std.mem.eql(u8, a, "--json")) {
                try args.bool_flags.put(a, {});
            } else if (std.mem.eql(u8, a, "-s")) {
                if (i + 1 < argv.len) {
                    try args.flags.put("-s", argv[i + 1]);
                    i += 1;
                }
            } else {
                // unknown flag, ignore
            }
        } else {
            try args.positional.append(a);
        }
    }
    return args;
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    if (argv.len < 2) {
        try stdout("{s}", .{usage_text});
        std.process.exit(0);
    }

    const cmd = argv[1];
    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "-h")) {
        try stdout("{s}", .{usage_text});
        std.process.exit(0);
    }
    if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "--version")) {
        try stdout("acts {s}\n", .{version_str});
        std.process.exit(0);
    }

    var args = try parseArgs(allocator, argv[2..]);
    defer args.deinit();

    const run_result = runCommand(allocator, cmd, &args);
    run_result catch |err| {
        try stderr("acts: error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

fn runCommand(allocator: std.mem.Allocator, cmd: []const u8, args: *const Args) !void {
    if (std.mem.eql(u8, cmd, "stack")) {
        if (args.positional.items.len < 1) return error.MissingSubcommand;
        const sub = args.positional.items[0];
        if (std.mem.eql(u8, sub, "create")) {
            if (args.positional.items.len < 2) return error.MissingStackId;
            return cmdStackCreate(allocator, args.positional.items[1], args);
        } else if (std.mem.eql(u8, sub, "status")) {
            return cmdStackStatus(allocator, args);
        } else if (std.mem.eql(u8, sub, "land")) {
            return cmdStackLand(allocator);
        }
        return error.UnknownSubcommand;
    }
    if (std.mem.eql(u8, cmd, "change")) {
        if (args.positional.items.len < 1) return error.MissingSubcommand;
        const sub = args.positional.items[0];
        if (std.mem.eql(u8, sub, "add")) {
            if (args.positional.items.len < 2) return error.MissingChangeId;
            return cmdChangeAdd(allocator, args.positional.items[1], args);
        } else if (std.mem.eql(u8, sub, "status")) {
            const id = if (args.positional.items.len >= 2) args.positional.items[1] else null;
            return cmdChangeStatus(allocator, id);
        }
        return error.UnknownSubcommand;
    }
    if (std.mem.eql(u8, cmd, "verify")) {
        const id = if (args.positional.items.len >= 1) args.positional.items[0] else null;
        return cmdVerify(allocator, id, args.has("--all"));
    }
    if (std.mem.eql(u8, cmd, "review")) {
        if (args.positional.items.len < 1) return error.MissingChangeId;
        return cmdReview(allocator, args.positional.items[0]);
    }
    if (std.mem.eql(u8, cmd, "approve")) {
        if (args.positional.items.len < 1) return error.MissingChangeId;
        return cmdApprove(allocator, args.positional.items[0]);
    }
    if (std.mem.eql(u8, cmd, "rework")) {
        if (args.positional.items.len < 1) return error.MissingChangeId;
        return cmdRework(allocator, args.positional.items[0]);
    }
    if (std.mem.eql(u8, cmd, "context")) {
        const id = if (args.positional.items.len >= 1) args.positional.items[0] else null;
        return cmdContext(allocator, id);
    }
    if (std.mem.eql(u8, cmd, "note")) {
        if (args.positional.items.len < 1) return error.MissingChangeId;
        const msg = args.flag("-m") orelse return error.MissingMessage;
        return cmdNote(allocator, args.positional.items[0], msg);
    }
    if (std.mem.eql(u8, cmd, "checkpoint")) {
        if (args.positional.items.len < 1) return error.MissingChangeId;
        const summary = args.flag("-s") orelse return error.MissingSummary;
        return cmdCheckpoint(allocator, args.positional.items[0], summary);
    }
    if (std.mem.eql(u8, cmd, "redirect")) {
        if (args.positional.items.len < 1) return error.MissingChangeId;
        const accept = args.flag("--accept") orelse return error.MissingAcceptance;
        return cmdRedirect(allocator, args.positional.items[0], accept);
    }
    if (std.mem.eql(u8, cmd, "scope")) {
        if (args.positional.items.len < 2) return error.MissingScopeArgs;
        return cmdScope(allocator, args.positional.items[0], args.positional.items[1]);
    }
    if (std.mem.eql(u8, cmd, "validate")) {
        return cmdValidate(allocator);
    }
    return error.UnknownCommand;
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

fn cmdStackCreate(allocator: std.mem.Allocator, id: []const u8, args: *const Args) !void {
    if (!git.isGitRepo(allocator)) return error.NotGitRepo;
    if (!validId(id)) return error.InvalidStackId;
    if (stack.manifestExists()) return error.StackAlreadyExists;

    const title = args.flag("--title") orelse args.flag("-t") orelse id;
    const base_branch = try std.fmt.allocPrint(allocator, "acts/{s}/base", .{id});

    // Create the base branch from current HEAD
    const res = try git.createBranch(allocator, base_branch, "");
    if (res.exit_code != 0) {
        try stderr("git: {s}\n", .{std.mem.trim(u8, res.stderr, " \n\r")});
        return error.BranchConflict;
    }

    var root = std.json.ObjectMap.init(allocator);
    try root.put("version", .{ .integer = 2 });
    try root.put("id", .{ .string = id });
    try root.put("title", .{ .string = title });
    try root.put("base_branch", .{ .string = base_branch });
    try root.put("changes", .{ .array = std.json.Array.init(allocator) });

    try stack.save(allocator, .{ .object = root });

    try stdout("stack {s} created on branch {s}\n", .{ id, base_branch });
    try stdout("  next: acts change add c1 -t \"<title>\" --accept \"<criteria>\"\n", .{});
}

fn cmdStackStatus(allocator: std.mem.Allocator, args: *const Args) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    const root = &v.object;
    const sid = if (root.get("id")) |s| if (s == .string) s.string else "" else "";
    const stitle = if (root.get("title")) |s| if (s == .string) s.string else "" else "";
    const base = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";

    try stdout("Stack: {s} — {s} (base: {s})\n", .{ sid, stitle, base });

    const changes = root.get("changes") orelse return;
    if (changes != .array) return;
    var idx: usize = 0;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const m = &c.*.object;
        const cid = if (m.get("id")) |s| if (s == .string) s.string else "" else "";
        const ctitle = if (m.get("title")) |s| if (s == .string) s.string else "" else "";
        const cstatus = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
        const marker: []const u8 = if (cstatus.len == 0) "  " else cstatus;
        try stdout("  {s} {s}  {s}\n", .{ if (idx == 0) "└" else "├", marker, ctitle });
        _ = cid;
        idx += 1;
    }
    if (args.has("--json")) {
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();
        try std.json.stringify(v, .{ .whitespace = .indent_2 }, buf.writer());
        try stdout("{s}\n", .{buf.items});
    }
}

fn cmdStackLand(allocator: std.mem.Allocator) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;
    const root = &v.object;

    const base = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";
    if (base.len == 0) return error.ManifestInvalid;

    const changes = root.get("changes") orelse return error.ManifestInvalid;
    if (changes != .array) return error.ManifestInvalid;

    var landed_any = false;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const m = &c.*.object;
        const cid = if (m.get("id")) |s| if (s == .string) s.string else "" else "";
        const cstatus = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
        const cbranch = if (m.get("branch")) |s| if (s == .string) s.string else "" else "";

        if (std.mem.eql(u8, cstatus, stack.status_merged)) continue;
        if (!std.mem.eql(u8, cstatus, stack.status_approved)) {
            try stdout("skip {s}: status is {s} (need APPROVED)\n", .{ cid, cstatus });
            continue;
        }
        // Merge the change branch into the base branch
        _ = try git.checkoutBranch(allocator, base);
        const mr = try git.run(allocator, &.{ "git", "merge", "--no-ff", cbranch, "-m", try std.fmt.allocPrint(allocator, "acts: land {s}", .{cid}) }, 8192);
        if (mr.exit_code != 0) {
            try stderr("merge failed for {s}: {s}\n", .{ cid, std.mem.trim(u8, mr.stderr, " \n\r") });
            return error.MergeFailed;
        }
        _ = try stack.setChangeString(v, cid, "status", stack.status_merged);
        try stdout("landed {s}\n", .{cid});
        landed_any = true;
    }
    if (landed_any) {
        try stack.save(allocator, v);
    } else {
        try stdout("nothing to land (no APPROVED changes)\n", .{});
    }
}

fn cmdChangeAdd(allocator: std.mem.Allocator, id: []const u8, args: *const Args) !void {
    if (!validId(id)) return error.InvalidChangeId;
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) != null) return error.ChangeExists;

    const title = args.flag("--title") orelse args.flag("-t") orelse return error.MissingTitle;
    const root = &v.object;
    const sid = if (root.get("id")) |s| if (s == .string) s.string else "" else "";
    const base = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";

    // Determine parent: current top of stack (or base if none)
    const parent = stack.topChange(v);
    const parent_branch = if (parent) |p| blk: {
        const pm = stack.getChange(v, p) orelse break :blk base;
        if (pm.get("branch")) |b| if (b == .string) break :blk b.string;
        break :blk base;
    } else base;

    const changes = root.get("changes").?.array.items.len;
    const slug = try slugify(allocator, title);
    const branch = try std.fmt.allocPrint(allocator, "acts/{s}/c{d}-{s}", .{ sid, changes + 1, slug });

    const res = try git.createBranch(allocator, branch, parent_branch);
    if (res.exit_code != 0) {
        try stderr("git: {s}\n", .{std.mem.trim(u8, res.stderr, " \n\r")});
        return error.BranchConflict;
    }

    // Build the change entry
    var entry = std.json.ObjectMap.init(allocator);
    try entry.put("id", .{ .string = id });
    try entry.put("title", .{ .string = title });
    try entry.put("branch", .{ .string = branch });
    if (parent) |p| {
        try entry.put("parent", .{ .string = p });
    } else {
        try entry.put("parent", .null);
    }
    try entry.put("status", .{ .string = stack.status_todo });

    // Acceptance criteria (split on newlines if --accept given)
    var acceptance = std.json.Array.init(allocator);
    if (args.flag("--accept")) |accept_raw| {
        try appendAcceptance(allocator, &acceptance, accept_raw);
    }
    try entry.put("acceptance", .{ .array = acceptance });
    try entry.put("verify", .{ .object = std.json.ObjectMap.init(allocator) });
    try entry.put("notes", .{ .array = std.json.Array.init(allocator) });
    try entry.put("checkpoint", .null);

    var pr = std.json.ObjectMap.init(allocator);
    try pr.put("url", .null);
    try pr.put("approved", .{ .bool = false });
    try entry.put("pr", .{ .object = pr });

    const changes_arr = root.getPtr("changes").?;
    try changes_arr.array.append(.{ .object = entry });

    try stack.save(allocator, v);
    try stdout("change {s} added on branch {s} (parent: {s})\n", .{ id, branch, if (parent) |p| p else base });
}

fn cmdChangeStatus(allocator: std.mem.Allocator, id_arg: ?[]const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    const id = id_arg orelse (resolveCurrentChange(allocator, v) orelse return error.NoActiveChange);
    const m = stack.getChange(v, id) orelse return error.ChangeNotFound;

    const ctitle = if (m.get("title")) |s| if (s == .string) s.string else "" else "";
    const cstatus = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
    const cbranch = if (m.get("branch")) |s| if (s == .string) s.string else "" else "";
    const parent = stack.parentOf(v, id) orelse "";

    try stdout("Change: {s} — {s}\n", .{ id, ctitle });
    try stdout("  status: {s}\n", .{cstatus});
    try stdout("  branch: {s}\n", .{cbranch});
    try stdout("  parent: {s}\n", .{parent});
    if (m.get("acceptance")) |acc| {
        if (acc == .array) {
            try stdout("  acceptance:\n", .{});
            for (acc.array.items) |item| {
                if (item == .string) try stdout("    - {s}\n", .{item.string});
            }
        }
    }
    if (stack.getCheckpoint(v, id)) |cp| {
        try stdout("  checkpoint: {s}\n", .{cp});
    }
    const verified = stack.verifyAllPassed(v, id);
    try stdout("  verified: {s}\n", .{if (verified) "yes" else "no"});
    if (m.get("pr")) |pr| {
        if (pr == .object) {
            if (pr.object.get("url")) |u| {
                if (u == .string and u.string.len > 0) try stdout("  pr: {s}\n", .{u.string});
            }
        }
    }
}

fn cmdVerify(allocator: std.mem.Allocator, id_arg: ?[]const u8, all: bool) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;
    const root = &v.object;
    const base = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";

    if (all) {
        var total_pass = true;
        const changes = root.get("changes") orelse return;
        if (changes != .array) return;
        for (changes.array.items) |*c| {
            if (c.* != .object) continue;
            const m = &c.*.object;
            const cid = if (m.get("id")) |s| if (s == .string) s.string else "" else "";
            const cstatus = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
            if (std.mem.eql(u8, cstatus, stack.status_merged)) continue;
            const ok = try runVerifyForChange(allocator, v, cid, base);
            if (!ok) total_pass = false;
        }
        try stack.save(allocator, v);
        if (!total_pass) return error.VerifyFailed;
        try stdout("all changes verified\n", .{});
        return;
    }

    const id = id_arg orelse (resolveCurrentChange(allocator, v) orelse return error.NoActiveChange);
    if (stack.getChange(v, id) == null) return error.ChangeNotFound;

    const ok = try runVerifyForChange(allocator, v, id, base);
    try stack.save(allocator, v);
    if (!ok) return error.VerifyFailed;
    try stdout("change {s} verified\n", .{id});
}

fn runVerifyForChange(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, base: []const u8) !bool {
    // Check out the change branch so tests run against its code
    const m = stack.getChange(v, id).?;
    const branch = if (m.get("branch")) |b| if (b == .string) b.string else "" else "";
    if (branch.len > 0) {
        _ = try git.checkoutBranch(allocator, branch);
    }
    _ = base;

    const results = try verify.runAllQualityGates(allocator);
    defer verify.freeQualityResults(allocator, results);

    var all_ok = true;
    for (results) |r| {
        const stage_name = switch (r.stage) {
            .Test => "test",
            .Lint => "lint",
            .Typecheck => "typecheck",
            .Build => "build",
        };
        const ok = r.status == .pass or r.status == .skipped;
        if (!ok) all_ok = false;
        _ = try stack.recordVerify(allocator, v, id, stage_name, r.command, ok, r.exit_code, r.duration_ms);
        try stdout("  {s}: {s} ({s}) [{d}ms]\n", .{ stage_name, if (ok) "PASS" else "FAIL", r.command, r.duration_ms });
        if (!ok and r.output.len > 0) {
            const trimmed = std.mem.trim(u8, r.output, " \n\r");
            if (trimmed.len > 400) {
                try stdout("      {s}\n", .{trimmed[0..400]});
            } else if (trimmed.len > 0) {
                try stdout("      {s}\n", .{trimmed});
            }
        }
    }

    const new_status: []const u8 = if (all_ok) stack.status_verified else stack.status_in_progress;
    _ = try stack.setChangeString(v, id, "status", new_status);
    return all_ok;
}

fn cmdReview(allocator: std.mem.Allocator, id: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    const m = stack.getChange(v, id) orelse return error.ChangeNotFound;
    if (!stack.verifyAllPassed(v, id)) return error.VerifyRequired;

    const branch = if (m.get("branch")) |b| if (b == .string) b.string else "" else "";
    const ctitle = if (m.get("title")) |s| if (s == .string) s.string else "" else "";
    const root = &v.object;
    const base = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";

    // Build PR body from the context pack
    const body = try context.buildContextPack(allocator, v, id);

    const tools = git.detectTools(allocator);
    var pr_url: ?[]const u8 = null;

    if (tools.gh) {
        const head = branch;
        const res = try git.run(allocator, &.{
            "gh",
            "pr",
            "create",
            "--head",
            head,
            "--base",
            base,
            "--title",
            try std.fmt.allocPrint(allocator, "{s}: {s}", .{ id, ctitle }),
            "--body",
            body,
        }, 16384);
        if (res.exit_code == 0) {
            const trimmed = std.mem.trim(u8, res.stdout, " \n\r");
            if (trimmed.len > 0) pr_url = trimmed;
        } else {
            try stderr("gh pr create: {s}\n", .{std.mem.trim(u8, res.stderr, " \n\r")});
        }
    } else {
        try stdout("note: gh CLI not found — PR not submitted. Push branch {s} manually.\n", .{branch});
    }

    if (pr_url) |url| {
        _ = try stack.setPrUrl(allocator, v, id, url);
        try stdout("PR submitted: {s}\n", .{url});
    }
    _ = try stack.setChangeString(v, id, "status", stack.status_in_review);
    try stack.save(allocator, v);
}

fn cmdApprove(allocator: std.mem.Allocator, id: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) == null) return error.ChangeNotFound;
    _ = try stack.setPrApproved(allocator, v, id, true);
    _ = try stack.setChangeString(v, id, "status", stack.status_approved);
    try stack.save(allocator, v);
    try stdout("change {s} approved\n", .{id});
}

fn cmdRework(allocator: std.mem.Allocator, id: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) == null) return error.ChangeNotFound;
    _ = try stack.setPrApproved(allocator, v, id, false);
    _ = try stack.setChangeString(v, id, "status", stack.status_in_progress);
    try stack.save(allocator, v);
    try stdout("change {s} reopened for rework\n", .{id});
}

fn cmdContext(allocator: std.mem.Allocator, id_arg: ?[]const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    const id = id_arg orelse (resolveCurrentChange(allocator, v) orelse return error.NoActiveChange);
    const pack = try context.buildContextPack(allocator, v, id);
    try stdout("{s}\n", .{pack});
}

fn cmdNote(allocator: std.mem.Allocator, id: []const u8, msg: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) == null) return error.ChangeNotFound;

    // Write the note to .acts/changes/<id>/notes/<ts>.md
    const ts = std.time.timestamp();
    const dir = try std.fmt.allocPrint(allocator, ".acts/changes/{s}/notes", .{id});
    std.fs.cwd().makePath(dir) catch {};
    const fname = try std.fmt.allocPrint(allocator, "{s}/{d}.md", .{ dir, ts });
    var content = std.ArrayList(u8).init(allocator);
    try content.writer().print("# Session note ({d})\n\n{s}\n", .{ ts, msg });
    try std.fs.cwd().writeFile(.{ .sub_path = fname, .data = content.items });

    _ = try stack.appendNote(allocator, v, id, fname);
    try stack.save(allocator, v);
    try stdout("note appended to {s}: {s}\n", .{ id, fname });
}

fn cmdCheckpoint(allocator: std.mem.Allocator, id: []const u8, summary: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) == null) return error.ChangeNotFound;
    _ = try stack.setCheckpoint(v, id, summary);
    try stack.save(allocator, v);
    try stdout("checkpoint recorded for {s}\n", .{id});
}

fn cmdRedirect(allocator: std.mem.Allocator, id: []const u8, accept: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    const m = stack.getChange(v, id) orelse return error.ChangeNotFound;
    var acceptance = std.json.Array.init(allocator);
    try appendAcceptance(allocator, &acceptance, accept);
    try m.put("acceptance", .{ .array = acceptance });
    _ = try stack.setChangeString(v, id, "status", stack.status_in_progress);
    try stack.save(allocator, v);
    try stdout("change {s} redirected with updated scope (status -> IN_PROGRESS)\n", .{id});
}

fn cmdScope(allocator: std.mem.Allocator, id: []const u8, file: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    const m = stack.getChange(v, id) orelse return error.ChangeNotFound;
    const branch = if (m.get("branch")) |b| if (b == .string) b.string else "" else "";
    const root = &v.object;
    const base = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";

    const cur_branch = (try git.currentBranch(allocator)) orelse "";
    if (!std.mem.eql(u8, cur_branch, branch)) {
        _ = try git.checkoutBranch(allocator, branch);
    }

    const files = try git.changedFilesSince(allocator, base);
    for (files) |f| {
        if (std.mem.eql(u8, f, file)) {
            try stdout("{{\n  \"file_path\": \"{s}\",\n  \"action\": \"ok\",\n  \"message\": \"File is part of change {s}'s diff\"\n}}\n", .{ file, id });
            return;
        }
    }
    try stdout("{{\n  \"file_path\": \"{s}\",\n  \"action\": \"warn\",\n  \"message\": \"File not in change {s}'s diff — verify it belongs to this task before editing\"\n}}\n", .{ file, id });
}

fn cmdValidate(allocator: std.mem.Allocator) !void {
    if (!stack.manifestExists()) {
        try stdout("no active stack (missing {s})\n", .{stack.manifest_path});
        return;
    }
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    const problems = try stack.validate(allocator, v);
    const trimmed = std.mem.trim(u8, problems, " \n\r");
    if (trimmed.len == 0) {
        try stdout("manifest OK\n", .{});
    } else {
        try stdout("manifest problems:\n{s}\n", .{problems});
        return error.ValidationFailed;
    }

    // Branch consistency
    const root = &v.object;
    const base = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";
    if (!git.branchExists(allocator, base)) {
        try stdout("warn: base branch {s} does not exist\n", .{base});
    }
    if (root.get("changes")) |changes| {
        if (changes == .array) {
            for (changes.array.items) |*c| {
                if (c.* != .object) continue;
                const m = &c.*.object;
                const cid = if (m.get("id")) |s| if (s == .string) s.string else "" else "";
                const cbranch = if (m.get("branch")) |s| if (s == .string) s.string else "" else "";
                if (!git.branchExists(allocator, cbranch)) {
                    try stdout("warn: change {s} branch {s} does not exist\n", .{ cid, cbranch });
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn validId(id: []const u8) bool {
    if (id.len == 0) return false;
    for (id) |ch| {
        const ok = std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_';
        if (!ok) return false;
    }
    return true;
}

/// Split acceptance criteria on newlines (real or literal `\n`) and append to an array.
fn appendAcceptance(allocator: std.mem.Allocator, arr: *std.json.Array, raw: []const u8) !void {
    // Normalize literal `\n` (backslash-n) to real newline so CLI users can pass one string.
    var normalized = std.ArrayList(u8).init(allocator);
    var i: usize = 0;
    while (i < raw.len) {
        if (i + 1 < raw.len and raw[i] == '\\' and raw[i + 1] == 'n') {
            try normalized.append('\n');
            i += 2;
        } else {
            try normalized.append(raw[i]);
            i += 1;
        }
    }
    var it = std.mem.splitScalar(u8, normalized.items, '\n');
    while (it.next()) |line| {
        const t = std.mem.trim(u8, line, " \t\r");
        if (t.len > 0) try arr.append(.{ .string = t });
    }
}

fn slugify(allocator: std.mem.Allocator, title: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    var prev_dash = false;
    for (title) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            try out.append(std.ascii.toLower(ch));
            prev_dash = false;
        } else if (ch == ' ' or ch == '-' or ch == '_' or ch == '/') {
            if (!prev_dash and out.items.len > 0) {
                try out.append('-');
                prev_dash = true;
            }
        }
    }
    // strip trailing dash
    if (out.items.len > 0 and out.items[out.items.len - 1] == '-') {
        _ = out.pop();
    }
    if (out.items.len == 0) try out.append('x');
    return out.toOwnedSlice();
}

/// Resolve the active change id from the currently checked-out git branch.
fn resolveCurrentChange(allocator: std.mem.Allocator, v: std.json.Value) ?[]const u8 {
    const branch = git.currentBranch(allocator) catch null orelse return null;
    const root = &v.object;
    const changes = root.get("changes") orelse return null;
    if (changes != .array) return null;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const m = &c.*.object;
        if (m.get("branch")) |b| {
            if (b == .string and std.mem.eql(u8, b.string, branch)) {
                if (m.get("id")) |idv| {
                    if (idv == .string) return idv.string;
                }
            }
        }
    }
    return null;
}

fn stdout(comptime fmt: []const u8, args: anytype) !void {
    try std.io.getStdOut().writer().print(fmt, args);
}

fn stderr(comptime fmt: []const u8, args: anytype) !void {
    try std.io.getStdErr().writer().print(fmt, args);
}

test "validId rejects spaces and empty" {
    try std.testing.expect(validId("c1"));
    try std.testing.expect(validId("auth-flow"));
    try std.testing.expect(!validId(""));
    try std.testing.expect(!validId("has space"));
    try std.testing.expect(!validId("has/slash"));
}

test "slugify basic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const s1 = try slugify(a, "JWT middleware");
    try std.testing.expectEqualStrings("jwt-middleware", s1);

    const s2 = try slugify(a, "Add user auth!");
    try std.testing.expectEqualStrings("add-user-auth", s2);

    const s3 = try slugify(a, "---");
    try std.testing.expectEqualStrings("x", s3);
}

test "manifest roundtrip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var root = std.json.ObjectMap.init(a);
    try root.put("version", .{ .integer = 2 });
    try root.put("id", .{ .string = "auth" });
    try root.put("title", .{ .string = "Auth" });
    try root.put("base_branch", .{ .string = "acts/auth/base" });

    var changes = std.json.Array.init(a);
    var entry = std.json.ObjectMap.init(a);
    try entry.put("id", .{ .string = "c1" });
    try entry.put("title", .{ .string = "JWT" });
    try entry.put("status", .{ .string = stack.status_todo });
    try entry.put("branch", .{ .string = "acts/auth/c1-jwt" });
    try entry.put("parent", .null);
    try changes.append(.{ .object = entry });
    try root.put("changes", .{ .array = changes });

    const v: std.json.Value = .{ .object = root };
    const problems = try stack.validate(a, v);
    try std.testing.expectEqualStrings("", std.mem.trim(u8, problems, " \n\r"));

    // verify record roundtrip
    _ = try stack.recordVerify(a, v, "c1", "test", "npm test", true, 0, 12);
    try std.testing.expect(stack.verifyAllPassed(v, "c1"));

    // parent chain
    try std.testing.expect(stack.parentOf(v, "c1") == null);
    try std.testing.expectEqualStrings("c1", stack.topChange(v).?);
}

test "manifest validates missing title" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var root = std.json.ObjectMap.init(a);
    try root.put("version", .{ .integer = 2 });
    try root.put("id", .{ .string = "auth" });
    try root.put("base_branch", .{ .string = "acts/auth/base" });
    try root.put("changes", .{ .array = std.json.Array.init(a) });

    const v: std.json.Value = .{ .object = root };
    const problems = try stack.validate(a, v);
    try std.testing.expect(std.mem.indexOf(u8, problems, "missing 'title'") != null);
}
