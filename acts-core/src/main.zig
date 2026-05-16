const std = @import("std");
const cli = @import("cli.zig");
const db = @import("db.zig");
const build_options = @import("build_options");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        std.process.exit(1);
    }

    const command = args[1];
    const cmd_args = args[2..];

    if (std.mem.eql(u8, command, "init")) {
        try handleInit(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "state")) {
        try handleState(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "task")) {
        try handleTask(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "review")) {
        try handleReview(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "approve")) {
        try handleApprove(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "reject")) {
        try handleReject(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "gate")) {
        try handleGate(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "decision")) {
        try handleDecision(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "approach")) {
        try handleApproach(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "question")) {
        try handleQuestion(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "ownership")) {
        try handleOwnership(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "scope")) {
        try handleScope(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "session")) {
        try handleSession(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "operation")) {
        try handleOperation(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "validate")) {
        try handleValidate(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "migrate")) {
        try handleMigrate(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "story")) {
        try handleStory(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "db")) {
        try handleDb(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "presence")) {
        try handlePresence(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "unblock")) {
        try handleUnblock(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "review-queue")) {
        try handleReviewQueue(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "gate-sla")) {
        try handleGateSla(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "changelog")) {
        try handleChangelog(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "override")) {
        try handleOverride(allocator, cmd_args);
    } else if (std.mem.eql(u8, command, "version") or std.mem.eql(u8, command, "--version") or std.mem.eql(u8, command, "-v")) {
        try printVersion();
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help") or std.mem.eql(u8, command, "-h")) {
        try printUsage();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printUsage();
        std.process.exit(1);
    }
}

fn printUsage() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(
        \\ACTS Core v1.1.0 - Agent Collaborative Tracking Standard
        \\
        \\Usage: acts <command> [options]
        \\
        \\Story Management:
        \\  init <story-id>              Initialize a new ACTS story
        \\  story create <id>            Create story with worktree
        \\    --title "..."                Story title
        \\    --from <branch>              Base branch (default: main)
        \\    --parent <story-id>          Parent story (optional)
        \\  story list                   List all stories
        \\    --include-archived           Show archived stories
        \\    --include-maintenance        Show maintenance story
        \\  story switch <id>            Switch active story
        \\  story archive <id>           Archive a completed story
        \\  story merge <id>             Merge story into target branch
        \\    --into <branch>              Target branch (default: main)
        \\    --semver <version>           Override computed semver
        \\  story graph                  Show story dependency graph
        \\    --format json|dot            Output format (default: json)
        \\
        \\State:
        \\  state read [--story <id>]    Read story state
        \\    --format json|pretty|table   Output format (default: json)
        \\  state write --story <id>     Write story state from stdin JSON
        \\
        \\Tasks:
        \\  task create <id>             Create a new task
        \\    --title "..."                Task title (required)
        \\    --story <id>                 Story (default: __maintenance__)
        \\    --description "..."          Task description
        \\    --labels "a,b"               JSON labels array
        \\  task get <id>                Get task details
        \\  task list                    List tasks
        \\    --story <id>                 Filter by story
        \\    --maintenance                Show maintenance tasks only
        \\    --status <status>            Filter by status
        \\  task update <id>             Update task status
        \\    --status <status>            Set status
        \\    --assigned-to <name>         Set assignee
        \\  task move <id>               Move task to another story
        \\    --to <story-id>              Target story (required)
        \\
        \\Review:
        \\  review <task-id>             Review task changes (enhanced HRE with vim navigation)
        \\  approve <task-id>            Approve task-review gate
        \\  reject <task-id>             Request changes on task-review gate
        \\
        \\Gates:
        \\  gate add --task <id>         Add gate checkpoint
        \\    --type <type>                Gate type
        \\    --status <status>            Status
        \\    --by <name>                  Who approved
        \\  gate list --task <id>        List gate checkpoints
        \\  gate-sla                     Show gate SLA status
        \\    --breached                   Show only breached SLAs
        \\
        \\Decisions & Learnings:
        \\  decision add                 Record decision from stdin JSON
        \\  decision list --task <id>    List decisions
        \\  approach add --rejected      Record rejected approach
        \\  question add                 Add open question
        \\  question resolve <id>        Resolve question
        \\
        \\Ownership & Scope:
        \\  ownership map                Show file ownership
        \\  scope check --task <id>      Check file scope
        \\    --file <path>                File to check
        \\
        \\Proactive Signals:
        \\  presence set                 Set agent presence
        \\    --agent <id>                 Agent ID
        \\    --task <id>                  Current task
        \\    --action "..."               Current action
        \\  presence list                Show active agents
        \\  unblock list                 Show unblock events
        \\    --acknowledged               Show acknowledged only
        \\  unblock ack <id>             Acknowledge unblock event
        \\  review-queue                 Show review queue
        \\    --story <id>                 Filter by story
        \\
        \\Changelog:
        \\  changelog --story <id>       Generate changelog from story data
        \\    --format md|json             Output format (default: md)
        \\
        \\Overrides (human-only):
        \\  override request               Request file override
        \\    --file <path>                  File to override (required)
        \\    --task <id>                    Requesting task (required)
        \\    --reason "..."                 Reason (required)
        \\  override approve <id>        Approve override (human only)
        \\    --by <name>                    Human approver name (required)
        \\  override reject <id>         Reject override
        \\  override list [--pending]    List overrides
        \\
        \\Database:
        \\  db checkpoint                Run WAL checkpoint
        \\  db status                    Show database status
        \\
        \\Sessions:
        \\  session parse <file.md>      Parse session markdown
        \\  session validate <file.md>   Validate session
        \\  session list --task <id>     List sessions for task
        \\
        \\Operations:
        \\  operation log --id <op>      Log operation
        \\  operation list [--task <id>] List operations
        \\  operation show <id>          Show operation details
        \\
        \\Validation:
        \\  validate                     Validate entire project
        \\  migrate                      Force schema migration
        \\  version                      Show version
        \\
    );
}

fn printVersion() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("acts {s}\n", .{build_options.version});
}

// ============================================================
// Story resolution (implicit --story from env/symlink/cwd)
// ============================================================

