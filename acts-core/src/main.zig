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
        \\  operation list [--task <id>] List logged operations
        \\  operation show <id>          Show operation details
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

// Review provider configuration
const ReviewCommand = struct {
    cmd: []const u8,
    args: []const []const u8,
    behavior: []const u8,
};

fn loadReviewProvider(allocator: std.mem.Allocator) !?[]const u8 {
    const acts_json_path = ".acts/acts.json";
    const file = std.fs.cwd().openFile(acts_json_path, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const obj = parsed.value.object;

    if (obj.get("review_provider")) |provider| {
        if (provider == .string) {
            return try allocator.dupe(u8, provider.string);
        }
    }
    return null;
}

fn loadReviewCommand(allocator: std.mem.Allocator, provider_name: []const u8) !?ReviewCommand {
    const filename = try std.mem.concat(allocator, u8, &[_][]const u8{ provider_name, ".json" });
    defer allocator.free(filename);
    const provider_path = try std.fs.path.join(allocator, &[_][]const u8{ ".acts", "review-providers", filename });
    defer allocator.free(provider_path);

    const file = std.fs.cwd().openFile(provider_path, .{}) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();

    if (parsed.value != .object) return null;
    const obj = parsed.value.object;

    // Look for commands in priority order: review > run > serve
    const commands = obj.get("commands") orelse return null;
    if (commands != .object) return null;
    const cmds = commands.object;

    var selected_cmd: ?std.json.ObjectMap = null;
    for ([_][]const u8{ "review", "run", "serve" }) |cmd_name| {
        if (cmds.get(cmd_name)) |cmd| {
            if (cmd == .object) {
                selected_cmd = cmd.object;
                break;
            }
        }
    }

    const cmd_obj = selected_cmd orelse return null;

    const cmd_field = cmd_obj.get("cmd") orelse return null;
    if (cmd_field != .string) return null;

    // Load behavior (default: background)
    var behavior: []const u8 = try allocator.dupe(u8, "background");
    errdefer allocator.free(behavior);
    if (cmd_obj.get("behavior")) |b| {
        if (b == .string) {
            allocator.free(behavior);
            behavior = try allocator.dupe(u8, b.string);
        }
    }

    // Load options for template substitution
    var options: std.json.ObjectMap = undefined;
    var has_options = false;
    if (cmd_obj.get("options")) |opts| {
        if (opts == .object) {
            options = opts.object;
            has_options = true;
        }
    }

    var arg_list = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (arg_list.items) |item| allocator.free(item);
        arg_list.deinit();
    }

    if (cmd_obj.get("args")) |args_field| {
        if (args_field == .array) {
            for (args_field.array.items) |arg| {
                if (arg == .string) {
                    var arg_str = try allocator.dupe(u8, arg.string);
                    
                    // Substitute template variables with defaults from options
                    if (has_options) {
                        var iter = options.iterator();
                        while (iter.next()) |entry| {
                            const placeholder = try std.mem.concat(allocator, u8, &[_][]const u8{ "{", entry.key_ptr.*, "}" });
                            defer allocator.free(placeholder);
                            
                            if (std.mem.indexOf(u8, arg_str, placeholder)) |_| {
                                // Get default value from options
                                if (entry.value_ptr.* == .object) {
                                    const opt_obj = entry.value_ptr.*.object;
                                    if (opt_obj.get("default")) |default_val| {
                                        var default_str: []const u8 = "";
                                        switch (default_val) {
                                            .string => |s| default_str = s,
                                            .integer => |n| {
                                                const buf = try allocator.alloc(u8, 32);
                                                const len = std.fmt.formatIntBuf(buf, n, 10, .lower, .{});
                                                default_str = buf[0..len];
                                            },
                                            .bool => |b| default_str = if (b) "true" else "false",
                                            else => {},
                                        }
                                        
                                        const new_arg = try std.mem.replaceOwned(u8, allocator, arg_str, placeholder, default_str);
                                        allocator.free(arg_str);
                                        arg_str = new_arg;
                                    }
                                }
                            }
                        }
                    }
                    
                    try arg_list.append(arg_str);
                }
            }
        }
    }

    return ReviewCommand{
        .cmd = try allocator.dupe(u8, cmd_field.string),
        .args = try arg_list.toOwnedSlice(),
        .behavior = behavior,
    };
}

