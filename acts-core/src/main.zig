const std = @import("std");
const build_options = @import("build_options");

const stack = @import("stack.zig");
const git = @import("git.zig");
const context = @import("context.zig");
const verify = @import("verify.zig");
const risk = @import("risk.zig");
const setup = @import("setup.zig");
const cbm = @import("cbm.zig");
const graph = @import("graph.zig");
const archify = @import("archify.zig");
const diagram = @import("diagram.zig");
const docrisk = @import("docrisk.zig");

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
    \\  verify [<id>] [--all] [--force -m <reason> | --manual <evidence>]
    \\                                          Run quality gates, record evidence
    \\                                          --force: override when failures are
    \\                                            outside this change (refused if a
    \\                                            change-owned file fails)
    \\                                          --manual: skip gates, record evidence
    \\  review <id>                             Submit stacked PR (requires verify to pass)
    \\  approve <id>                            Mark change approved (after human PR review)
    \\  rework <id>                             Reopen for rework (clears approval)
    \\  risk <id>                               Compute + show the change's risk tier
    \\
    \\Context continuity:
    \\  context [<id>]                          Emit scoped context pack for a change
    \\  note <id> -m <text>                     Append a session note
    \\  checkpoint <id> -s <summary>            Record a status checkpoint
    \\  redirect <id> --accept <criteria>       Update scope mid-flight without context loss
    \\
    \\Coordination:
    \\  scope <id> <file>                       Check file ownership (derived from diffs)
    \\  tech-lead <id>                          Pre-flight risk report (CBM graph)
    \\  doc-risk <file> [--json]                Evaluate a spec/plan doc (static + CBM)
    \\  graph repos|index|bootstrap|span        CBM fleet helpers (replaces cbm plugin)
    \\  diagram <id> [--delta] [--attach]       Render change architecture impact via
    \\                                          archify (HTML; --delta = Before/Delta/
    \\                                          After, --attach = comment on the PR)
    \\  archify install                         Install the archify renderer skill
    \\  validate                                Validate manifest + branch consistency
    \\  setup [dir] [--source <acts-spec>] [--github] [--force] [--bin-dir <dir>]
    \\                                          Install binaries globally + wire a project
    \\  migrate [<story-id>]                    Import a v1 SQLite story into a v2 stack
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

    const long_value_flags = [_][]const u8{ "--title", "--accept", "--message", "--cost", "--source", "--bin-dir", "--manual", "--reason", "--type", "-t", "-m" };
    const bool_flags = [_][]const u8{ "--all", "--json", "--github", "--force", "--no-install", "--delta", "--attach", "--with-archify" };
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
            } else {
                var is_bool = false;
                for (bool_flags) |f| {
                    if (std.mem.eql(u8, a, f)) {
                        try args.bool_flags.put(a, {});
                        is_bool = true;
                        break;
                    }
                }
                if (is_bool) continue;
                if (std.mem.eql(u8, a, "-s")) {
                    if (i + 1 < argv.len) {
                        try args.flags.put("-s", argv[i + 1]);
                        i += 1;
                    }
                } else {
                    // unknown flag, ignore
                }
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
        if (err == error.UnknownCommand) {
            if (v1Hint(cmd)) |hint| {
                try stderr("acts: error: UnknownCommand\n", .{});
                try stderr("note: `{s}` is an ACTS v1 command that was removed in v2. {s}\n", .{ cmd, hint });
                std.process.exit(1);
            }
        }
        try stderr("acts: error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

/// Map removed ACTS v1 commands to their v2 equivalents so users get a helpful
/// pointer instead of a bare "UnknownCommand".
fn v1Hint(cmd: []const u8) ?[]const u8 {
    const hints = [_]struct { cmd: []const u8, hint: []const u8 }{
        .{ .cmd = "state", .hint = "Try `acts stack status` (or `acts stack status --json`)." },
        .{ .cmd = "task", .hint = "v2 has no tasks — use `acts change add <id>` and `acts change status`." },
        .{ .cmd = "gate", .hint = "Gates were replaced by verification: run `acts verify <id>`." },
        .{ .cmd = "init", .hint = "Start a stack instead: `acts stack create <id> -t \"<title>\"`." },
        .{ .cmd = "story", .hint = "Stories became stacks: `acts stack create <id>` / `acts stack land`." },
        .{ .cmd = "ownership", .hint = "Ownership is derived from diffs: `acts scope <id> <file>`." },
        .{ .cmd = "override", .hint = "File overrides were removed — ownership is git-derived." },
        .{ .cmd = "reject", .hint = "Use `acts rework <id>` to reopen a change for rework." },
        .{ .cmd = "session", .hint = "Session summaries moved to `acts note <id> -m \"...\"`." },
        .{ .cmd = "changelog", .hint = "Removed in v2." },
        .{ .cmd = "presence", .hint = "Removed in v2." },
        .{ .cmd = "unblock", .hint = "Removed in v2 — dependencies are handled by the stack." },
        .{ .cmd = "db", .hint = "Removed in v2 — there is no sidecar database." },
    };
    for (hints) |h| {
        if (std.mem.eql(u8, cmd, h.cmd)) return h.hint;
    }
    return null;
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
        const force = args.has("--force");
        const manual = args.flag("--manual") orelse null;
        const reason = args.flag("-m") orelse args.flag("--reason") orelse null;
        if (force and reason == null) return error.MissingReason;
        return cmdVerify(allocator, id, args.has("--all"), force, manual, reason);
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
    if (std.mem.eql(u8, cmd, "risk")) {
        if (args.positional.items.len < 1) return error.MissingChangeId;
        return cmdRisk(allocator, args.positional.items[0]);
    }
    if (std.mem.eql(u8, cmd, "tech-lead")) {
        if (args.positional.items.len < 1) return error.MissingChangeId;
        const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch ".";
        return graph.cmdTechLead(allocator, cwd, args.positional.items[0]);
    }
    if (std.mem.eql(u8, cmd, "doc-risk")) {
        if (args.positional.items.len < 1) return error.MissingFile;
        const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch ".";
        return cmdDocRisk(allocator, cwd, args.positional.items[0], args.has("--json"));
    }
    if (std.mem.eql(u8, cmd, "graph")) {
        if (args.positional.items.len < 1) return error.MissingSubcommand;
        const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch ".";
        const sub = args.positional.items[0];
        if (std.mem.eql(u8, sub, "repos")) {
            return graph.cmdRepos(allocator, cwd, args.has("--json"));
        } else if (std.mem.eql(u8, sub, "index")) {
            return graph.cmdIndexAll(allocator, cwd);
        } else if (std.mem.eql(u8, sub, "bootstrap")) {
            return graph.cmdBootstrap(allocator, cwd);
        } else if (std.mem.eql(u8, sub, "span")) {
            if (args.positional.items.len < 2) return error.MissingChangeId;
            return graph.cmdSpan(allocator, cwd, args.positional.items[1]);
        }
        return error.UnknownSubcommand;
    }
    if (std.mem.eql(u8, cmd, "diagram")) {
        if (args.positional.items.len < 1) return error.MissingChangeId;
        const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch ".";
        const diag_type = args.flag("--type") orelse "architecture";
        if (!std.mem.eql(u8, diag_type, "architecture")) {
            try stderr("diagram: only --type architecture is supported in this version.\n", .{});
            return error.UnsupportedDiagramType;
        }
        _ = try diagram.cmdDiagram(allocator, cwd, args.positional.items[0], args.has("--delta"));
        if (args.has("--attach")) {
            return diagram.attachToPr(allocator, cwd, args.positional.items[0], true);
        }
        return;
    }
    if (std.mem.eql(u8, cmd, "archify")) {
        if (args.positional.items.len < 1) return error.MissingSubcommand;
        const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch ".";
        if (std.mem.eql(u8, args.positional.items[0], "install")) {
            return diagram.cmdArchifyInstall(allocator, cwd);
        }
        return error.UnknownSubcommand;
    }
    if (std.mem.eql(u8, cmd, "context")) {
        const id = if (args.positional.items.len >= 1) args.positional.items[0] else null;
        return cmdContext(allocator, id);
    }
    if (std.mem.eql(u8, cmd, "note")) {
        if (args.positional.items.len < 1) return error.MissingChangeId;
        const msg = args.flag("-m") orelse return error.MissingMessage;
        return cmdNote(allocator, args.positional.items[0], msg, args);
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
    if (std.mem.eql(u8, cmd, "setup")) {
        return cmdSetup(allocator, args);
    }
    if (std.mem.eql(u8, cmd, "migrate")) {
        return cmdMigrate(allocator, args);
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
    // The integration branch is whatever we're on now (master/main).
    const integ = (try git.currentBranch(allocator)) orelse "master";
    const integ_sha = try git.refSha(allocator, integ);
    const feat = try std.fmt.allocPrint(allocator, "acts/{s}/feature", .{id});

    // Create the feature branch from current HEAD.
    const res = try git.createBranch(allocator, feat, "");
    if (res.exit_code != 0) {
        try stderr("git: {s}\n", .{std.mem.trim(u8, res.stderr, " \n\r")});
        return error.BranchConflict;
    }

    var root = std.json.ObjectMap.init(allocator);
    try root.put("version", .{ .integer = 3 });
    try root.put("id", .{ .string = id });
    try root.put("title", .{ .string = title });
    try root.put("branch", .{ .string = feat });
    try root.put("base_branch", .{ .string = integ });
    if (integ_sha.len > 0) try root.put("base_sha", .{ .string = integ_sha });
    var pr = std.json.ObjectMap.init(allocator);
    try pr.put("url", .null);
    try root.put("pr", .{ .object = pr });
    try root.put("changes", .{ .array = std.json.Array.init(allocator) });

    try stack.save(allocator, .{ .object = root });

    try stdout("stack {s} created on feature branch {s} (off {s})\n", .{ id, feat, integ });
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

        // Stale-verification guard: if the base branch moved since this change
        // was verified, require re-verification before landing.
        const verified_sha = stack.getVerifyBaseSha(v, cid);
        const cur_base_sha = try git.refSha(allocator, base);
        if (verified_sha != null and cur_base_sha.len > 0 and !std.mem.eql(u8, verified_sha.?, cur_base_sha)) {
            try stdout("skip {s}: base moved since verify — run `acts verify {s}` before landing\n", .{ cid, cid });
            continue;
        }

        // Commit any pending manifest/note changes on the change branch first, so
        // switching to the base branch isn't blocked by a dirty tracked `.acts/`.
        const cur = (try git.currentBranch(allocator)) orelse "";
        if (!std.mem.eql(u8, cur, cbranch)) {
            _ = try git.checkoutBranch(allocator, cbranch);
        }
        const status_res = try git.run(allocator, &.{ "git", "status", "--porcelain", "--", ".acts" }, 8192);
        if (status_res.exit_code == 0 and std.mem.trim(u8, status_res.stdout, " \n\r").len > 0) {
            _ = try git.run(allocator, &.{ "git", "add", ".acts" }, 8192);
            const cres = try git.gitCommit(allocator, try std.fmt.allocPrint(allocator, "chore(acts): record {s} state", .{cid}));
            if (cres.exit_code != 0) {
                try stderr("commit .acts failed for {s}: {s}\n", .{ cid, std.mem.trim(u8, cres.stderr, " \n\r") });
                return error.CommitFailed;
            }
        }

        // Merge the change branch into the base branch
        const co = try git.checkoutBranch(allocator, base);
        if (co.exit_code != 0) {
            try stderr("checkout {s} failed: {s}\n", .{ base, std.mem.trim(u8, co.stderr, " \n\r") });
            return error.CheckoutFailed;
        }
        const mr = try git.run(allocator, &.{ "git", "merge", "--no-ff", cbranch, "-m", try std.fmt.allocPrint(allocator, "acts: land {s}", .{cid}) }, 8192);
        if (mr.exit_code != 0) {
            try stderr("merge failed for {s}: {s}\n", .{ cid, std.mem.trim(u8, mr.stderr, " \n\r") });
            return error.MergeFailed;
        }
        try stdout("landed {s} onto {s}\n", .{ cid, base });
        landed_any = true;
    }

    // Update the manifest: mark landed changes MERGED. Note: we are on the base
    // branch now, so save the manifest there and commit it.
    if (landed_any) {
        for (changes.array.items) |*c| {
            if (c.* != .object) continue;
            const m = &c.*.object;
            const cid = if (m.get("id")) |s| if (s == .string) s.string else "" else "";
            const cstatus = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
            if (!std.mem.eql(u8, cstatus, stack.status_merged)) {
                _ = try stack.setChangeString(v, cid, "status", stack.status_merged);
            }
        }
        try stack.save(allocator, v);
        const status_res = try git.run(allocator, &.{ "git", "status", "--porcelain", "--", ".acts" }, 8192);
        if (status_res.exit_code == 0 and std.mem.trim(u8, status_res.stdout, " \n\r").len > 0) {
            _ = try git.run(allocator, &.{ "git", "add", ".acts" }, 8192);
            _ = try git.gitCommit(allocator, "chore(acts): mark landed changes MERGED");
        }
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
    _ = sid;
    const feat = stack.branchOf(v) orelse return error.ManifestInvalid;

    // Checkpoint at the current feature-branch HEAD — no new branch.
    const head = try git.headSha(allocator);

    var entry = std.json.ObjectMap.init(allocator);
    try entry.put("id", .{ .string = id });
    try entry.put("title", .{ .string = title });
    try entry.put("status", .{ .string = stack.status_todo });
    if (head.len > 0) try entry.put("start_sha", .{ .string = head });
    try entry.put("end_sha", .null);

    var acceptance = std.json.Array.init(allocator);
    if (args.flag("--accept")) |accept_raw| {
        try appendAcceptance(allocator, &acceptance, accept_raw);
    }
    try entry.put("acceptance", .{ .array = acceptance });
    try entry.put("verify", .{ .object = std.json.ObjectMap.init(allocator) });
    try entry.put("notes", .{ .array = std.json.Array.init(allocator) });
    try entry.put("checkpoint", .null);

    const changes_arr = root.getPtr("changes").?;
    try changes_arr.array.append(.{ .object = entry });

    try stack.save(allocator, v);
    try stdout("change {s} added (checkpoint {s}) on feature branch {s}\n", .{ id, if (head.len > 0) head[0..7] else "(no commits)", feat });
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
    if (stack.getRisk(v, id)) |tier| {
        try stdout("  risk: {s}\n", .{tier});
    }
    if (stack.getCost(v, id)) |cost| {
        try stdout("  cost: ${d:.2}\n", .{cost});
    }
    if (m.get("pr")) |pr| {
        if (pr == .object) {
            if (pr.object.get("url")) |u| {
                if (u == .string and u.string.len > 0) try stdout("  pr: {s}\n", .{u.string});
            }
        }
    }
}

fn cmdVerify(allocator: std.mem.Allocator, id_arg: ?[]const u8, all: bool, force: bool, manual: ?[]const u8, reason: ?[]const u8) !void {
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
            const ok = try runVerifyForChange(allocator, v, cid, base, force, manual, reason);
            if (!ok) total_pass = false;
        }
        try stack.save(allocator, v);
        if (!total_pass) return error.VerifyFailed;
        try stdout("all changes verified\n", .{});
        return;
    }

    const id = id_arg orelse (resolveCurrentChange(allocator, v) orelse return error.NoActiveChange);
    if (stack.getChange(v, id) == null) return error.ChangeNotFound;

    const ok = try runVerifyForChange(allocator, v, id, base, force, manual, reason);
    try stack.save(allocator, v);
    if (!ok) return error.VerifyFailed;
    try stdout("change {s} verified\n", .{id});
}

fn runVerifyForChange(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, base: []const u8, force: bool, manual: ?[]const u8, reason: ?[]const u8) !bool {
    // Check out the change branch so tests run against its code
    const m = stack.getChange(v, id).?;
    const branch = if (m.get("branch")) |b| if (b == .string) b.string else "" else "";
    if (branch.len > 0) {
        _ = try git.checkoutBranch(allocator, branch);
    }

    var all_ok = true;

    // ── Manual verification: skip gates entirely, record evidence ──
    if (manual) |evidence| {
        _ = try stack.setVerifyForced(allocator, v, id, "manual", evidence);
        _ = try stack.setChangeString(v, id, "status", stack.status_verified);
        const base_sha = try git.refSha(allocator, base);
        if (base_sha.len > 0) _ = try stack.setVerifyBaseSha(allocator, v, id, base_sha);
        const tier = try computeRiskForChange(allocator, v, id, branch, base);
        _ = try stack.setRisk(v, id, tier.label());
        try stdout("  manual verification recorded: {s}\n", .{evidence});
        try stdout("  risk: {s}\n", .{tier.label()});
        return true;
    }

    // ── Normal: run all quality gates ──
    const results = try verify.runAllQualityGates(allocator);
    defer verify.freeQualityResults(allocator, results);

    var failing_outputs = std.ArrayList(u8).init(allocator);
    defer failing_outputs.deinit();

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
            if (!ok) try failing_outputs.writer().writeAll(r.output);
        }
    }

    // ── Force override with enforcement ──
    // Force is only allowed when the failures are attributable to files OUTSIDE
    // this change's diff (e.g. pre-existing files owned by another change), or
    // when no file can be attributed (broken/wrong gate tooling). If a failing
    // file is owned by THIS change, force is refused — the code must be fixed.
    if (!all_ok and force) {
        const fail_owned = try failingFilesOwnedByChange(allocator, base, branch, failing_outputs.items);
        if (fail_owned) {
            try stderr("force denied: the failing gate output includes files this change owns.\n", .{});
            try stderr("  Fix the code or correct the gate config (`.acts/acts.json` quality_gate), then re-verify.\n", .{});
            _ = try stack.setChangeString(v, id, "status", stack.status_in_progress);
            return false;
        }
        _ = try stack.setVerifyForced(allocator, v, id, "force", reason orelse "failures outside this change");
        _ = try stack.setChangeString(v, id, "status", stack.status_verified);
        try stdout("  forced: yes — failures attributed outside this change. Reason: {s}\n", .{ reason orelse "" });
    } else {
        const new_status: []const u8 = if (all_ok) stack.status_verified else stack.status_in_progress;
        _ = try stack.setChangeString(v, id, "status", new_status);
    }

    // Record the base SHA verification ran against, so stale verification can
    // be detected later, and (re)compute the risk tier from the final diff.
    const base_sha = try git.refSha(allocator, base);
    if (base_sha.len > 0) {
        _ = try stack.setVerifyBaseSha(allocator, v, id, base_sha);
    }
    const tier = try computeRiskForChange(allocator, v, id, branch, base);
    _ = try stack.setRisk(v, id, tier.label());
    try stdout("  risk: {s}\n", .{tier.label()});

    return all_ok or (force and stack.isVerifyForced(v, id));
}

