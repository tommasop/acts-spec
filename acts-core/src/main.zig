const std = @import("std");
const cli = @import("cli.zig");
const db = @import("db.zig");

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
        \\ACTS Core v1.0.0 - Agent Collaborative Tracking Standard
        \\
        \\Usage: acts <command> [options]
        \\
        \\Commands:
        \\  init <story-id>              Initialize a new ACTS story
        \\  state read [--story <id>]    Read story state as JSON
        \\  state write --story <id>     Write story state from stdin JSON
        \\  task get <task-id>           Get task details as JSON
        \\  task update <task-id>        Update task status
        \\    --status <status>            Set status (TODO/IN_PROGRESS/BLOCKED/DONE)
        \\    --assigned-to <name>         Set assignee
        \\  gate add --task <id>         Add gate checkpoint
        \\    --type <type>                Gate type (approve/task-review/commit-review/architecture-discuss)
        \\    --status <status>            Status (pending/approved/changes_requested)
        \\    --by <name>                  Who approved
        \\  gate list --task <id>        List gate checkpoints for task
        \\  decision add                 Record decision from stdin JSON
        \\  decision list --task <id>    List decisions for task
        \\  approach add --rejected      Record rejected approach from stdin JSON
        \\  question add                 Add open question from stdin JSON
        \\  question resolve <id>        Resolve open question
        \\  ownership map                Show file ownership map as JSON
        \\  scope check --task <id>      Check if file is in scope
        \\    --file <path>                File path to check
        \\  session parse <file.md>      Parse session markdown to JSON
        \\  session validate <file.md>   Validate session markdown
        \\  session list --task <id>     List and parse sessions for task
        \\  operation log --id <op>      Log operation from stdin JSON
        \\  validate                     Validate entire ACTS project
        \\  migrate                      Force schema migration
        \\  help                         Show this help
        \\
    );
}

fn handleInit(_allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = _allocator;
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

    // Create directory structure first
    try std.fs.cwd().makePath(".acts");
    try std.fs.cwd().makePath(".story/sessions");
    try std.fs.cwd().makePath(".story/tasks");
    
    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    
    try database.migrate();
    try database.initStory(story_id, title orelse story_id);
    
    // Create plan.md template
    const plan_file = try std.fs.cwd().createFile(".story/plan.md", .{});
    defer plan_file.close();
    try plan_file.writeAll("# Plan\n\n## Overview\n\n[Story overview]\n\n## Tasks\n\n");
    
    // Create spec.md template
    const spec_file = try std.fs.cwd().createFile(".story/spec.md", .{});
    defer spec_file.close();
    try spec_file.writeAll("# Specification\n\n## Overview\n\n[Story specification]\n\n## Acceptance Criteria\n\n");
    
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Initialized ACTS story: {s}\n", .{story_id});
    try stdout.print("Database: {s}\n", .{db_path});
    try stdout.writeAll("Created: .story/plan.md, .story/spec.md, .story/sessions/\n");
}

fn handleState(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: acts state <read|write> [options]\n", .{});
        std.process.exit(1);
    }
    
    const subcommand = args[0];
    var story_id: ?[]const u8 = null;
    
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--story") and i + 1 < args.len) {
            story_id = args[i + 1];
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
        try stdout.writeAll(state);
        try stdout.writeAll("\n");
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

fn handleTask(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("Usage: acts task <get|update> <task-id> [options]\n", .{});
        std.process.exit(1);
    }
    
    const subcommand = args[0];
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

fn handleOperation(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2 or !std.mem.eql(u8, args[0], "log")) {
        std.debug.print("Usage: acts operation log --id <operation-id> [--task <task-id>] (reads JSON from stdin)\n", .{});
        std.process.exit(1);
    }
    
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
    
    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    try database.migrate();
    
    const stdin = std.io.getStdIn().reader();
    const input = try stdin.readAllAlloc(allocator, 1024 * 1024);
    defer allocator.free(input);
    try database.logOperation(allocator, operation_id.?, task_id, input);
}

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
    
    // Check schema version
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
    
    // Check required files exist
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
    
    // Validate all session files
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

fn handleMigrate(_allocator: std.mem.Allocator, args: []const []const u8) !void {
    _ = _allocator;
    _ = args;
    const db_path = ".acts/acts.db";
    var database = try db.Database.open(db_path);
    defer database.close();
    
    const stdout = std.io.getStdOut().writer();
    const version_before = database.getSchemaVersion() catch 0;
    try stdout.print("Schema version before: {d}\n", .{version_before});
    
    try database.migrate();
    
    const version_after = database.getSchemaVersion() catch 0;
    try stdout.print("Schema version after: {d}\n", .{version_after});
    
    if (version_after > version_before) {
        try stdout.writeAll("Migration completed\n");
    } else {
        try stdout.writeAll("No migration needed\n");
    }
}