fn spawnReviewTool(allocator: std.mem.Allocator, command: ReviewCommand) !std.process.Child {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.append(command.cmd);
    for (command.args) |arg| {
        try argv.append(arg);
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();
    return child;
}

fn spawnHunkDaemon(allocator: std.mem.Allocator) !?std.process.Child {
    var argv = [_][]const u8{ "hunk", "daemon", "serve" };
    var child = std.process.Child.init(&argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch {
        return null;
    };

    // Give daemon time to bind its port
    std.time.sleep(2 * std.time.ns_per_s);
    return child;
}

fn seedHunkSession(allocator: std.mem.Allocator, command: ReviewCommand) void {
    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    argv.append(command.cmd) catch return;
    for (command.args) |arg| {
        argv.append(arg) catch return;
    }

    var child = std.process.Child.init(argv.items, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    child.spawn() catch {
        return;
    };

    // Let hunk register with daemon, then kill TUI process
    std.time.sleep(2 * std.time.ns_per_s);
    _ = child.kill() catch {};
    _ = child.wait() catch {};
}

fn killHunkDaemon(child: *std.process.Child) void {
    _ = child.kill() catch {};
    _ = child.wait() catch {};
}

fn waitForReviewApproval(database: *db.Database, task_id: []const u8, timeout_secs: u64) !bool {
    const poll_interval_ms = 5000;
    const max_iterations = (timeout_secs * 1000) / poll_interval_ms;
    const stdout = std.io.getStdOut().writer();

    var iteration: u64 = 0;
    while (iteration < max_iterations) : (iteration += 1) {
        const approved = try database.hasApprovedReviewGate(task_id);
        if (approved) {
            try stdout.writeAll("\n✓ Task-review gate approved by human developer.\n");
            return true;
        }

        if (iteration % 12 == 0) { // Every minute
            try stdout.print("Waiting for human review approval... ({d} minutes elapsed)\n", .{iteration / 12});
        }

        std.time.sleep(poll_interval_ms * std.time.ns_per_ms);
    }

    try stdout.writeAll("\n✗ Timeout: No human review approval received.\n");
    return false;
}

fn freeReviewCommand(allocator: std.mem.Allocator, command: ReviewCommand) void {
    allocator.free(command.cmd);
    for (command.args) |arg| allocator.free(arg);
    allocator.free(command.args);
    allocator.free(command.behavior);
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
        // Check if transitioning to DONE requires human review
        if (status != null and std.mem.eql(u8, status.?, "DONE")) {
            const has_review = try database.hasApprovedReviewGate(task_id);
            if (!has_review) {
                const stdout = std.io.getStdOut().writer();
                try stdout.print("\n⚠ Task-review gate required for task {s}.\n", .{task_id});
                try stdout.writeAll("Code review must be performed by a human developer.\n\n");

                // Try to load and spawn review tool
                if (try loadReviewProvider(allocator)) |provider_name| {
                    defer allocator.free(provider_name);

                    if (try loadReviewCommand(allocator, provider_name)) |command| {
                        defer freeReviewCommand(allocator, command);

                        try stdout.print("Review tool: {s}\n", .{command.cmd});
                        for (command.args) |arg| {
                            try stdout.print("  {s}\n", .{arg});
                        }
                        try stdout.writeAll("\n");

                        const is_interactive = std.mem.eql(u8, command.behavior, "interactive_tui");
                        var daemon_child: ?std.process.Child = null;
                        var review_child: ?std.process.Child = null;

                        if (is_interactive) {
                            daemon_child = try spawnHunkDaemon(allocator);
                            if (daemon_child != null) {
                                seedHunkSession(allocator, command);
                                try stdout.writeAll("Hunk review daemon started.\n");
                                try stdout.writeAll("Run `hunk diff` in any terminal to review.\n\n");
                            } else {
                                try stdout.writeAll("Could not start hunk daemon. Please run the review tool manually:\n\n");
                                try stdout.print("  {s}", .{command.cmd});
                                for (command.args) |arg| {
                                    try stdout.print(" {s}", .{arg});
                                }
                                try stdout.writeAll("\n\n");
                                try stdout.print("Then approve with:\n  acts gate add --task {s} --type task-review --status approved --by \"<developer>\"\n\n", .{task_id});
                            }
                        } else {
                            review_child = try spawnReviewTool(allocator, command);
                            try stdout.writeAll("Review tool spawned in background.\n");
                            try stdout.writeAll("(The review tool is running. Approve the review to proceed.)\n\n");
                        }

                        try stdout.writeAll("Waiting for human developer to complete review...\n\n");

                        const approved = try waitForReviewApproval(&database, task_id, 3600); // 1 hour timeout

                        if (daemon_child) |*c| {
                            killHunkDaemon(c);
                        }
                        if (review_child) |*c| {
                            _ = c.kill() catch {};
                        }

                        if (!approved) {
                            std.debug.print("\nTask update aborted: human review not approved within timeout.\n", .{});
                            std.debug.print("Please run the review tool manually and then re-run this command.\n", .{});
                            std.process.exit(1);
                        }
                    } else {
                        try stdout.print("Warning: Could not load review command for provider '{s}'\n", .{provider_name});
                        try stdout.writeAll("Please run your review tool manually, then:\n");
                        try stdout.print("  acts gate add --task {s} --type task-review --status approved --by \"<developer>\"\n", .{task_id});
                        try stdout.writeAll("Then re-run: acts task update {s} --status DONE\n\n");
                        std.process.exit(1);
                    }
                } else {
                    try stdout.writeAll("No review provider configured in .acts/acts.json\n");
                    try stdout.writeAll("Please add a review provider or manually run:\n");
                    try stdout.print("  acts gate add --task {s} --type task-review --status approved --by \"<developer>\"\n", .{task_id});
                    try stdout.writeAll("Then re-run: acts task update {s} --status DONE\n\n");
                    std.process.exit(1);
                }
            }
        }
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
        
        // Enforce human developer approval for task-review gates
        if (std.mem.eql(u8, gate_type.?, "task-review")) {
            if (approved_by == null or approved_by.?.len == 0) {
                std.debug.print("Error: task-review gates MUST be approved by a human developer.\n", .{});
                std.debug.print("Usage: acts gate add --task {s} --type task-review --status approved --by \"<human-developer-name>\"\n", .{task_id.?});
                std.debug.print("Agents cannot approve their own code reviews.\n", .{});
                std.process.exit(1);
            }
            
            // Block common agent names
            const blocked_names = [_][]const u8{ "agent", "ai", "claude", "cursor", "copilot", "gpt", "assistant", "opencode", "model" };
            const lower_name = try std.ascii.allocLowerString(allocator, approved_by.?);
            defer allocator.free(lower_name);
            
            for (blocked_names) |blocked| {
                if (std.mem.indexOf(u8, lower_name, blocked) != null) {
                    std.debug.print("Error: '{s}' appears to be an agent name. task-review gates MUST be approved by a human developer.\n", .{approved_by.?});
                    std.debug.print("Please use your actual name.\n", .{});
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