fn resolveStoryId(allocator: std.mem.Allocator, database: *db.Database, explicit: ?[]const u8) ![]const u8 {
    if (explicit) |id| return try allocator.dupe(u8, id);
    if (std.process.getEnvVarOwned(allocator, "ACTS_STORY")) |env| return env;

    // Try .acts/current symlink
    const link = std.fs.cwd().readLink(".acts/current") catch |err| {
        if (err == error.FileNotFound or err == error.SymLinkInvalid) {
            // Check if single story in DB
            return try getSingleStoryId(allocator, database);
        }
        return err;
    };
    defer allocator.free(link);
    const basename = std.fs.path.basename(link);
    return try allocator.dupe(u8, basename);
}

fn getSingleStoryId(allocator: std.mem.Allocator, database: *db.Database) ![]const u8 {
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(database.db, "SELECT id FROM stories WHERE id != '__maintenance__' AND status != 'ARCHIVED'", -1, &stmt, null);
    if (rc != c.SQLITE_OK) return error.QueryFailed;
    defer _ = c.sqlite3_finalize(stmt);

    const first = c.sqlite3_step(stmt) == c.SQLITE_ROW;
    const id1 = if (first) try allocator.dupe(u8, std.mem.span(c.sqlite3_column_text(stmt, 0))) else null;
    const second = c.sqlite3_step(stmt) == c.SQLITE_ROW;

    if (id1) |id| {
        if (!second) return id; // Exactly one story
        allocator.free(id);
    }
    return error.NoActiveStory;
}

// ============================================================
// Init
// ============================================================

fn handleInit(_: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts init <story-id> [--title \"...\"]\n", .{});
        std.process.exit(1);
    }
    const story_id = args[0];
    var title: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--title") and i + 1 < args.len) {
            title = args[i + 1];
            i += 1;
        }
    }

    try std.fs.cwd().makePath(".acts");
    try std.fs.cwd().makePath(".story/sessions");
    try std.fs.cwd().makePath(".story/tasks");

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();

    try database.migrate();
    try database.initStory(story_id, title orelse story_id);

    const plan_file = try std.fs.cwd().createFile(".story/plan.md", .{});
    defer plan_file.close();
    try plan_file.writeAll("# Plan\n\n## Overview\n\n[Story overview]\n\n## Tasks\n\n");

    const spec_file = try std.fs.cwd().createFile(".story/spec.md", .{});
    defer spec_file.close();
    try spec_file.writeAll("# Specification\n\n## Overview\n\n[Story specification]\n\n## Acceptance Criteria\n\n");

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Initialized ACTS story: {s}\n", .{story_id});
    try stdout.print("Database: {s}\n", .{db_path});
    try stdout.writeAll("Created: .story/plan.md, .story/spec.md, .story/sessions/\n");
}

// ============================================================
// State
// ============================================================

fn handleState(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts state <read|write> [options]\n", .{});
        std.process.exit(1);
    }

    const subcommand = args[0];
    var story_id: ?[]const u8 = null;
    var format: []const u8 = "json";

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--story") and i + 1 < args.len) {
            story_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--format") and i + 1 < args.len) {
            format = args[i + 1];
            i += 1;
        }
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    if (std.mem.eql(u8, subcommand, "read")) {
        const state = try database.readState(allocator, story_id);
        defer allocator.free(state);
        const stdout = std.io.getStdOut().writer();

        if (std.mem.eql(u8, format, "json")) {
            try stdout.writeAll(state);
            try stdout.writeAll("\n");
        } else if (std.mem.eql(u8, format, "pretty")) {
            const pretty = try prettyPrintJson(allocator, state);
            defer allocator.free(pretty);
            try stdout.writeAll(pretty);
            try stdout.writeAll("\n");
        } else if (std.mem.eql(u8, format, "table")) {
            try printStateTable(stdout, allocator, state);
        } else {
            std.debug.print("Unknown format: {s}. Use json, pretty, or table.\n", .{format});
            std.process.exit(1);
        }
    } else if (std.mem.eql(u8, subcommand, "write")) {
        if (story_id == null) {
            std.debug.print("Usage: acts state write --story <id> (reads JSON from stdin)\n", .{});
            std.process.exit(1);
        }
        const stdin = std.io.getStdIn().reader();
        const input = try stdin.readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(input);
        try database.writeState(allocator, story_id.?, input);
    } else {
        std.debug.print("Unknown state subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}

// ============================================================
// State formatting helpers
// ============================================================

fn prettyPrintJson(allocator: std.mem.Allocator, json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    try std.json.stringify(parsed.value, .{ .whitespace = .indent_2 }, out.writer());

    return out.toOwnedSlice();
}

fn printStateTable(writer: anytype, allocator: std.mem.Allocator, json: []const u8) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return;
    const obj = parsed.value.object;

    // Story header
    const title = if (obj.get("title")) |v| if (v == .string) v.string else "?" else "?";
    const status = if (obj.get("status")) |v| if (v == .string) v.string else "?" else "?";
    const story_id = if (obj.get("story_id")) |v| if (v == .string) v.string else "?" else "?";
    const story_type = if (obj.get("type")) |v| if (v == .string) v.string else "?" else "?";

    try writer.print("{s}{s} — {s}{s} ({s}, {s})\n", .{ "\x1b[1m", story_id, title, "\x1b[0m", story_type, status });
    try writer.writeAll("══════════════════════════════════════════════════════\n\n");

    // Tasks table
    if (obj.get("tasks")) |tasks| {
        if (tasks == .array and tasks.array.items.len > 0) {
            try writer.print("{s}{s:<10} {s:<30} {s:<12} {s:<10} {s:<12}{s}\n", .{
                "\x1b[1m", "ID", "Title", "Status", "Priority", "Review", "\x1b[0m",
            });
            try writer.writeAll("────────────────────────────────────────────────────────────\n");

            for (tasks.array.items) |task| {
                if (task != .object) continue;
                const t = task.object;

                const tid = if (t.get("id")) |v| if (v == .string) v.string else "?" else "?";
                const ttitle = if (t.get("title")) |v| if (v == .string) v.string else "?" else "?";
                const tstatus = if (t.get("status")) |v| if (v == .string) v.string else "?" else "?";
                const treview = if (t.get("review_status")) |v| if (v == .string) v.string else "?" else "?";
                const tpriority = if (t.get("context_priority")) |v| if (v == .integer) std.fmt.allocPrint(allocator, "{d}", .{v.integer}) catch "?" else "?" else "?";

                // Color status
                const status_color = if (std.mem.eql(u8, tstatus, "DONE")) "\x1b[32m"
                    else if (std.mem.eql(u8, tstatus, "IN_PROGRESS")) "\x1b[33m"
                    else if (std.mem.eql(u8, tstatus, "BLOCKED")) "\x1b[31m"
                    else "\x1b[0m";

                try writer.print("{s:<10} {s:<30} {s}{s:<12}{s} {s:<10} {s:<12}\n", .{
                    tid, ttitle, status_color, tstatus, "\x1b[0m", tpriority, treview,
                });

                // Show files if any
                if (t.get("files_touched")) |files| {
                    if (files == .array and files.array.items.len > 0) {
                        for (files.array.items) |f| {
                            if (f == .string) {
                                try writer.print("             {s}{s}\n", .{ "\x1b[2m", f.string });
                            }
                        }
                    }
                }
            }
            try writer.writeAll("\n");
        }
    }
}

// ============================================================
// Task (get, update, create, list, move)
// ============================================================

fn handleTask(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("Usage: acts task <get|update|create|list|move> ...\n", .{});
        std.process.exit(1);
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "create")) {
        try handleTaskCreate(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        try handleTaskList(allocator, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "move")) {
        try handleTaskMove(allocator, args[1..]);
    } else {
        // get / update (existing behavior)
        const task_id = args[1];

        var status: ?[]const u8 = null;
        var assigned_to: ?[]const u8 = null;

        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--status") and i + 1 < args.len) {
                status = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--assigned-to") and i + 1 < args.len) {
                assigned_to = args[i + 1];
                i += 1;
            }
        }

        const db_path = ".acts/acts.db";
        var database = try db.Database.open(db_path);
        defer database.close();
        try database.migrate();

        if (std.mem.eql(u8, subcommand, "get")) {
            const task = try database.getTask(allocator, task_id);
            defer allocator.free(task);
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll(task);
            try stdout.writeAll("\n");
        } else if (std.mem.eql(u8, subcommand, "update")) {
            try database.updateTask(task_id, status, assigned_to);
        } else {
            std.debug.print("Unknown task subcommand: {s}\n", .{subcommand});
            std.process.exit(1);
        }
    }
}