/// Return true if any failing file (path:line tokens in the gate output) is
/// owned by this change (i.e. present in `git diff --name-only base branch`).
fn failingFilesOwnedByChange(allocator: std.mem.Allocator, base: []const u8, branch: []const u8, output: []const u8) !bool {
    const owned = try git.diffNameOnly(allocator, base, branch);
    return failingFilesOwnedByChangeWithOwned(output, owned);
}

/// Core attribution check (pure, testable): does the failing output reference
/// any of the given owned files?
fn failingFilesOwnedByChangeWithOwned(output: []const u8, owned: []const []const u8) bool {
    if (output.len == 0) return false; // no files attributable → force allowed
    if (owned.len == 0) return false;

    // Extract candidate file paths from output: "path:line:col: message",
    // "path:line", or a bare path that matches a change-owned file.
    var it = std.mem.tokenizeAny(u8, output, " \t\n\r");
    while (it.next()) |tok| {
        // Strip trailing ":<digits>" suffixes (line[:col]) to recover the path.
        var path = tok;
        while (std.mem.lastIndexOfScalar(u8, path, ':')) |colon| {
            const suffix = path[colon + 1 ..];
            if (suffix.len == 0) break;
            const all_digits = for (suffix) |ch| {
                if (!std.ascii.isDigit(ch)) break false;
            } else true;
            if (!all_digits) break;
            path = path[0..colon];
        }
        for (owned) |f| {
            if (std.mem.eql(u8, path, f)) return true;
            // Also match if the failing path ends with the owned relative path.
            if (std.mem.endsWith(u8, path, f)) return true;
        }
    }
    return false;
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

    // Ensure we're on the change's branch so the PR reflects its code.
    const cur_branch = (try git.currentBranch(allocator)) orelse "";
    if (!std.mem.eql(u8, cur_branch, branch)) {
        _ = try git.checkoutBranch(allocator, branch);
    }

    // Compute risk tier early (used for the PR body and auto-land).
    const tier = try computeRiskForChange(allocator, v, id, branch, base);
    _ = try stack.setRisk(v, id, tier.label());

    // Push the branch (and, when using git-spice, the rest of the stack).
    var pr_submitted = false;
    const remote = git.defaultRemote(allocator) orelse blk: {
        try stdout("note: no git remote configured — cannot submit PR. Commit and push manually.\n", .{});
        break :blk "";
    };
    if (remote.len > 0) {
        const push_res = try git.pushBranch(allocator, remote, branch);
        if (push_res.exit_code != 0) {
            try stderr("git push: {s}\n", .{std.mem.trim(u8, push_res.stderr, " \n\r")});
            return error.PushFailed;
        }
        pr_submitted = true;
    }

    // Build PR body from the context pack, plus risk tier + escalation notes.
    var body_buf = std.ArrayList(u8).init(allocator);
    const pack = try context.buildContextPack(allocator, v, id);
    try body_buf.appendSlice(pack);
    try body_buf.writer().print("\n## Risk Tier: {s}\n", .{tier.label()});
    if (tier == .HIGH or tier == .CRITICAL) {
        try body_buf.appendSlice(
            "\n## ⚠️ Escalation Checklist (mandatory human review)\n" ++
            "- [ ] Deployment coordination across services\n" ++
            "- [ ] Backward compatibility verified for high-caller-count symbols\n" ++
            "- [ ] Rollback plan confirmed\n",
        );
    } else if (tier == .LOW) {
        try body_buf.appendSlice("\n> LOW risk — eligible for auto-land once CI passes.\n");
    }
    const body = body_buf.items;

    const tools = git.detectTools(allocator);
    var pr_url: ?[]const u8 = null;

    if (pr_submitted and tools.git_spice) {
        // git-spice handles the full stack of PRs bottom-up.
        const res = try git.run(allocator, &.{ "gs", "stack", "submit" }, 16384);
        if (res.exit_code == 0) {
            const trimmed = std.mem.trim(u8, res.stdout, " \n\r");
            if (trimmed.len > 0) {
                // Best-effort: surface any PR URL in gs output.
                var it = std.mem.tokenizeAny(u8, trimmed, " \n\r");
                while (it.next()) |tok| {
                    if (std.mem.indexOf(u8, tok, "github.com/") != null or std.mem.indexOf(u8, tok, "gitlab.com/") != null) {
                        pr_url = tok;
                        break;
                    }
                }
            }
            try stdout("{s}\n", .{trimmed});
        } else {
            try stderr("gs stack submit: {s}\n", .{std.mem.trim(u8, res.stderr, " \n\r")});
            try stdout("note: git-spice failed — falling back to gh pr create.\n", .{});
        }
    }

    if (pr_url == null and pr_submitted and tools.gh) {
        const res = try git.run(allocator, &.{
            "gh",
            "pr",
            "create",
            "--head",
            branch,
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
    } else if (pr_url == null and pr_submitted and !tools.gh and !tools.git_spice) {
        try stdout("note: neither gh nor gs CLI found — branch pushed to {s}; submit PR manually.\n", .{remote});
    }

    if (pr_url) |url| {
        _ = try stack.setPrUrl(allocator, v, id, url);
        try stdout("PR submitted: {s}\n", .{url});
    }
    _ = try stack.setChangeString(v, id, "status", stack.status_in_review);
    try stack.save(allocator, v);

    // Best-effort, non-blocking: attach an archify architecture-delta comment
    // to the submitted PR so reviewers see the change's architecture impact.
    if (pr_url != null) {
        const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch ".";
        diagram.attachToPr(allocator, cwd, id, true) catch |err| {
            try stderr("note: archify attach skipped ({s}) — review is not blocked.\n", .{@errorName(err)});
        };
    }

    // Risk-based HITL: LOW-risk verified changes are eligible for auto-land.
    // gated by .acts/acts.json `hilt.auto_land_low` (default true).
    if (tier == .LOW and autoLandLowEnabled(allocator)) {
        try stdout("LOW risk + verified — auto-landing.\n", .{});
        _ = try stack.appendApproval(allocator, v, id, "approve", "__auto__", "LOW", "auto-land: low risk, verified");
        _ = try stack.setPrApproved(allocator, v, id, true);
        _ = try stack.setChangeString(v, id, "status", stack.status_approved);
        try stack.save(allocator, v);
        try stdout("change {s} auto-approved (LOW risk)\n", .{id});
    }
}

/// Read `.acts/acts.json` `hilt.auto_land_low` (default true).
fn autoLandLowEnabled(allocator: std.mem.Allocator) bool {
    const file = std.fs.cwd().openFile(".acts/acts.json", .{}) catch return true;
    defer file.close();
    const content = file.readToEndAlloc(allocator, 65536) catch return true;
    defer allocator.free(content);
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch return true;
    defer parsed.deinit();
    const v = parsed.value;
    if (v != .object) return true;
    const hilt = v.object.get("hilt") orelse return true;
    if (hilt != .object) return true;
    if (hilt.object.get("auto_land_low")) |a| {
        if (a == .bool) return a.bool;
    }
    return true;
}

fn cmdApprove(allocator: std.mem.Allocator, id: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) == null) return error.ChangeNotFound;
    const tier = stack.getRisk(v, id) orelse "UNKNOWN";
    _ = try stack.appendApproval(allocator, v, id, "approve", "developer", tier, "human PR approval");
    _ = try stack.setPrApproved(allocator, v, id, true);
    _ = try stack.setChangeString(v, id, "status", stack.status_approved);
    try stack.save(allocator, v);
    try stdout("change {s} approved (risk: {s})\n", .{ id, tier });
}

