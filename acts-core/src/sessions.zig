const std = @import("std");

pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    
    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);
    
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    const writer = output.writer();
    
    try writer.writeAll("{\n");
    
    // Extract metadata
    var developer: ?[]const u8 = null;
    var agent: ?[]const u8 = null;
    var date: ?[]const u8 = null;
    var task_id: ?[]const u8 = null;
    
    var lines = std.mem.split(u8, content, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "- **Developer:**")) {
            developer = std.mem.trim(u8, line[16..], " \r\n");
        } else if (std.mem.startsWith(u8, line, "- **Agent:**")) {
            agent = std.mem.trim(u8, line[12..], " \r\n");
        } else if (std.mem.startsWith(u8, line, "- **Date:**")) {
            date = std.mem.trim(u8, line[11..], " \r\n");
        } else if (std.mem.startsWith(u8, line, "- **Task:**")) {
            task_id = std.mem.trim(u8, line[11..], " \r\n");
        }
    }
    
    if (developer) |d| try writer.print("  \"developer\": \"{s}\",\n", .{d});
    if (agent) |a| try writer.print("  \"agent\": \"{s}\",\n", .{a});
    if (date) |dt| try writer.print("  \"date\": \"{s}\",\n", .{dt});
    if (task_id) |tid| try writer.print("  \"task_id\": \"{s}\",\n", .{tid});
    
    // Extract sections
    try writer.writeAll("  \"sections\": {\n");
    
    var in_section = false;
    var current_section: ?[]const u8 = null;
    var section_content = std.ArrayList(u8).init(allocator);
    defer section_content.deinit();
    
    lines = std.mem.split(u8, content, "\n");
    var first_section = true;
    
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "## ")) {
            if (in_section and current_section != null) {
                if (!first_section) try writer.writeAll(",\n");
                first_section = false;
                try writer.print("    \"{s}\": \"", .{current_section.?});
                // Escape newlines and quotes in content
                const content_str = section_content.items;
                for (content_str) |ch| {
                    if (ch == '\\' or ch == '"') {
                        try writer.writeByte('\\');
                    }
                    if (ch == '\n') {
                        try writer.writeByte('\\');
                        try writer.writeByte('n');
                    } else {
                        try writer.writeByte(ch);
                    }
                }
                try writer.writeAll("\"");
                section_content.clearRetainingCapacity();
            }
            current_section = std.mem.trim(u8, line[3..], " \r\n");
            in_section = true;
        } else if (in_section) {
            try section_content.writer().writeAll(line);
            try section_content.writer().writeByte('\n');
        }
    }
    
    // Last section
    if (in_section and current_section != null) {
        if (!first_section) try writer.writeAll(",\n");
        try writer.print("    \"{s}\": \"", .{current_section.?});
        const content_str = section_content.items;
        for (content_str) |ch| {
            if (ch == '\\' or ch == '"') {
                try writer.writeByte('\\');
            }
            if (ch == '\n') {
                try writer.writeByte('\\');
                try writer.writeByte('n');
            } else {
                try writer.writeByte(ch);
            }
        }
        try writer.writeAll("\"");
    }
    
    try writer.writeAll("\n  }\n}");
    
    return output.toOwnedSlice();
}

pub fn validateFile(allocator: std.mem.Allocator, path: []const u8) !bool {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    
    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);
    
    const required_sections = [_][]const u8{
        "What was done",
        "Decisions made",
        "What was NOT done (and why)",
        "Approaches tried and rejected",
        "Open questions",
        "Current state",
        "Files touched this session",
        "Suggested next step",
        "Agent Compliance",
    };
    
    var found_sections = std.StringHashMap(bool).init(allocator);
    defer found_sections.deinit();
    
    var lines = std.mem.split(u8, content, "\n");
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "## ")) {
            const section_name = std.mem.trim(u8, line[3..], " \r\n");
            try found_sections.put(section_name, true);
        }
    }
    
    var valid = true;
    const stderr = std.io.getStdErr().writer();
    
    for (required_sections) |section| {
        var found = false;
        var iter = found_sections.keyIterator();
        while (iter.next()) |key| {
            if (std.mem.startsWith(u8, key.*, section)) {
                found = true;
                break;
            }
        }
        if (!found) {
            try stderr.print("Missing required section: {s}\n", .{section});
            valid = false;
        }
    }
    
    // Check metadata
    if (!std.mem.containsAtLeast(u8, content, 1, "**Developer:**")) {
        try stderr.writeAll("Missing metadata: Developer\n");
        valid = false;
    }
    if (!std.mem.containsAtLeast(u8, content, 1, "**Date:**")) {
        try stderr.writeAll("Missing metadata: Date\n");
        valid = false;
    }
    if (!std.mem.containsAtLeast(u8, content, 1, "**Task:**")) {
        try stderr.writeAll("Missing metadata: Task\n");
        valid = false;
    }
    
    return valid;
}

pub fn listSessions(allocator: std.mem.Allocator, task_id: []const u8) ![]u8 {
    var output = std.ArrayList(u8).init(allocator);
    defer output.deinit();
    const writer = output.writer();
    
    try writer.writeAll("[\n");
    
    const sessions_dir = std.fs.cwd().openDir(".story/sessions", .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            try writer.writeAll("]");
            return output.toOwnedSlice();
        },
        else => return err,
    };
    
    var entries = std.ArrayList([]const u8).init(allocator);
    defer {
        for (entries.items) |entry| {
            allocator.free(entry);
        }
        entries.deinit();
    }
    
    var iter = sessions_dir.iterate();
    while (try iter.next()) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".md")) {
            try entries.append(try allocator.dupe(u8, entry.name));
        }
    }
    
    // Sort entries (newest first by filename)
    std.mem.sort([]const u8, entries.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .gt;
        }
    }.lessThan);
    
    var first = true;
    for (entries.items) |filename| {
        const path = try std.fs.path.join(allocator, &[_][]const u8{".story/sessions", filename});
        defer allocator.free(path);
        
        const parsed = parseFile(allocator, path) catch |err| {
            std.debug.print("Failed to parse {s}: {}\n", .{filename, err});
            continue;
        };
        defer allocator.free(parsed);
        
        // Check if this session is for the requested task
        if (!std.mem.containsAtLeast(u8, parsed, 1, task_id)) {
            continue;
        }
        
        if (!first) try writer.writeAll(",\n");
        first = false;
        try writer.writeAll(parsed);
    }
    
    try writer.writeAll("\n]");
    return output.toOwnedSlice();
}