fn handleTaskCreate(_: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts task create <id> --title \"...\" [--story <id>] [--description \"...\"] [--labels \"a,b\"]\n", .{});
        std.process.exit(1);
    }
    const task_id = args[0];
    var title: ?[]const u8 = null;
    var story_id: ?[]const u8 = null;
    var description: ?[]const u8 = null;
    var labels: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--title") and i + 1 < args.len) {
            title = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--story") and i + 1 < args.len) {
            story_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--description") and i + 1 < args.len) {
            description = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--labels") and i + 1 < args.len) {
            labels = args[i + 1];
            i += 1;
        }
    }

    if (title == null) {
        std.debug.print("Error: --title is required\n", .{});
        std.process.exit(1);
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    try database.createTask(task_id, story_id, title.?, description, labels);

    const stdout = std.io.getStdOut().writer();
    const actual_story = story_id orelse "__maintenance__";
    try stdout.print("Task {s} created in story {s}\n", .{ task_id, actual_story });
}

fn handleTaskList(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var story_id: ?[]const u8 = null;
    var maintenance_only = false;
    var status_filter: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--story") and i + 1 < args.len) {
            story_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--maintenance")) {
            maintenance_only = true;
        } else if (std.mem.eql(u8, args[i], "--status") and i + 1 < args.len) {
            status_filter = args[i + 1];
            i += 1;
        }
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const tasks = try database.listTasks(allocator, story_id, maintenance_only, status_filter);
    defer allocator.free(tasks);
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(tasks);
    try stdout.writeAll("\n");
}

fn handleTaskMove(_: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts task move <id> --to <story-id>\n", .{});
        std.process.exit(1);
    }
    const task_id = args[0];
    var to_story: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--to") and i + 1 < args.len) {
            to_story = args[i + 1];
            i += 1;
        }
    }

    if (to_story == null) {
        std.debug.print("Error: --to <story-id> is required\n", .{});
        std.process.exit(1);
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    database.moveTask(task_id, to_story.?) catch |err| {
        switch (err) {
            error.CannotMoveDoneTask => {
                std.debug.print("Error: Cannot move DONE tasks\n", .{});
                std.process.exit(1);
            },
            error.TaskNotFound => {
                std.debug.print("Error: Task {s} not found\n", .{task_id});
                std.process.exit(1);
            },
            else => {
                std.debug.print("Error: {}\n", .{err});
                std.process.exit(1);
            },
        }
    };

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Task {s} moved to story {s}\n", .{ task_id, to_story.? });
}

// ============================================================
// Review (enhanced HRE)
// ============================================================

fn handleReview(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts review <task-id>\n", .{});
        std.process.exit(1);
    }
    const task_id = args[0];

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    // Verify task exists
    _ = database.getTask(allocator, task_id) catch |err| {
        if (err == error.TaskNotFound) {
            std.debug.print("Error: Task {s} not found\n", .{task_id});
            std.process.exit(1);
        }
        std.debug.print("Error: {}\n", .{err});
        std.process.exit(1);
    };

    const review = @import("review.zig");
    review.run(allocator, &database, task_id) catch |err| {
        std.debug.print("Error during review: {}\n", .{err});
        std.process.exit(1);
    };
}

// ============================================================
// Approve / Reject
// ============================================================

fn handleApprove(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts approve <task-id>\n", .{});
        std.process.exit(1);
    }
    const task_id = args[0];

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const user = std.process.getEnvVarOwned(allocator, "USER") catch blk: {
        break :blk try allocator.dupe(u8, "developer");
    };
    defer allocator.free(user);

    try database.addGate(task_id, "task-review", "approved", user);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Task-review gate approved for {s} by {s}.\n", .{ task_id, user });
}