fn cmdRework(allocator: std.mem.Allocator, id: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) == null) return error.ChangeNotFound;
    const tier = stack.getRisk(v, id) orelse "UNKNOWN";
    _ = try stack.appendApproval(allocator, v, id, "rework", "developer", tier, "reopened for rework");
    _ = try stack.setPrApproved(allocator, v, id, false);
    _ = try stack.setChangeString(v, id, "status", stack.status_in_progress);
    try stack.save(allocator, v);
    try stdout("change {s} reopened for rework\n", .{id});
}

fn cmdRisk(allocator: std.mem.Allocator, id: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;
    const root = &v.object;

    const m = stack.getChange(v, id) orelse return error.ChangeNotFound;
    const branch = if (m.get("branch")) |b| if (b == .string) b.string else "" else "";
    const base = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";

    const tier = try computeRiskForChange(allocator, v, id, branch, base);
    _ = try stack.setRisk(v, id, tier.label());
    try stack.save(allocator, v);

    const cross = try crossRepoEdgeCount(allocator, branch, base);
    const files = try git.changedFilesSince(allocator, base);
    const adds = try git.diffAdditions(allocator, base);
    const verified = stack.verifyAllPassed(v, id);

    try stdout("risk for {s}: {s}\n", .{ id, tier.label() });
    try stdout("  files: {d} | additions: {d} | cross-repo edges: {d} | verified: {s}\n", .{ files.len, adds, cross, if (verified) "yes" else "no" });
    if (tier == .LOW) {
        try stdout("  → LOW: eligible for auto-land after verification\n", .{});
    } else if (tier == .HIGH or tier == .CRITICAL) {
        try stdout("  → {s}: requires human review + escalation checklist\n", .{tier.label()});
    }
}

