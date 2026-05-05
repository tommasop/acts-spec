const std = @import("std");

const c = @cImport({
    @cInclude("sqlite3.h");
});

pub const Database = struct {
    db: ?*c.sqlite3,

    pub fn open(path: []const u8) !Database {
        var db: ?*c.sqlite3 = null;
        const rc = c.sqlite3_open(path.ptr, &db);
        if (rc != c.SQLITE_OK) {
            std.debug.print("Cannot open database: {s}\n", .{c.sqlite3_errmsg(db)});
            if (db) |ptr| {
                _ = c.sqlite3_close(ptr);
            }
            return error.DatabaseOpenFailed;
        }
        
        // Enable foreign keys
        var stmt: ?*c.sqlite3_stmt = null;
        _ = c.sqlite3_prepare_v2(db, "PRAGMA foreign_keys = ON", -1, &stmt, null);
        if (stmt) |s| {
            _ = c.sqlite3_step(s);
            _ = c.sqlite3_finalize(s);
        }
        
        return Database{ .db = db };
    }

    pub fn close(self: *Database) void {
        if (self.db) |db| {
            _ = c.sqlite3_close(db);
            self.db = null;
        }
    }

    pub fn migrate(self: *Database) !void {
        const schema_sql = @embedFile("schema.sql");
        
        var err_msg: ?[*:0]u8 = null;
        const rc = c.sqlite3_exec(self.db, schema_sql, null, null, &err_msg);
        if (rc != c.SQLITE_OK) {
            if (err_msg) |msg| {
                std.debug.print("Migration failed: {s}\n", .{msg});
                c.sqlite3_free(msg);
            }
            return error.MigrationFailed;
        }
    }

    pub fn getSchemaVersion(self: *Database) !i32 {
        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, "SELECT version FROM schema_version ORDER BY version DESC LIMIT 1", -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            return error.QueryFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);
        
        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            return c.sqlite3_column_int(stmt, 0);
        }
        return 0;
    }

    pub fn initStory(self: *Database, story_id: []const u8, title: []const u8) !void {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO stories (id, acts_version, title, status, spec_approved) VALUES (?, '1.0.0', ?, 'ANALYSIS', 0)";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) {
            std.debug.print("Prepare failed: {s}\n", .{c.sqlite3_errmsg(self.db)});
            return error.QueryFailed;
        }
        defer _ = c.sqlite3_finalize(stmt);
        
        _ = c.sqlite3_bind_text(stmt, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, title.ptr, @intCast(title.len), c.SQLITE_STATIC);
        
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            std.debug.print("Insert failed: {s}\n", .{c.sqlite3_errmsg(self.db)});
            return error.InsertFailed;
        }
    }

    pub fn readState(self: *Database, allocator: std.mem.Allocator, story_id: ?[]const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        
        const writer = output.writer();
        
        // Get story
        var story_stmt: ?*c.sqlite3_stmt = null;
        var rc: c_int = 0;
        if (story_id != null) {
            rc = c.sqlite3_prepare_v2(self.db, "SELECT id, acts_version, title, status, spec_approved, created_at, updated_at, context_budget, session_count, compressed, strict_mode FROM stories WHERE id = ?", -1, &story_stmt, null);
        } else {
            rc = c.sqlite3_prepare_v2(self.db, "SELECT id, acts_version, title, status, spec_approved, created_at, updated_at, context_budget, session_count, compressed, strict_mode FROM stories", -1, &story_stmt, null);
        }
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(story_stmt);
        
        if (story_id != null) {
            _ = c.sqlite3_bind_text(story_stmt, 1, story_id.?.ptr, @intCast(story_id.?.len), c.SQLITE_STATIC);
        }
        
        if (c.sqlite3_step(story_stmt) == c.SQLITE_ROW) {
            try writer.print("{{\n", .{});
            try writer.print("  \"story_id\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(story_stmt, 0))});
            try writer.print("  \"acts_version\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(story_stmt, 1))});
            try writer.print("  \"title\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(story_stmt, 2))});
            try writer.print("  \"status\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(story_stmt, 3))});
            try writer.print("  \"spec_approved\": {s},\n", .{if (c.sqlite3_column_int(story_stmt, 4) == 1) "true" else "false"});
            try writer.print("  \"created_at\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(story_stmt, 5))});
            try writer.print("  \"updated_at\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(story_stmt, 6))});
            try writer.print("  \"context_budget\": {d},\n", .{c.sqlite3_column_int(story_stmt, 7)});
            try writer.print("  \"session_count\": {d},\n", .{c.sqlite3_column_int(story_stmt, 8)});
            try writer.print("  \"compressed\": {s},\n", .{if (c.sqlite3_column_int(story_stmt, 9) == 1) "true" else "false"});
            try writer.print("  \"strict_mode\": {s},\n", .{if (c.sqlite3_column_int(story_stmt, 10) == 1) "true" else "false"});
            
            // Get tasks
            try writer.writeAll("  \"tasks\": [\n");
            
            var task_stmt: ?*c.sqlite3_stmt = null;
            const task_sql = "SELECT id, title, description, status, assigned_to, context_priority, review_status FROM tasks WHERE story_id = ?";
            rc = c.sqlite3_prepare_v2(self.db, task_sql, -1, &task_stmt, null);
            if (rc == c.SQLITE_OK) {
                defer _ = c.sqlite3_finalize(task_stmt);
                _ = c.sqlite3_bind_text(task_stmt, 1, c.sqlite3_column_text(story_stmt, 0), -1, c.SQLITE_STATIC);
                
                var first_task = true;
                while (c.sqlite3_step(task_stmt) == c.SQLITE_ROW) {
                    if (!first_task) try writer.writeAll(",\n");
                    first_task = false;
                    
                    try writer.print("    {{\n", .{});
                    try writer.print("      \"id\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(task_stmt, 0))});
                    try writer.print("      \"title\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(task_stmt, 1))});
                    try writer.print("      \"description\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(task_stmt, 2))});
                    try writer.print("      \"status\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(task_stmt, 3))});
                    
                    const assigned = c.sqlite3_column_text(task_stmt, 4);
                    if (assigned != null) {
                        try writer.print("      \"assigned_to\": \"{s}\",\n", .{std.mem.span(assigned)});
                    } else {
                        try writer.writeAll("      \"assigned_to\": null,\n");
                    }
                    
                    try writer.print("      \"context_priority\": {d},\n", .{c.sqlite3_column_int(task_stmt, 5)});
                    try writer.print("      \"review_status\": \"{s}\"\n", .{std.mem.span(c.sqlite3_column_text(task_stmt, 6))});
                    
                    // Get files for this task
                    try writer.writeAll(",      \"files_touched\": [");
                    var file_stmt: ?*c.sqlite3_stmt = null;
                    const file_sql = "SELECT file_path FROM task_files WHERE task_id = ?";
                    rc = c.sqlite3_prepare_v2(self.db, file_sql, -1, &file_stmt, null);
                    if (rc == c.SQLITE_OK) {
                        defer _ = c.sqlite3_finalize(file_stmt);
                        _ = c.sqlite3_bind_text(file_stmt, 1, c.sqlite3_column_text(task_stmt, 0), -1, c.SQLITE_STATIC);
                        var first_file = true;
                        while (c.sqlite3_step(file_stmt) == c.SQLITE_ROW) {
                            if (!first_file) try writer.writeAll(", ");
                            first_file = false;
                            try writer.print("\"{s}\"", .{std.mem.span(c.sqlite3_column_text(file_stmt, 0))});
                        }
                    }
                    try writer.writeAll("],\n");
                    
                    // Get dependencies for this task
                    try writer.writeAll("      \"depends_on\": [");
                    var dep_stmt: ?*c.sqlite3_stmt = null;
                    const dep_sql = "SELECT depends_on FROM task_dependencies WHERE task_id = ?";
                    rc = c.sqlite3_prepare_v2(self.db, dep_sql, -1, &dep_stmt, null);
                    if (rc == c.SQLITE_OK) {
                        defer _ = c.sqlite3_finalize(dep_stmt);
                        _ = c.sqlite3_bind_text(dep_stmt, 1, c.sqlite3_column_text(task_stmt, 0), -1, c.SQLITE_STATIC);
                        var first_dep = true;
                        while (c.sqlite3_step(dep_stmt) == c.SQLITE_ROW) {
                            if (!first_dep) try writer.writeAll(", ");
                            first_dep = false;
                            try writer.print("\"{s}\"", .{std.mem.span(c.sqlite3_column_text(dep_stmt, 0))});
                        }
                    }
                    try writer.writeAll("]\n");
                    
                    try writer.writeAll("    }");
                }
            }
            
            try writer.writeAll("\n  ]\n}");
        } else {
            return error.StoryNotFound;
        }
        
        return output.toOwnedSlice();
    }

    pub fn writeState(_self: *Database, _allocator: std.mem.Allocator, _story_id: []const u8, _json: []const u8) !void {
        // Simple JSON parser for state write
        // For v1.0.0, we do a basic upsert of story fields
        // Full JSON parsing can be added in v1.1
        _ = _self;
        _ = _allocator;
        _ = _story_id;
        _ = _json;
        std.debug.print("State write: Not fully implemented in v1.0.0. Use SQL directly or task update commands.\n", .{});
    }

    pub fn getTask(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const writer = output.writer();
        
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT id, title, description, status, assigned_to, context_priority, review_status FROM tasks WHERE id = ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);
        
        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            try writer.print("{{\n", .{});
            try writer.print("  \"id\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(stmt, 0))});
            try writer.print("  \"title\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(stmt, 1))});
            try writer.print("  \"description\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(stmt, 2))});
            try writer.print("  \"status\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(stmt, 3))});
            
            const assigned = c.sqlite3_column_text(stmt, 4);
            if (assigned != null) {
                try writer.print("  \"assigned_to\": \"{s}\",\n", .{std.mem.span(assigned)});
            } else {
                try writer.writeAll("  \"assigned_to\": null,\n");
            }
            
            try writer.print("  \"context_priority\": {d},\n", .{c.sqlite3_column_int(stmt, 5)});
            try writer.print("  \"review_status\": \"{s}\"\n", .{std.mem.span(c.sqlite3_column_text(stmt, 6))});
            try writer.writeAll("}");
        } else {
            return error.TaskNotFound;
        }
        
        return output.toOwnedSlice();
    }

    pub fn updateTask(self: *Database, task_id: []const u8, status: ?[]const u8, assigned_to: ?[]const u8) !void {
        if (status != null and assigned_to != null) {
            var stmt: ?*c.sqlite3_stmt = null;
            const sql = "UPDATE tasks SET status = ?, assigned_to = ? WHERE id = ?";
            const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
            if (rc != c.SQLITE_OK) return error.QueryFailed;
            defer _ = c.sqlite3_finalize(stmt);
            
            _ = c.sqlite3_bind_text(stmt, 1, status.?.ptr, @intCast(status.?.len), c.SQLITE_STATIC);
            _ = c.sqlite3_bind_text(stmt, 2, assigned_to.?.ptr, @intCast(assigned_to.?.len), c.SQLITE_STATIC);
            _ = c.sqlite3_bind_text(stmt, 3, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);
            
            if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
                const err = c.sqlite3_errmsg(self.db);
                std.debug.print("Update failed: {s}\n", .{err});
                return error.UpdateFailed;
            }
        } else if (status != null) {
            var stmt: ?*c.sqlite3_stmt = null;
            const sql = "UPDATE tasks SET status = ? WHERE id = ?";
            const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
            if (rc != c.SQLITE_OK) return error.QueryFailed;
            defer _ = c.sqlite3_finalize(stmt);
            
            _ = c.sqlite3_bind_text(stmt, 1, status.?.ptr, @intCast(status.?.len), c.SQLITE_STATIC);
            _ = c.sqlite3_bind_text(stmt, 2, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);
            
            const step_rc = c.sqlite3_step(stmt);
            if (step_rc != c.SQLITE_DONE) {
                const err = c.sqlite3_errmsg(self.db);
                std.debug.print("Update failed: {s}\n", .{err});
                return error.UpdateFailed;
            }
        } else if (assigned_to != null) {
            var stmt: ?*c.sqlite3_stmt = null;
            const sql = "UPDATE tasks SET assigned_to = ? WHERE id = ?";
            const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
            if (rc != c.SQLITE_OK) return error.QueryFailed;
            defer _ = c.sqlite3_finalize(stmt);
            
            _ = c.sqlite3_bind_text(stmt, 1, assigned_to.?.ptr, @intCast(assigned_to.?.len), c.SQLITE_STATIC);
            _ = c.sqlite3_bind_text(stmt, 2, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);
            
            if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
                return error.UpdateFailed;
            }
        }
    }

    pub fn addGate(self: *Database, task_id: []const u8, gate_type: []const u8, status: []const u8, approved_by: ?[]const u8) !void {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO gate_checkpoints (task_id, gate_type, status, approved_by) VALUES (?, ?, ?, ?)";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, gate_type.ptr, @intCast(gate_type.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 3, status.ptr, @intCast(status.len), c.SQLITE_STATIC);
        
        if (approved_by) |by| {
            _ = c.sqlite3_bind_text(stmt, 4, by.ptr, @intCast(by.len), c.SQLITE_STATIC);
        } else {
            _ = c.sqlite3_bind_null(stmt, 4);
        }
        
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.InsertFailed;
        }
    }

    pub fn listGates(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const writer = output.writer();
        
        try writer.writeAll("[\n");
        
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT id, gate_type, status, approved_by, created_at FROM gate_checkpoints WHERE task_id = ? ORDER BY created_at";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);
        
        var first = true;
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            if (!first) try writer.writeAll(",\n");
            first = false;
            
            try writer.print("  {{\n", .{});
            try writer.print("    \"id\": {d},\n", .{c.sqlite3_column_int(stmt, 0)});
            try writer.print("    \"gate_type\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(stmt, 1))});
            try writer.print("    \"status\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(stmt, 2))});
            
            const approved_by = c.sqlite3_column_text(stmt, 3);
            if (approved_by != null) {
                try writer.print("    \"approved_by\": \"{s}\",\n", .{std.mem.span(approved_by)});
            } else {
                try writer.writeAll("    \"approved_by\": null,\n");
            }
            
            try writer.print("    \"created_at\": \"{s}\"\n", .{std.mem.span(c.sqlite3_column_text(stmt, 4))});
            try writer.writeAll("  }");
        }
        
        try writer.writeAll("\n]");
        return output.toOwnedSlice();
    }

    pub fn addDecision(_self: *Database, _allocator: std.mem.Allocator, _json: []const u8) !void {
        _ = _self;
        _ = _allocator;
        _ = _json;
        std.debug.print("Decision add: Not fully implemented in v1.0.0\n", .{});
    }

    pub fn listDecisions(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const writer = output.writer();
        
        try writer.writeAll("[\n");
        
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT id, topic, decided, reason, authority FROM decisions WHERE task_id = ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);
        
        var first = true;
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            if (!first) try writer.writeAll(",\n");
            first = false;
            
            try writer.print("  {{\n", .{});
            try writer.print("    \"id\": {d},\n", .{c.sqlite3_column_int(stmt, 0)});
            try writer.print("    \"topic\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(stmt, 1))});
            try writer.print("    \"decided\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(stmt, 2))});
            try writer.print("    \"reason\": \"{s}\",\n", .{std.mem.span(c.sqlite3_column_text(stmt, 3))});
            try writer.print("    \"authority\": \"{s}\"\n", .{std.mem.span(c.sqlite3_column_text(stmt, 4))});
            try writer.writeAll("  }");
        }
        
        try writer.writeAll("\n]");
        return output.toOwnedSlice();
    }

    pub fn addRejectedApproach(_self: *Database, _allocator: std.mem.Allocator, _json: []const u8) !void {
        _ = _self;
        _ = _allocator;
        _ = _json;
        std.debug.print("Rejected approach add: Not fully implemented in v1.0.0\n", .{});
    }

    pub fn addQuestion(_self: *Database, _allocator: std.mem.Allocator, _json: []const u8) !void {
        _ = _self;
        _ = _allocator;
        _ = _json;
        std.debug.print("Question add: Not fully implemented in v1.0.0\n", .{});
    }

    pub fn resolveQuestion(self: *Database, question_id: []const u8, resolution: ?[]const u8, resolved_by: ?[]const u8) !void {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "UPDATE open_questions SET status = 'resolved', resolution = ?, resolved_by = ? WHERE id = ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        if (resolution) |r| {
            _ = c.sqlite3_bind_text(stmt, 1, r.ptr, @intCast(r.len), c.SQLITE_STATIC);
        } else {
            _ = c.sqlite3_bind_null(stmt, 1);
        }
        
        if (resolved_by) |by| {
            _ = c.sqlite3_bind_text(stmt, 2, by.ptr, @intCast(by.len), c.SQLITE_STATIC);
        } else {
            _ = c.sqlite3_bind_null(stmt, 2);
        }
        
        const id = try std.fmt.parseInt(i32, question_id, 10);
        _ = c.sqlite3_bind_int(stmt, 3, id);
        
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.UpdateFailed;
        }
    }

    pub fn getOwnershipMap(self: *Database, allocator: std.mem.Allocator) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const writer = output.writer();
        
        try writer.writeAll("{\n");
        
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT t.id, t.status, tf.file_path FROM tasks t LEFT JOIN task_files tf ON t.id = tf.task_id WHERE t.status = 'DONE' ORDER BY t.id";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        var current_task: ?[]const u8 = null;
        var first = true;
        
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const task_id = std.mem.span(c.sqlite3_column_text(stmt, 0));
            const status = std.mem.span(c.sqlite3_column_text(stmt, 1));
            const file_path = c.sqlite3_column_text(stmt, 2);
            
            if (current_task == null or !std.mem.eql(u8, current_task.?, task_id)) {
                if (current_task != null) try writer.writeAll("\n  ]");
                if (!first) try writer.writeAll(",");
                first = false;
                try writer.print("\n  \"{s}\": {{\n    \"status\": \"{s}\",\n    \"files\": [", .{task_id, status});
                current_task = task_id;
                if (file_path != null) {
                    try writer.print("\"{s}\"", .{std.mem.span(file_path)});
                }
            } else if (file_path != null) {
                try writer.print(", \"{s}\"", .{std.mem.span(file_path)});
            }
        }
        
        if (current_task != null) try writer.writeAll("]\n  }");
        try writer.writeAll("\n}");
        
        return output.toOwnedSlice();
    }

    pub fn checkScope(self: *Database, allocator: std.mem.Allocator, task_id: []const u8, file_path: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const writer = output.writer();
        
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT t.id, t.status FROM tasks t JOIN task_files tf ON t.id = tf.task_id WHERE tf.file_path = ? AND t.id != ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        _ = c.sqlite3_bind_text(stmt, 1, file_path.ptr, @intCast(file_path.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);
        
        try writer.writeAll("{\n");
        try writer.print("  \"file_path\": \"{s}\",\n", .{file_path});
        try writer.print("  \"requesting_task\": \"{s}\",\n", .{task_id});
        
        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const owner_id = std.mem.span(c.sqlite3_column_text(stmt, 0));
            const owner_status = std.mem.span(c.sqlite3_column_text(stmt, 1));
            
            try writer.print("  \"owned_by\": \"{s}\",\n", .{owner_id});
            try writer.print("  \"owner_status\": \"{s}\",\n", .{owner_status});
            
            if (std.mem.eql(u8, owner_status, "DONE")) {
                try writer.writeAll("  \"action\": \"error\",\n");
                try writer.print("  \"message\": \"File is owned by DONE task {s}. Modifications require explicit approval.\"\n", .{owner_id});
            } else {
                try writer.writeAll("  \"action\": \"warn\",\n");
                try writer.print("  \"message\": \"File is owned by in-progress task {s}.\"\n", .{owner_id});
            }
        } else {
            try writer.writeAll("  \"owned_by\": null,\n");
            try writer.writeAll("  \"owner_status\": null,\n");
            try writer.writeAll("  \"action\": \"ok\",\n");
            try writer.writeAll("  \"message\": \"File is not owned by any other task. Safe to modify.\"\n");
        }
        
        try writer.writeAll("}");
        return output.toOwnedSlice();
    }

    pub fn logOperation(self: *Database, _allocator: std.mem.Allocator, operation_id: []const u8, task_id: ?[]const u8, json: []const u8) !void {
        _ = _allocator;
        
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO operation_log (operation_id, task_id, input_json) VALUES (?, ?, ?)";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);
        
        _ = c.sqlite3_bind_text(stmt, 1, operation_id.ptr, @intCast(operation_id.len), c.SQLITE_STATIC);
        
        if (task_id) |tid| {
            _ = c.sqlite3_bind_text(stmt, 2, tid.ptr, @intCast(tid.len), c.SQLITE_STATIC);
        } else {
            _ = c.sqlite3_bind_null(stmt, 2);
        }
        
        _ = c.sqlite3_bind_text(stmt, 3, json.ptr, @intCast(json.len), c.SQLITE_STATIC);
        
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.InsertFailed;
        }
    }
};