fn handleReject(_: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts reject <task-id>\n", .{});
        std.process.exit(1);
    }
    const task_id = args[0];

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    try database.addGate(task_id, "task-review", "changes_requested", null);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Changes requested for {s}. Gate marked as 'changes_requested'.\n", .{task_id});
}

// ============================================================
// Gate
// ============================================================

fn handleGate(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("Usage: acts gate <add|list> [options]\n", .{});
        std.process.exit(1);
    }

    const subcommand = args[0];
    var task_id: ?[]const u8 = null;
    var gate_type: ?[]const u8 = null;
    var status: ?[]const u8 = null;
    var approved_by: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--task") and i + 1 < args.len) {
            task_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--type") and i + 1 < args.len) {
            gate_type = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--status") and i + 1 < args.len) {
            status = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--by") and i + 1 < args.len) {
            approved_by = args[i + 1];
            i += 1;
        }
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    if (std.mem.eql(u8, subcommand, "add")) {
        if (task_id == null or gate_type == null or status == null) {
            std.debug.print("Usage: acts gate add --task <id> --type <type> --status <status> [--by <name>]\n", .{});
            std.process.exit(1);
        }

        // Enforce human developer approval for task-review gates
        if (std.mem.eql(u8, gate_type.?, "task-review")) {
            if (approved_by == null or approved_by.?.len == 0) {
                std.debug.print("Error: task-review gates MUST be approved by a human developer.\n", .{});
                std.debug.print("Usage: acts gate add --task {s} --type task-review --status approved --by \"<human-developer-name>\"\n", .{task_id.?});
                std.process.exit(1);
            }

            const blocked_names = [_][]const u8{ "agent", "ai", "claude", "cursor", "copilot", "gpt", "assistant", "opencode", "model" };
            const lower_name = try std.ascii.allocLowerString(allocator, approved_by.?);
            defer allocator.free(lower_name);

            for (blocked_names) |blocked| {
                if (std.mem.indexOf(u8, lower_name, blocked) != null) {
                    std.debug.print("Error: '{s}' appears to be an agent name. task-review gates MUST be approved by a human developer.\n", .{approved_by.?});
                    std.process.exit(1);
                }
            }
        }

        try database.addGate(task_id.?, gate_type.?, status.?, approved_by);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        if (task_id == null) {
            std.debug.print("Usage: acts gate list --task <id>\n", .{});
            std.process.exit(1);
        }
        const gates = try database.listGates(allocator, task_id.?);
        defer allocator.free(gates);
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(gates);
        try stdout.writeAll("\n");
    } else {
        std.debug.print("Unknown gate subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}

// ============================================================
// Decision
// ============================================================

fn handleDecision(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts decision <add|list> [options]\n", .{});
        std.process.exit(1);
    }

    const subcommand = args[0];
    var task_id: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--task") and i + 1 < args.len) {
            task_id = args[i + 1];
            i += 1;
        }
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    if (std.mem.eql(u8, subcommand, "add")) {
        const stdin = std.io.getStdIn().reader();
        const input = try stdin.readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(input);
        try database.addDecision(allocator, input);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        if (task_id == null) {
            std.debug.print("Usage: acts decision list --task <id>\n", .{});
            std.process.exit(1);
        }
        const decisions = try database.listDecisions(allocator, task_id.?);
        defer allocator.free(decisions);
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(decisions);
        try stdout.writeAll("\n");
    } else {
        std.debug.print("Unknown decision subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}

// ============================================================
// Approach
// ============================================================

fn handleApproach(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2 or !std.mem.eql(u8, args[0], "add") or !std.mem.eql(u8, args[1], "--rejected")) {
        std.debug.print("Usage: acts approach add --rejected (reads JSON from stdin)\n", .{});
        std.process.exit(1);
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const stdin = std.io.getStdIn().reader();
    const input = try stdin.readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(input);
    try database.addRejectedApproach(allocator, input);
}

// ============================================================
// Question
// ============================================================

fn handleQuestion(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts question <add|resolve> [options]\n", .{});
        std.process.exit(1);
    }

    const subcommand = args[0];

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    if (std.mem.eql(u8, subcommand, "add")) {
        const stdin = std.io.getStdIn().reader();
        const input = try stdin.readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(input);
        try database.addQuestion(allocator, input);
    } else if (std.mem.eql(u8, subcommand, "resolve")) {
        if (args.len < 2) {
            std.debug.print("Usage: acts question resolve <id> [--resolution \"...\"] [--by <name>]\n", .{});
            std.process.exit(1);
        }
        const question_id = args[1];
        var resolution: ?[]const u8 = null;
        var resolved_by: ?[]const u8 = null;

        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--resolution") and i + 1 < args.len) {
                resolution = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--by") and i + 1 < args.len) {
                resolved_by = args[i + 1];
                i += 1;
            }
        }
        try database.resolveQuestion(question_id, resolution, resolved_by);
    } else {
        std.debug.print("Unknown question subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}

// ============================================================
// Ownership / Scope
// ============================================================

fn handleOwnership(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1 or !std.mem.eql(u8, args[0], "map")) {
        std.debug.print("Usage: acts ownership map\n", .{});
        std.process.exit(1);
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const map = try database.getOwnershipMap(allocator);
    defer allocator.free(map);
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(map);
    try stdout.writeAll("\n");
}

fn handleScope(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 4) {
        std.debug.print("Usage: acts scope check --task <id> --file <path>\n", .{});
        std.process.exit(1);
    }

    var task_id: ?[]const u8 = null;
    var file_path: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--task") and i + 1 < args.len) {
            task_id = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--file") and i + 1 < args.len) {
            file_path = args[i + 1];
            i += 1;
        }
    }

    if (task_id == null or file_path == null) {
        std.debug.print("Usage: acts scope check --task <id> --file <path>\n", .{});
        std.process.exit(1);
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const result = try database.checkScope(allocator, task_id.?, file_path.?);
    defer allocator.free(result);
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(result);
    try stdout.writeAll("\n");
}

// ============================================================
// Session
// ============================================================

fn handleSession(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("Usage: acts session <parse|validate|list> [options]\n", .{});
        std.process.exit(1);
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "parse")) {
        if (args.len < 2) {
            std.debug.print("Usage: acts session parse <file.md>\n", .{});
            std.process.exit(1);
        }
        const sessions = @import("sessions.zig");
        const result = try sessions.parseFile(allocator, args[1]);
        defer allocator.free(result);
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(result);
        try stdout.writeAll("\n");
    } else if (std.mem.eql(u8, subcommand, "validate")) {
        if (args.len < 2) {
            std.debug.print("Usage: acts session validate <file.md>\n", .{});
            std.process.exit(1);
        }
        const sessions = @import("sessions.zig");
        const valid = try sessions.validateFile(allocator, args[1]);
        if (!valid) {
            std.process.exit(1);
        }
    } else if (std.mem.eql(u8, subcommand, "list")) {
        var task_id: ?[]const u8 = null;
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--task") and i + 1 < args.len) {
                task_id = args[i + 1];
                i += 1;
            }
        }
        if (task_id == null) {
            std.debug.print("Usage: acts session list --task <id>\n", .{});
            std.process.exit(1);
        }
        const sessions = @import("sessions.zig");
        const result = try sessions.listSessions(allocator, task_id.?);
        defer allocator.free(result);
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(result);
        try stdout.writeAll("\n");
    } else {
        std.debug.print("Unknown session subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}

// ============================================================
// Operation
// ============================================================

fn handleOperation(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts operation <log|list|show> [options]\n", .{});
        std.process.exit(1);
    }

    const subcommand = args[0];

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const stdout = std.io.getStdOut().writer();

    if (std.mem.eql(u8, subcommand, "log")) {
        var operation_id: ?[]const u8 = null;
        var task_id: ?[]const u8 = null;

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--id") and i + 1 < args.len) {
                operation_id = args[i + 1];
                i += 1;
            } else if (std.mem.eql(u8, args[i], "--task") and i + 1 < args.len) {
                task_id = args[i + 1];
                i += 1;
            }
        }

        if (operation_id == null) {
            std.debug.print("Usage: acts operation log --id <operation-id> [--task <task-id>]\n", .{});
            std.process.exit(1);
        }

        const stdin = std.io.getStdIn().reader();
        const input = try stdin.readAllAlloc(allocator, 1024 * 1024);
        defer allocator.free(input);
        try database.logOperation(allocator, operation_id.?, task_id, input);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        var task_id: ?[]const u8 = null;

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--task") and i + 1 < args.len) {
                task_id = args[i + 1];
                i += 1;
            }
        }

        const ops = try database.listOperations(allocator, task_id);
        defer allocator.free(ops);
        try stdout.writeAll(ops);
        try stdout.writeAll("\n");
    } else if (std.mem.eql(u8, subcommand, "show")) {
        if (args.len < 2) {
            std.debug.print("Usage: acts operation show <operation-id>\n", .{});
            std.process.exit(1);
        }
        const operation_id = args[1];
        const op = try database.getOperation(allocator, operation_id);
        defer allocator.free(op);
        try stdout.writeAll(op);
        try stdout.writeAll("\n");
    } else {
        std.debug.print("Unknown operation subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}

// ============================================================
// Validate
// ============================================================

fn handleValidate(_allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = _allocator;
    _ = args;
    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    var valid = true;

    const version = blk: {
        break :blk database.getSchemaVersion() catch |err| {
            try stderr.print("Schema version check failed: {}\n", .{err});
            valid = false;
            break :blk 0;
        };
    };
    if (valid) {
        try stdout.print("Schema version: {d}\n", .{version});
    }

    const required_files = [_][]const u8{ ".story/plan.md", ".story/spec.md" };
    for (required_files) |file| {
        var file_exists = true;
        std.fs.cwd().access(file, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                file_exists = false;
            },
            else => return err,
        };
        if (!file_exists) {
            try stderr.print("Missing required file: {s}\n", .{file});
            valid = false;
        } else {
            try stdout.print("Found: {s}\n", .{file});
        }
    }

    var sessions_dir: ?std.fs.Dir = null;
    sessions_dir = std.fs.cwd().openDir(".story/sessions", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => blk: {
            try stderr.writeAll("No sessions directory found\n");
            break :blk null;
        },
        else => return err,
    };

    if (sessions_dir) |dir| {
        var iter = dir.iterate();
        var session_count: usize = 0;
        while (try iter.next()) |entry| {
            if (std.mem.endsWith(u8, entry.name, ".md")) {
                session_count += 1;
            }
        }
        try stdout.print("Session files: {d}\n", .{session_count});
    }

    if (!valid) {
        try stderr.writeAll("\nValidation FAILED\n");
        std.process.exit(1);
    } else {
        try stdout.writeAll("\nValidation PASSED\n");
    }
}

// ============================================================
// Migrate
// ============================================================

fn handleMigrate(_: std.mem.Allocator, _: []const []const u8) !void {
    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();

    try database.migrate();

    const version = try database.getSchemaVersion();
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Migration complete. Schema version: {d}\n", .{version});
}

// ============================================================
// Story (create, list, switch, archive, merge, graph)
// ============================================================

fn handleStory(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts story <create|list|switch|archive|merge|graph> ...\n", .{});
        std.process.exit(1);
    }

    const subcommand = args[0];

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    if (std.mem.eql(u8, subcommand, "create")) {
        try handleStoryCreate(allocator, &database, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "list")) {
        try handleStoryList(allocator, &database, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "switch")) {
        try handleStorySwitch(allocator, &database, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "archive")) {
        try handleStoryArchive(allocator, &database, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "merge")) {
        try handleStoryMerge(allocator, &database, args[1..]);
    } else if (std.mem.eql(u8, subcommand, "graph")) {
        try handleStoryGraph(allocator, &database, args[1..]);
    } else {
        std.debug.print("Unknown story subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}

fn handleStoryCreate(allocator: std.mem.Allocator, database: *db.Database, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts story create <id> --title \"...\" [--from <branch>] [--parent <story-id>]\n", .{});
        std.process.exit(1);
    }
    const story_id = args[0];
    var title: ?[]const u8 = null;
    var from_branch: ?[]const u8 = null;
    var parent_story: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--title") and i + 1 < args.len) {
            title = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--from") and i + 1 < args.len) {
            from_branch = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--parent") and i + 1 < args.len) {
            parent_story = args[i + 1];
            i += 1;
        }
    }

    if (title == null) {
        std.debug.print("Error: --title is required\n", .{});
        std.process.exit(1);
    }

    const branch = from_branch orelse "main";
    const worktree_path = try std.fs.path.join(allocator, &[_][]const u8{ ".acts", "worktrees", story_id });
    defer allocator.free(worktree_path);

    // Create git worktree
    var wt_argv = [_][]const u8{ "git", "worktree", "add", worktree_path, "-b", story_id, branch };
    var wt_child = std.process.Child.init(&wt_argv, allocator);
    wt_child.stdin_behavior = .Ignore;
    wt_child.stdout_behavior = .Pipe;
    wt_child.stderr_behavior = .Pipe;
    const wt_result = wt_child.spawnAndWait() catch |err| {
        std.debug.print("Error: Could not create git worktree: {}\n", .{err});
        std.process.exit(1);
    };
    if (wt_result.Exited != 0) {
        std.debug.print("Error: git worktree add failed (exit {d})\n", .{wt_result.Exited});
        std.process.exit(1);
    }

    // Create .story scaffold inside worktree
    const story_dir = try std.fs.path.join(allocator, &[_][]const u8{ worktree_path, ".story" });
    defer allocator.free(story_dir);
    try std.fs.cwd().makePath(story_dir);
    const sessions_dir = try std.fs.path.join(allocator, &[_][]const u8{ story_dir, "sessions" });
    defer allocator.free(sessions_dir);
    try std.fs.cwd().makePath(sessions_dir);
    const tasks_dir = try std.fs.path.join(allocator, &[_][]const u8{ story_dir, "tasks" });
    defer allocator.free(tasks_dir);
    try std.fs.cwd().makePath(tasks_dir);

    const plan_path = try std.fs.path.join(allocator, &[_][]const u8{ story_dir, "plan.md" });
    defer allocator.free(plan_path);
    const plan_file = try std.fs.cwd().createFile(plan_path, .{});
    defer plan_file.close();
    try plan_file.writeAll("# Plan\n\n## Overview\n\n[Story overview]\n\n## Tasks\n\n");

    const spec_path = try std.fs.path.join(allocator, &[_][]const u8{ story_dir, "spec.md" });
    defer allocator.free(spec_path);
    const spec_file = try std.fs.cwd().createFile(spec_path, .{});
    defer spec_file.close();
    try spec_file.writeAll("# Specification\n\n## Overview\n\n[Story specification]\n\n## Acceptance Criteria\n\n");

    // Create .acts/current symlink
    std.fs.cwd().deleteFile(".acts/current") catch {};
    try std.fs.symLinkAbsolute(worktree_path, ".acts/current", .{});

    // Insert into DB
    try database.createStory(story_id, title.?, branch, worktree_path, parent_story);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Story {s} created\n", .{story_id});
    try stdout.print("  Worktree: {s}\n", .{worktree_path});
    try stdout.print("  Branch: story/{s}\n", .{story_id});
    try stdout.writeAll("  Switched to this story\n");
}