/// Compute the risk tier for a change from git-derived heuristics plus any
/// cross-repo data the CBM plugin has stored on the change under `risk`
/// (object with `cross_repo_edges`, `high_complexity_symbols`).
fn computeRiskForChange(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, branch: []const u8, base: []const u8) !risk.RiskTier {
    const files = try git.changedFilesSince(allocator, base);
    const adds = try git.diffAdditions(allocator, base);

    var cross: usize = try crossRepoEdgeCount(allocator, branch, base);
    var high_complexity: usize = 0;
    const meta = stack.getRiskMeta(v, id);
    if (meta.cross_repo_edges > 0) cross = meta.cross_repo_edges;
    high_complexity = meta.high_complexity_symbols;

    return risk.classify(.{
        .file_count = files.len,
        .diff_additions = adds,
        .cross_repo_edges = cross,
        .high_complexity_symbols = high_complexity,
        .verified = stack.verifyAllPassed(v, id),
    });
}

/// Build the ONE-PR body for a stack: all changes with acceptance, verification
/// evidence, and risk. No per-change branches involved.
fn buildReviewBody(allocator: std.mem.Allocator, v: std.json.Value) ![]const u8 {
    var buf = std.ArrayList(u8).init(allocator);
    const w = buf.writer();
    const sid = if (v.object.get("id")) |s| if (s == .string) s.string else "" else "";
    const stitle = if (v.object.get("title")) |s| if (s == .string) s.string else "" else "";
    const feat = stack.branchOf(v) orelse "";
    const integ = stack.integrationBranch(v);
    try w.print("# Stack: {s} — {s}\n\n", .{ sid, stitle });
    try w.print("**Feature branch:** `{s}` → `{s}`\n\n", .{ integ, feat });
    try w.writeAll("One PR for the whole stack. Each change is a checkpoint on the feature branch.\n\n");

    const changes = v.object.get("changes") orelse return buf.toOwnedSlice();
    if (changes != .array) return buf.toOwnedSlice();
    var idx: usize = 0;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const m = &c.*.object;
        const cid = if (m.get("id")) |s| if (s == .string) s.string else "" else "";
        const ctitle = if (m.get("title")) |s| if (s == .string) s.string else "" else "";
        const cstatus = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
        const crisk = stack.getRisk(v, cid) orelse "UNKNOWN";
        idx += 1;
        try w.print("\n## {d}. {s}: {s} — {s} (risk: {s})\n", .{ idx, cid, ctitle, cstatus, crisk });
        if (m.get("acceptance")) |acc| {
            if (acc == .array and acc.array.items.len > 0) {
                try w.writeAll("- Acceptance: ");
                var first = true;
                for (acc.array.items) |item| {
                    const s = if (item == .string) item.string else "?";
                    if (!first) try w.writeAll("; ");
                    try w.print("`{s}`", .{s});
                    first = false;
                }
                try w.writeAll("\n");
            }
        }
        if (m.get("verify")) |ver| {
            if (ver == .object) {
                for (stack.verify_stages) |stage| {
                    if (ver.object.get(stage)) |r| {
                        if (r == .object) {
                            const ok = if (r.object.get("ok")) |o| o == .bool and o.bool else false;
                            const cmd = if (r.object.get("cmd")) |cc| if (cc == .string) cc.string else "" else "";
                            try w.print("  - {s}: {s} `{s}`\n", .{ stage, if (ok) "PASS" else "FAIL", cmd });
                        }
                    }
                }
                if (ver.object.get("forced")) |f| {
                    if (f == .bool and f.bool) {
                        const reason = if (ver.object.get("force_reason")) |fr| if (fr == .string) fr.string else "" else "";
                        try w.print("  - forced verification: {s}\n", .{reason});
                    }
                }
            }
        }
    }
    try w.writeAll("\n---\nGenerated by ACTS. Review the changes and approve each checkpoint before `acts stack land`.\n");
    return buf.toOwnedSlice();
}