fn handleStoryList(allocator: std.mem.Allocator, database: *db.Database, args: []const []const u8) !void {
    var include_archived = false;
    var include_maintenance = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--include-archived")) {
            include_archived = true;
        } else if (std.mem.eql(u8, args[i], "--include-maintenance")) {
            include_maintenance = true;
        }
    }

    const stories = try database.listStories(allocator, include_archived, include_maintenance);
    defer allocator.free(stories);
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(stories);
    try stdout.writeAll("\n");
}

fn handleStorySwitch(allocator: std.mem.Allocator, database: *db.Database, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts story switch <id>\n", .{});
        std.process.exit(1);
    }
    const story_id = args[0];

    database.switchStory(story_id) catch |err| {
        switch (err) {
            error.StoryArchived => {
                std.debug.print("Error: Story {s} is archived\n", .{story_id});
                std.process.exit(1);
            },
            error.StoryNotFound => {
                std.debug.print("Error: Story {s} not found\n", .{story_id});
                std.process.exit(1);
            },
            else => {
                std.debug.print("Error: {}\n", .{err});
                std.process.exit(1);
            },
        }
    };

    // Update symlink
    const worktree_path = try std.fs.path.join(allocator, &[_][]const u8{ ".acts", "worktrees", story_id });
    defer allocator.free(worktree_path);
    std.fs.cwd().deleteFile(".acts/current") catch {};
    std.fs.symLinkAbsolute(worktree_path, ".acts/current", .{}) catch {};

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Switched to story {s}\n", .{story_id});
}

fn handleStoryArchive(allocator: std.mem.Allocator, database: *db.Database, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts story archive <id>\n", .{});
        std.process.exit(1);
    }
    const story_id = args[0];

    database.archiveStory(story_id) catch |err| {
        switch (err) {
            error.OpenTasksRemain => {
                std.debug.print("Error: Story {s} has open tasks. Complete all tasks first.\n", .{story_id});
                std.process.exit(1);
            },
            else => {
                std.debug.print("Error: {}\n", .{err});
                std.process.exit(1);
            },
        }
    };

    // Remove worktree and branch
    const worktree_path = try std.fs.path.join(allocator, &[_][]const u8{ ".acts", "worktrees", story_id });
    defer allocator.free(worktree_path);

    var rm_argv = [_][]const u8{ "git", "worktree", "remove", worktree_path };
    var rm_child = std.process.Child.init(&rm_argv, allocator);
    _ = rm_child.spawnAndWait() catch {};

    var branch_argv = [_][]const u8{ "git", "branch", "-D", story_id };
    var branch_child = std.process.Child.init(&branch_argv, allocator);
    _ = branch_child.spawnAndWait() catch {};

    // Remove symlink if pointing to this story
    std.fs.cwd().deleteFile(".acts/current") catch {};

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Story {s} archived\n", .{story_id});
}