/// Number of files in this change that live in a repo outside the current one.
/// For a single-repo stack this is always 0; the CBM plugin can supply the
/// true cross-repo edge count via `acts risk <id> --cross-repo <n>`. We detect
/// files under a sibling repo layout heuristically (paths under ../*).
fn crossRepoEdgeCount(allocator: std.mem.Allocator, branch: []const u8, base: []const u8) !usize {
    _ = branch;
    const files = try git.changedFilesSince(allocator, base);
    var count: usize = 0;
    for (files) |f| {
        if (std.mem.startsWith(u8, f, "../")) count += 1;
    }
    return count;
}

/// `acts doc-risk <file>` — evaluate a spec/plan document (static + CBM).
fn cmdDocRisk(allocator: std.mem.Allocator, cwd: []const u8, file: []const u8, json_out: bool) !void {
    // Read the document (local file or remote URL).
    var content: []const u8 = undefined;
    if (std.mem.startsWith(u8, file, "http://") or std.mem.startsWith(u8, file, "https://")) {
        content = try fetchUrl(allocator, file);
    } else {
        content = try std.fs.cwd().readFileAlloc(allocator, file, 1 << 24);
    }
    defer allocator.free(content);

    const report = try docrisk.analyze(allocator, content);

    if (json_out) {
        try stdout("{s}\n", .{report});
        return;
    }

    try stdout("{s}\n", .{report});

    // CBM code-intelligence layer: resolve code references in the doc against
    // the graph. Best-effort; degrade to a note if CBM is unavailable.
    const bin = cbm.findBinary(allocator, cwd);
    if (bin) |b| {
        try stdout("\n## Code-intelligence (CBM graph)\n", .{});
        try stdout("- shared graph: {s}\n", .{cbm.cacheDir(allocator)});

        // Ensure the current repo is indexed (auto-index-if-missing, fast mode).
        const indexed = cbm.ensureIndexed(allocator, b, cwd);
        if (!indexed) {
            try stdout("> repo not indexed — run `acts graph index --all` for full enrichment.\n", .{});
            return;
        }

        // Extract code-looking references from the document (max 15, bounded).
        const refs = try extractCodeRefs(allocator, content, 15);
        if (refs.len == 0) {
            try stdout("- no code references found in the document.\n", .{});
            return;
        }

        const projects = try cbm.listProjects(allocator, b);
        var rows: usize = 0;
        for (refs) |ref| {
            if (rows >= 15) break;
            // Try each indexed project (bounded to keep this fast).
            for (projects) |p| {
                if (rows >= 15) break;
                const syms = cbm.searchSymbols(allocator, b, p.name, ref, 3) catch &[_]cbm.Symbol{};
                for (syms) |s| {
                    if (s.name.len == 0) continue;
                    const tr = cbm.traceSymbol(allocator, b, p.name, s.name);
                    const risk_mark = if (tr.cross_repo >= 2) "CRITICAL" else if (tr.cross_repo >= 1 or s.complexity >= 15) "HIGH" else if (s.complexity >= 8) "MEDIUM" else "LOW";
                    try stdout(
                        "| {s} | {s} | {s} | x-repo {d} | complexity {d} | in {d}/out {d} |\n",
                        .{ s.name, p.name, risk_mark, tr.cross_repo, s.complexity, tr.callers, tr.callees },
                    );
                    rows += 1;
                }
                if (rows > 0) break; // resolved in this project
            }
        }
        if (rows == 0) {
            try stdout("- references not found in indexed graph (plan may target code that doesn't exist yet).\n", .{});
        }
    } else {
        try stdout("\n> code-intelligence unavailable (cbm not installed) — run `acts setup --with-cbm`.\n", .{});
    }
}