fn handleStoryMerge(allocator: std.mem.Allocator, database: *db.Database, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts story merge <id> --into <branch> [--semver <version>]\n", .{});
        std.process.exit(1);
    }
    const story_id = args[0];
    var into_branch: ?[]const u8 = null;
    var semver_override: ?[]const u8 = null;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--into") and i + 1 < args.len) {
            into_branch = args[i + 1];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--semver") and i + 1 < args.len) {
            semver_override = args[i + 1];
            i += 1;
        }
    }

    const target = into_branch orelse "main";

    // Trigger will enforce: all tasks DONE, all reviews approved
    var stmt: ?*c.sqlite3_stmt = null;
    const sql = "UPDATE stories SET status = 'MERGED' WHERE id = ?";
    const rc = c.sqlite3_prepare_v2(database.db, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        std.debug.print("Error: Could not prepare merge statement\n", .{});
        std.process.exit(1);
    }
    defer _ = c.sqlite3_finalize(stmt);
    _ = c.sqlite3_bind_text(stmt, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);

    const step_rc = c.sqlite3_step(stmt);
    if (step_rc != c.SQLITE_DONE) {
        const err = c.sqlite3_errmsg(database.db);
        std.debug.print("Merge failed: {s}\n", .{err});
        std.process.exit(1);
    }

    // Merge git branch
    const merge_msg = try std.fmt.allocPrint(allocator, "Merge story: {s}", .{story_id});
    defer allocator.free(merge_msg);
    var merge_argv = [_][]const u8{ "git", "merge", story_id, "-m", merge_msg };
    var merge_child = std.process.Child.init(&merge_argv, allocator);
    merge_child.stdin_behavior = .Ignore;
    merge_child.stdout_behavior = .Inherit;
    merge_child.stderr_behavior = .Inherit;
    merge_child.spawn() catch {};
    _ = merge_child.wait() catch {};

    const stdout = std.io.getStdOut().writer();
    try stdout.print("Story {s} merged into {s}\n", .{ story_id, target });
}

fn handleStoryGraph(allocator: std.mem.Allocator, database: *db.Database, args: []const []const u8) !void {
    var format: []const u8 = "json";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--format") and i + 1 < args.len) {
            format = args[i + 1];
            i += 1;
        }
    }

    const graph = try database.getStoryGraph(allocator, format);
    defer allocator.free(graph);
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(graph);
    try stdout.writeAll("\n");
}

// ============================================================
// DB (checkpoint, status)
// ============================================================