/// Extract up to `max` code-looking tokens from a document: PascalCase /
/// camelCase symbols and dotted `pkg.Fn` or `Repo::Thing` references.
fn extractCodeRefs(allocator: std.mem.Allocator, content: []const u8, max: usize) ![][]const u8 {
    var out = std.ArrayList([]const u8).init(allocator);
    var seen = std.StringHashMap(void).init(allocator);

    var it = std.mem.tokenizeAny(u8, content, " \t\n\r,.;:()[]{}\"'`=+*/-");
    while (it.next()) |tok| {
        if (out.items.len >= max) break;
        if (tok.len < 3 or tok.len > 40) continue;
        // Skip markdown/url-ish and stopwords.
        if (std.mem.eql(u8, tok, "the") or std.mem.eql(u8, tok, "and") or
            std.mem.eql(u8, tok, "with") or std.mem.eql(u8, tok, "https") or
            std.mem.eql(u8, tok, "http")) continue;
        if (std.mem.indexOf(u8, tok, "//") != null) continue;

        // Looks like a symbol: contains a dot, or starts uppercase + has a lowercase tail,
        // or camelCase with an uppercase interior.
        const has_dot = std.mem.indexOfScalar(u8, tok, '.') != null;
        const starts_upper = std.ascii.isUpper(tok[0]);
        var has_upper_interior = false;
        var has_lower = false;
        for (tok[1..]) |ch| {
            if (std.ascii.isUpper(ch)) has_upper_interior = true;
            if (std.ascii.isLower(ch)) has_lower = true;
        }
        if (!has_dot and !(starts_upper and has_lower) and !has_upper_interior) continue;

        // Build a regex-ish pattern: escape nothing, just anchor with .* around for search_graph.
        const pat = try std.fmt.allocPrint(allocator, ".*{s}.*", .{tok});
        if (!seen.contains(tok)) {
            try seen.put(tok, {});
            try out.append(pat);
        }
    }
    return out.toOwnedSlice();
}

/// Fetch a remote document via curl.
fn fetchUrl(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    if (!git.hasTool(allocator, "curl")) return error.CurlMissing;
    const tmp = "/tmp/acts-docrisk-XXXXXX";
    const res = try git.run(allocator, &.{ "curl", "-fsSL", url }, 1 << 24);
    if (res.exit_code != 0) return error.DownloadFailed;
    _ = tmp;
    return allocator.dupe(u8, res.stdout);
}

fn cmdContext(allocator: std.mem.Allocator, id_arg: ?[]const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    const id = id_arg orelse (resolveCurrentChange(allocator, v) orelse return error.NoActiveChange);
    const pack = try context.buildContextPack(allocator, v, id);
    try stdout("{s}\n", .{pack});
}

fn cmdNote(allocator: std.mem.Allocator, id: []const u8, msg: []const u8, args: *const Args) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) == null) return error.ChangeNotFound;

    // Optional cost tracking: `acts note <id> -m "..." --cost <$>`
    if (args.flag("--cost")) |cost_str| {
        const cost = std.fmt.parseFloat(f64, cost_str) catch 0;
        _ = try stack.setCost(v, id, cost);
        try stdout("  cost: ${d:.2}\n", .{cost});
    }

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
// setup
// ---------------------------------------------------------------------------

fn cmdSetup(allocator: std.mem.Allocator, args: *const Args) !void {
    const target = if (args.positional.items.len >= 1) args.positional.items[0] else ".";
    try setup.run(allocator, .{
        .target_dir = target,
        .source_dir = args.flag("--source"),
        .with_github = args.has("--github"),
        .force = args.has("--force"),
        .no_install = args.has("--no-install"),
        .bin_dir = args.flag("--bin-dir") orelse "~/.local/bin",
        .with_archify = args.has("--with-archify"),
    });
    try stdout("setup complete for {s}\n", .{target});
    try stdout("  next: open a session with OpenCode — the acts skill + tools are wired.\n", .{});
    if (!args.has("--no-install")) {
        try stdout("  next: `acts stack create <id>` to start your first stack.\n", .{});
    }
}

// ---------------------------------------------------------------------------
// v1 → v2 migration
// ---------------------------------------------------------------------------

/// Migrate a v1 ACTS project (SQLite `.acts/acts.db`) to v2 (`.acts/stack.json`
/// + git branches). Reads the v1 DB via the `sqlite3` CLI. For each v1 story
/// (skipping `__maintenance__`), creates a v2 stack and maps its tasks to
/// changes. Branches are created on demand with `--create-branches`.
fn cmdMigrate(allocator: std.mem.Allocator, args: *const Args) !void {
    const v1_db = ".acts/acts.db";
    if (stack.manifestExists()) {
        try stdout("a v2 stack already exists ({s}) — refusing to overwrite.\n", .{stack.manifest_path});
        return error.StackAlreadyExists;
    }
    std.fs.cwd().access(v1_db, .{}) catch {
        try stdout("no v1 database found ({s}) — nothing to migrate.\n", .{v1_db});
        return;
    };
    if (!git.hasTool(allocator, "sqlite3")) {
        try stdout("error: `sqlite3` CLI not found — required to read the v1 database.\n", .{});
        return error.ToolMissing;
    }

    const story_id = if (args.positional.items.len >= 1) args.positional.items[0] else null;

    // ── Query stories ─────────────────────────
    const stories_sql = "SELECT id, title, status, type FROM stories WHERE id != '__maintenance__' ORDER BY id;";
    const stories_res = try git.run(allocator, &.{ "sqlite3", "-separator", "|", v1_db, stories_sql }, 65536);
    if (stories_res.exit_code != 0) {
        try stderr("sqlite3: {s}\n", .{std.mem.trim(u8, stories_res.stderr, " \n\r")});
        return error.MigrationFailed;
    }

    var stories = std.ArrayList([]const u8).init(allocator);
    var it = std.mem.tokenizeAny(u8, stories_res.stdout, "\n");
    while (it.next()) |line| try stories.append(line);

    if (stories.items.len == 0) {
        try stdout("v1 database has no migratable stories.\n", .{});
        return;
    }

    // ── Pick the story to migrate ─────────────
    var chosen: []const u8 = undefined;
    if (story_id) |sid| {
        var found: ?[]const u8 = null;
        for (stories.items) |line| {
            if (std.mem.startsWith(u8, line, sid) and line.len >= sid.len and line[sid.len] == '|') {
                found = line;
                break;
            }
        }
        if (found) |f| {
            chosen = f;
        } else {
            // Story not found — list the available ones to help the user.
            try stdout("no v1 story found with id '{s}'. Available stories:\n", .{sid});
            for (stories.items) |line| {
                var f = std.mem.splitScalar(u8, line, '|');
                if (f.next()) |story_line_id| {
                    try stdout("  - {s}\n", .{story_line_id});
                }
            }
            return error.StoryNotFound;
        }
    } else {
        chosen = stories.items[0];
    }

    var fields = std.mem.splitScalar(u8, chosen, '|');
    const sid = fields.next() orelse return error.MigrationFailed;
    const stitle = fields.next() orelse sid;
    const sstatus = fields.next() orelse "";
    _ = sstatus;

    // ── Create the v2 stack ───────────────────
    if (!git.isGitRepo(allocator)) return error.NotGitRepo;
    if (!validId(sid)) return error.InvalidStackId;
    const base_branch = try std.fmt.allocPrint(allocator, "acts/{s}/base", .{sid});
    const res = try git.createBranch(allocator, base_branch, "");
    if (res.exit_code != 0) {
        try stderr("git: {s}\n", .{std.mem.trim(u8, res.stderr, " \n\r")});
        return error.BranchConflict;
    }

    var root_map = std.json.ObjectMap.init(allocator);
    try root_map.put("version", .{ .integer = 2 });
    try root_map.put("id", .{ .string = sid });
    try root_map.put("title", .{ .string = stitle });
    try root_map.put("base_branch", .{ .string = base_branch });
    var changes = std.json.Array.init(allocator);

    // ── Query tasks for this story ────────────
    const esc = try std.mem.replaceOwned(u8, allocator, sid, "'", "''");
    const tasks_sql = try std.fmt.allocPrint(
        allocator,
        "SELECT id, title, status, review_status FROM tasks WHERE story_id = '{s}' ORDER BY id;",
        .{esc},
    );
    const tasks_res = try git.run(allocator, &.{ "sqlite3", "-separator", "|", v1_db, tasks_sql }, 65536);
    if (tasks_res.exit_code != 0) {
        try stderr("sqlite3: {s}\n", .{std.mem.trim(u8, tasks_res.stderr, " \n\r")});
        return error.MigrationFailed;
    }

    var tasks_it = std.mem.tokenizeAny(u8, tasks_res.stdout, "\n");
    var idx: usize = 0;
    var prev_tid: ?[]const u8 = null;
    while (tasks_it.next()) |line| {
        var f = std.mem.splitScalar(u8, line, '|');
        const tid = f.next() orelse continue;
        const ttitle = f.next() orelse continue;
        const tstatus = f.next() orelse "";
        const treview = f.next() orelse "";

        idx += 1;
        const slug = try slugify(allocator, ttitle);
        const branch = try std.fmt.allocPrint(allocator, "acts/{s}/c{d}-{s}", .{ sid, idx, slug });

        var entry = std.json.ObjectMap.init(allocator);
        try entry.put("id", .{ .string = tid });
        try entry.put("title", .{ .string = ttitle });
        try entry.put("branch", .{ .string = branch });
        if (prev_tid) |pt| {
            try entry.put("parent", .{ .string = pt });
        } else {
            try entry.put("parent", .null);
        }
        prev_tid = tid;
        try entry.put("acceptance", .{ .array = std.json.Array.init(allocator) });
        try entry.put("verify", .{ .object = std.json.ObjectMap.init(allocator) });
        try entry.put("notes", .{ .array = std.json.Array.init(allocator) });
        try entry.put("checkpoint", .null);
        try entry.put("status", .{ .string = statusFromV1(tstatus, treview) });

        var pr = std.json.ObjectMap.init(allocator);
        try pr.put("url", .null);
        try pr.put("approved", .{ .bool = std.mem.eql(u8, treview, "approved") });
        try entry.put("pr", .{ .object = pr });

        // Preserve v1 file ownership as a session note
        const files = try queryV1Files(allocator, v1_db, tid);
        if (files.len > 0) {
            var note = std.ArrayList(u8).init(allocator);
            try note.writer().print("# migrated from ACTS v1 — files owned\n", .{});
            for (files) |fp| {
                try note.writer().print("- {s}\n", .{fp});
            }
            const dir = try std.fmt.allocPrint(allocator, ".acts/changes/{s}/notes", .{tid});
            std.fs.cwd().makePath(dir) catch {};
            const fname = try std.fmt.allocPrint(allocator, "{s}/v1-files.md", .{dir});
            try std.fs.cwd().writeFile(.{ .sub_path = fname, .data = note.items });
            _ = try stack.appendNote(allocator, .{ .object = root_map }, tid, fname);
        }

        try changes.append(.{ .object = entry });
    }

    try root_map.put("changes", .{ .array = changes });
    try stack.save(allocator, .{ .object = root_map });

    try stdout("migrated v1 story {s} → v2 stack (base branch {s}, {d} changes)\n", .{ sid, base_branch, idx });
    try stdout("  next: acts change status c1  |  acts verify --all  |  acts review <id>\n", .{});
}

/// Query v1 task_files for a task id, returning the list of file paths.
fn queryV1Files(allocator: std.mem.Allocator, v1_db: []const u8, tid: []const u8) ![][]const u8 {
    const esc = try std.mem.replaceOwned(u8, allocator, tid, "'", "''");
    const sql = try std.fmt.allocPrint(allocator, "SELECT file_path FROM task_files WHERE task_id = '{s}';", .{esc});
    const res = try git.run(allocator, &.{ "sqlite3", "-separator", "|", v1_db, sql }, 65536);
    var out = std.ArrayList([]const u8).init(allocator);
    var it = std.mem.tokenizeAny(u8, res.stdout, "\n");
    while (it.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \r");
        if (trimmed.len > 0) try out.append(trimmed);
    }
    return out.toOwnedSlice();
}