fn handleDb(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts db <checkpoint|status>\n", .{});
        std.process.exit(1);
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();

    const subcommand = args[0];
    const stdout = std.io.getStdOut().writer();

    if (std.mem.eql(u8, subcommand, "checkpoint")) {
        const result = database.walCheckpoint() catch |err| {
            std.debug.print("Checkpoint failed: {}\n", .{err});
            std.process.exit(1);
        };
        try stdout.print("WAL checkpoint complete: {d} pages logged, {d} pages checkpointed\n", .{ result.pages_log, result.pages_ckpt });
    } else if (std.mem.eql(u8, subcommand, "status")) {
        const status = try database.walStatus(allocator);
        defer allocator.free(status);
        try stdout.writeAll(status);
        try stdout.writeAll("\n");
    } else {
        std.debug.print("Unknown db subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}

// ============================================================
// Presence
// ============================================================

fn handlePresence(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts presence <set|list> ...\n", .{});
        std.process.exit(1);
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "set")) {
        var agent_id: ?[]const u8 = null;
        var task_id: ?[]const u8 = null;
        var action: ?[]const u8 = null;
        var story_id: ?[]const u8 = null;

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--agent") and i + 1 < args.len) { agent_id = args[i + 1]; i += 1; }
            else if (std.mem.eql(u8, args[i], "--task") and i + 1 < args.len) { task_id = args[i + 1]; i += 1; }
            else if (std.mem.eql(u8, args[i], "--action") and i + 1 < args.len) { action = args[i + 1]; i += 1; }
            else if (std.mem.eql(u8, args[i], "--story") and i + 1 < args.len) { story_id = args[i + 1]; i += 1; }
        }

        if (agent_id == null) {
            std.debug.print("Error: --agent is required\n", .{});
            std.process.exit(1);
        }

        try database.setPresence(agent_id.?, story_id, task_id, action);
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Presence set for {s}\n", .{agent_id.?});
    } else if (std.mem.eql(u8, subcommand, "list")) {
        var story_id: ?[]const u8 = null;
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--story") and i + 1 < args.len) { story_id = args[i + 1]; i += 1; }
        }
        const presence = try database.listPresence(allocator, story_id);
        defer allocator.free(presence);
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(presence);
        try stdout.writeAll("\n");
    } else {
        std.debug.print("Unknown presence subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}

// ============================================================
// Unblock
// ============================================================

fn handleUnblock(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts unblock <list|ack> ...\n", .{});
        std.process.exit(1);
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "list")) {
        var acknowledged = false;
        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--acknowledged")) acknowledged = true;
        }
        const events = try database.listUnblockEvents(allocator, acknowledged);
        defer allocator.free(events);
        const stdout = std.io.getStdOut().writer();
        try stdout.writeAll(events);
        try stdout.writeAll("\n");
    } else if (std.mem.eql(u8, subcommand, "ack")) {
        if (args.len < 2) {
            std.debug.print("Usage: acts unblock ack <id>\n", .{});
            std.process.exit(1);
        }
        const event_id = try std.fmt.parseInt(i32, args[1], 10);
        try database.ackUnblockEvent(event_id);
        const stdout = std.io.getStdOut().writer();
        try stdout.print("Unblock event {d} acknowledged\n", .{event_id});
    } else {
        std.debug.print("Unknown unblock subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}

// ============================================================
// Review Queue
// ============================================================

fn handleReviewQueue(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var story_id: ?[]const u8 = null;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--story") and i + 1 < args.len) { story_id = args[i + 1]; i += 1; }
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const queue = try database.listReviewQueue(allocator, story_id);
    defer allocator.free(queue);
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(queue);
    try stdout.writeAll("\n");
}

// ============================================================
// Gate SLA
// ============================================================

fn handleGateSla(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var breached_only = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--breached")) breached_only = true;
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const sla = try database.listGateSla(allocator, breached_only);
    defer allocator.free(sla);
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(sla);
    try stdout.writeAll("\n");
}

// ============================================================
// Changelog
// ============================================================

fn handleChangelog(allocator: std.mem.Allocator, args: []const []const u8) !void {
    var story_id: ?[]const u8 = null;
    var format: []const u8 = "md";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--story") and i + 1 < args.len) { story_id = args[i + 1]; i += 1; }
        else if (std.mem.eql(u8, args[i], "--format") and i + 1 < args.len) { format = args[i + 1]; i += 1; }
    }

    if (story_id == null) {
        std.debug.print("Usage: acts changelog --story <id> [--format md|json]\n", .{});
        std.process.exit(1);
    }

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    const changelog = try database.generateChangelog(allocator, story_id.?, format);
    defer allocator.free(changelog);
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(changelog);
    try stdout.writeAll("\n");
}

// ============================================================
// Override (human-only file override requests)
// ============================================================

fn handleOverride(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts override <request|approve|reject|list> [options]\n", .{});
        std.process.exit(1);
    }

    const subcommand = args[0];

    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();

    // Expire stale overrides first
    database.expireOverrides() catch {};

    const stdout = std.io.getStdOut().writer();

    if (std.mem.eql(u8, subcommand, "request")) {
        var file_path: ?[]const u8 = null;
        var task_id: ?[]const u8 = null;
        var reason: ?[]const u8 = null;

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--file") and i + 1 < args.len) { file_path = args[i + 1]; i += 1; }
            else if (std.mem.eql(u8, args[i], "--task") and i + 1 < args.len) { task_id = args[i + 1]; i += 1; }
            else if (std.mem.eql(u8, args[i], "--reason") and i + 1 < args.len) { reason = args[i + 1]; i += 1; }
        }

        if (file_path == null or task_id == null or reason == null) {
            std.debug.print("Usage: acts override request --file <path> --task <id> --reason \"...\"\n", .{});
            std.process.exit(1);
        }

        const override_id = try database.requestOverride(file_path.?, task_id.?, reason.?);
        try stdout.print("Override request #{d} created for {s} (task {s})\n", .{ override_id, file_path.?, task_id.? });
        try stdout.writeAll("Waiting for human approval: acts override approve <id> --by \"<human-name>\"\n");

    } else if (std.mem.eql(u8, subcommand, "approve")) {
        if (args.len < 2) {
            std.debug.print("Usage: acts override approve <id> --by \"<human-name>\"\n", .{});
            std.process.exit(1);
        }
        const override_id = try std.fmt.parseInt(i32, args[1], 10);
        var approved_by: ?[]const u8 = null;

        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--by") and i + 1 < args.len) { approved_by = args[i + 1]; i += 1; }
        }

        if (approved_by == null or approved_by.?.len == 0) {
            std.debug.print("Error: --by <human-name> is required. Only humans can approve overrides.\n", .{});
            std.process.exit(1);
        }

        // Block agent names
        const blocked_names = [_][]const u8{ "agent", "ai", "claude", "cursor", "copilot", "gpt", "assistant", "opencode", "model" };
        const lower_name = try std.ascii.allocLowerString(allocator, approved_by.?);
        defer allocator.free(lower_name);

        for (blocked_names) |blocked| {
            if (std.mem.indexOf(u8, lower_name, blocked) != null) {
                std.debug.print("Error: '{s}' appears to be an agent name. Only humans can approve overrides.\n", .{approved_by.?});
                std.process.exit(1);
            }
        }

        database.approveOverride(override_id, approved_by.?) catch |err| {
            switch (err) {
                error.UpdateFailed => {
                    std.debug.print("Error: Override #{d} not found or already processed\n", .{override_id});
                    std.process.exit(1);
                },
                else => {
                    std.debug.print("Error: {}\n", .{err});
                    std.process.exit(1);
                },
            }
        };

        try stdout.print("Override #{d} approved by {s}\n", .{ override_id, approved_by.? });

    } else if (std.mem.eql(u8, subcommand, "reject")) {
        if (args.len < 2) {
            std.debug.print("Usage: acts override reject <id>\n", .{});
            std.process.exit(1);
        }
        const override_id = try std.fmt.parseInt(i32, args[1], 10);

        database.rejectOverride(override_id) catch |err| {
            switch (err) {
                error.UpdateFailed => {
                    std.debug.print("Error: Override #{d} not found or already processed\n", .{override_id});
                    std.process.exit(1);
                },
                else => {
                    std.debug.print("Error: {}\n", .{err});
                    std.process.exit(1);
                },
            }
        };

        try stdout.print("Override #{d} rejected\n", .{override_id});

    } else if (std.mem.eql(u8, subcommand, "list")) {
        var pending_only = false;

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--pending")) pending_only = true;
        }

        const overrides = try database.listOverrides(allocator, pending_only);
        defer db.Database.freeOverrides(allocator, overrides);

        if (overrides.len == 0) {
            try stdout.writeAll("No override requests.\n");
            return;
        }

        try stdout.print("{s}{s:<6} {s:<30} {s:<10} {s:<12} {s:<12} {s:<24}{s}\n", .{
            "\x1b[1m", "ID", "File", "Task", "Status", "Approved By", "Expires", "\x1b[0m",
        });
        try stdout.writeAll("────────────────────────────────────────────────────────────────────────────────────────────\n");

        for (overrides) |o| {
            const approved = if (o.approved_by) |ab| ab else "-";
            try stdout.print("{d:<6} {s:<30} {s:<10} {s:<12} {s:<12} {s:<24}\n", .{
                o.id, o.file_path, o.task_id, o.status, approved, o.expires_at,
            });
        }
    } else {
        std.debug.print("Unknown override subcommand: {s}\n", .{subcommand});
        std.process.exit(1);
    }
}