/// Map v1 task status + review_status to a v2 change status.
fn statusFromV1(tstatus: []const u8, treview: []const u8) []const u8 {
    if (std.mem.eql(u8, tstatus, "DONE")) {
        if (std.mem.eql(u8, treview, "approved")) return stack.status_approved;
        return stack.status_verified;
    }
    if (std.mem.eql(u8, tstatus, "IN_PROGRESS") or std.mem.eql(u8, tstatus, "BLOCKED")) return stack.status_in_progress;
    return stack.status_todo;
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

fn activeChangeForBranch(v: std.json.Value, branch: []const u8) ?[]const u8 {
    const changes = v.object.get("changes") orelse return null;
    if (changes != .array) return null;
    const feat = stack.branchOf(v) orelse "";
    if (std.mem.eql(u8, branch, feat)) {
        return stack.topChange(v);
    }
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const m = &c.*.object;
        if (m.get("status")) |st| {
            if (st == .string and std.mem.eql(u8, st.string, stack.status_merged)) continue;
        }
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

/// Resolve the active change id from the currently checked-out git branch.
fn resolveCurrentChange(allocator: std.mem.Allocator, v: std.json.Value) ?[]const u8 {
    const branch = git.currentBranch(allocator) catch null orelse return null;
    return activeChangeForBranch(v, branch);
}

// Swallow broken-pipe errors: piping to `grep -q` / `head` closes stdout early,
// and that should not make `acts` fail (exit code is already decided by then).
fn stdout(comptime fmt: []const u8, args: anytype) !void {
    std.io.getStdOut().writer().print(fmt, args) catch |err| switch (err) {
        error.BrokenPipe => return,
        else => return err,
    };
}

fn stderr(comptime fmt: []const u8, args: anytype) !void {
    std.io.getStdErr().writer().print(fmt, args) catch |err| switch (err) {
        error.BrokenPipe => return,
        else => return err,
    };
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

test "statusFromV1 maps v1 task statuses to v2 change statuses" {
    try std.testing.expectEqualStrings(stack.status_approved, statusFromV1("DONE", "approved"));
    try std.testing.expectEqualStrings(stack.status_verified, statusFromV1("DONE", "pending"));
    try std.testing.expectEqualStrings(stack.status_in_progress, statusFromV1("IN_PROGRESS", "pending"));
    try std.testing.expectEqualStrings(stack.status_in_progress, statusFromV1("BLOCKED", "changes_requested"));
    try std.testing.expectEqualStrings(stack.status_todo, statusFromV1("TODO", "pending"));
}

test "verifyAllPassed honors forced verification" {
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
    try entry.put("status", .{ .string = stack.status_in_progress });
    try entry.put("branch", .{ .string = "acts/auth/c1-jwt" });
    try entry.put("parent", .null);
    try changes.append(.{ .object = entry });
    try root.put("changes", .{ .array = changes });
    const v: std.json.Value = .{ .object = root };

    // No verify yet → not passed
    try std.testing.expect(!stack.verifyAllPassed(v, "c1"));

    // A failing stage → not passed
    _ = try stack.recordVerify(a, v, "c1", "test", "npm test", false, 1, 10);
    try std.testing.expect(!stack.verifyAllPassed(v, "c1"));

    // Force it → passed, and flagged forced
    _ = try stack.setVerifyForced(a, v, "c1", "force", "lint fails outside change");
    try std.testing.expect(stack.verifyAllPassed(v, "c1"));
    try std.testing.expect(stack.isVerifyForced(v, "c1"));
    try std.testing.expectEqualStrings("lint fails outside change", stack.getVerifyForcedReason(v, "c1").?);
}

test "failingFilesOwnedByChange detects owned vs external files" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    _ = a;

    const owned = [_][]const u8{ "src/auth.ts", "src/routes.ts" };

    // Output mentions an external file → not owned by the change.
    const ext_output = "src/generated/foo.js:1:1 error: not formatted\nmake: *** [lint] Error 1\n";
    try std.testing.expect(!failingFilesOwnedByChangeWithOwned(ext_output, &owned));

    // Output mentions a file owned by the change → owned.
    const owned_output = "src/auth.ts:3:5 error: unused var\n";
    try std.testing.expect(failingFilesOwnedByChangeWithOwned(owned_output, &owned));

    // A bare path with no line suffix, plus trailing colon form.
    try std.testing.expect(failingFilesOwnedByChangeWithOwned("src/routes.ts error", &owned));

    // Empty output (broken tooling) → not owned, so force is allowed.
    try std.testing.expect(!failingFilesOwnedByChangeWithOwned("", &owned));
}

test "usage text documents diagram and archify install" {
    try std.testing.expect(std.mem.indexOf(u8, usage_text, "diagram <id>") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_text, "--delta") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_text, "--attach") != null);
    try std.testing.expect(std.mem.indexOf(u8, usage_text, "archify install") != null);
}

test "activeChangeForBranch picks top non-merged change on the feature branch" {
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
    try c1.put("status", .{ .string = "VERIFIED" });
    try ch.append(.{ .object = c1 });
    var c2 = std.json.ObjectMap.init(a);
    try c2.put("id", .{ .string = "c2" });
    try c2.put("status", .{ .string = "TODO" });
    try ch.append(.{ .object = c2 });
    var c3 = std.json.ObjectMap.init(a);
    try c3.put("id", .{ .string = "c3" });
    try c3.put("status", .{ .string = "MERGED" });
    try ch.append(.{ .object = c3 });
    try r.put("changes", .{ .array = ch });
    const v: std.json.Value = .{ .object = r };

    try std.testing.expectEqualStrings("c2", activeChangeForBranch(v, "acts/auth/feature").?);
    try std.testing.expect(activeChangeForBranch(v, "master") == null);

    // Legacy v2: a change with a per-change `branch` resolves when checked out.
    var rl = std.json.ObjectMap.init(a);
    try rl.put("version", .{ .integer = 2 });
    try rl.put("base_branch", .{ .string = "acts/x/base" });
    var chl = std.json.Array.init(a);
    var lc = std.json.ObjectMap.init(a);
    try lc.put("id", .{ .string = "c1" });
    try lc.put("status", .{ .string = "TODO" });
    try lc.put("branch", .{ .string = "acts/x/c1" });
    try chl.append(.{ .object = lc });
    var lc2 = std.json.ObjectMap.init(a);
    try lc2.put("id", .{ .string = "c2" });
    try lc2.put("status", .{ .string = "MERGED" });
    try lc2.put("branch", .{ .string = "acts/x/c2" });
    try chl.append(.{ .object = lc2 });
    try rl.put("changes", .{ .array = chl });
    const vl: std.json.Value = .{ .object = rl };
    try std.testing.expectEqualStrings("c1", activeChangeForBranch(vl, "acts/x/c1").?);
    try std.testing.expect(activeChangeForBranch(vl, "acts/x/other") == null);
    try std.testing.expect(activeChangeForBranch(vl, "acts/x/c2") == null);
}

test "buildReviewBody renders stack summary with per-change sections" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var r = std.json.ObjectMap.init(a);
    try r.put("version", .{ .integer = 3 });
    try r.put("id", .{ .string = "auth" });
    try r.put("title", .{ .string = "Add auth" });
    try r.put("branch", .{ .string = "acts/auth/feature" });
    try r.put("base_branch", .{ .string = "master" });
    var ch = std.json.Array.init(a);
    var c1 = std.json.ObjectMap.init(a);
    try c1.put("id", .{ .string = "c1" });
    try c1.put("title", .{ .string = "JWT middleware" });
    try c1.put("status", .{ .string = "VERIFIED" });
    try c1.put("risk", .{ .string = "LOW" });
    var acc = std.json.Array.init(a);
    try acc.append(.{ .string = "token validated" });
    try c1.put("acceptance", .{ .array = acc });
    var ver = std.json.ObjectMap.init(a);
    var v1 = std.json.ObjectMap.init(a);
    try v1.put("ok", .{ .bool = true });
    try v1.put("cmd", .{ .string = "npm test" });
    try ver.put("test", .{ .object = v1 });
    try c1.put("verify", .{ .object = ver });
    try ch.append(.{ .object = c1 });
    var c2 = std.json.ObjectMap.init(a);
    try c2.put("id", .{ .string = "c2" });
    try c2.put("title", .{ .string = "Ops changes" });
    try c2.put("status", .{ .string = "VERIFIED" });
    var ver2 = std.json.ObjectMap.init(a);
    try ver2.put("forced", .{ .bool = true });
    try ver2.put("force_reason", .{ .string = "lint fails outside change" });
    try c2.put("verify", .{ .object = ver2 });
    try ch.append(.{ .object = c2 });
    try r.put("changes", .{ .array = ch });
    const v: std.json.Value = .{ .object = r };

    const body = try buildReviewBody(a, v);
    try std.testing.expect(std.mem.indexOf(u8, body, "Add auth") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "JWT middleware") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "token validated") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "npm test") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "LOW") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "forced verification") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "lint fails outside change") != null);
}
