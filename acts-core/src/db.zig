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

        // Enable WAL mode for concurrent access
        _ = c.sqlite3_exec(db, "PRAGMA journal_mode = WAL", null, null, null);
        // Queue writes instead of failing with SQLITE_BUSY
        _ = c.sqlite3_exec(db, "PRAGMA busy_timeout = 5000", null, null, null);
        // Foreign keys
        _ = c.sqlite3_exec(db, "PRAGMA foreign_keys = ON", null, null, null);

        return Database{ .db = db };
    }

    pub fn close(self: *Database) void {
        if (self.db) |db| {
            _ = c.sqlite3_close(db);
            self.db = null;
        }
    }

    pub fn beginImmediate(self: *Database) !void {
        var err_msg: ?[*:0]u8 = null;
        const rc = c.sqlite3_exec(self.db, "BEGIN IMMEDIATE", null, null, &err_msg);
        if (rc != c.SQLITE_OK) {
            if (err_msg) |msg| { c.sqlite3_free(msg); }
            return error.WriteLockFailed;
        }
    }

    pub fn commit(self: *Database) !void {
        const rc = c.sqlite3_exec(self.db, "COMMIT", null, null, null);
        if (rc != c.SQLITE_OK) return error.CommitFailed;
    }

    pub fn rollback(self: *Database) void {
        _ = c.sqlite3_exec(self.db, "ROLLBACK", null, null, null);
    }

    pub fn walCheckpoint(self: *Database) !struct { pages_log: i32, pages_ckpt: i32 } {
        var n_log: c_int = 0;
        var n_ckpt: c_int = 0;
        const rc = c.sqlite3_wal_checkpoint_v2(
            self.db, null,
            c.SQLITE_CHECKPOINT_RESTART,
            &n_log, &n_ckpt,
        );
        if (rc != c.SQLITE_OK) return error.CheckpointFailed;
        return .{ .pages_log = n_log, .pages_ckpt = n_ckpt };
    }

    pub fn walStatus(self: *Database, allocator: std.mem.Allocator) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const w = output.writer();

        var stmt: ?*c.sqlite3_stmt = null;
        const queries = [_]struct { pragma: []const u8, key: []const u8 }{
            .{ .pragma = "PRAGMA journal_mode", .key = "journal_mode" },
            .{ .pragma = "PRAGMA page_count", .key = "page_count" },
            .{ .pragma = "PRAGMA freelist_count", .key = "freelist_count" },
        };

        try w.writeAll("{");
        var first = true;
        for (queries) |q| {
            if (!first) try w.writeAll(",");
            first = false;
            _ = c.sqlite3_prepare_v2(self.db, q.pragma.ptr, -1, &stmt, null);
            if (stmt) |s| {
                defer _ = c.sqlite3_finalize(s);
                if (c.sqlite3_step(s) == c.SQLITE_ROW) {
                    const val = c.sqlite3_column_text(s, 0);
                    if (val) |v| {
                        try w.print("\"{s}\":\"{s}\"", .{ q.key, std.mem.span(v) });
                    } else {
                        try w.print("\"{s}\":{d}", .{ q.key, c.sqlite3_column_int(s, 0) });
                    }
                }
            }
        }
        try w.writeAll("}");
        return output.toOwnedSlice();
    }

    pub fn migrate(self: *Database) !void {
        const current_version = self.getSchemaVersion() catch 0;

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

        // Incremental migrations for older databases
        if (current_version < 2) {
            _ = c.sqlite3_exec(self.db, "ALTER TABLE tasks ADD COLUMN review_metadata TEXT", null, null, null);
        }
        if (current_version < 3) {
            _ = c.sqlite3_exec(self.db,
                "ALTER TABLE stories ADD COLUMN type TEXT DEFAULT 'feature' CHECK(type IN ('feature','maintenance','epic','spike'))",
                null, null, null);
            _ = c.sqlite3_exec(self.db, "ALTER TABLE tasks ADD COLUMN labels TEXT", null, null, null);
            _ = c.sqlite3_exec(self.db, auto_approve_maintenance_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, ensure_maintenance_sql, null, null, null);
        }
        if (current_version < 4) {
            _ = c.sqlite3_exec(self.db, "ALTER TABLE stories ADD COLUMN branch TEXT", null, null, null);
            _ = c.sqlite3_exec(self.db, "ALTER TABLE stories ADD COLUMN worktree_path TEXT", null, null, null);
            _ = c.sqlite3_exec(self.db, "ALTER TABLE stories ADD COLUMN parent_story TEXT REFERENCES stories(id)", null, null, null);
            _ = c.sqlite3_exec(self.db, "ALTER TABLE stories ADD COLUMN archived_at INTEGER", null, null, null);
            _ = c.sqlite3_exec(self.db, "ALTER TABLE stories ADD COLUMN semver TEXT", null, null, null);
            _ = c.sqlite3_exec(self.db, "ALTER TABLE stories ADD COLUMN released_at INTEGER", null, null, null);
            _ = c.sqlite3_exec(self.db, active_story_table_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, story_gates_table_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, file_conflicts_table_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, cross_story_ownership_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, detect_file_conflict_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, enforce_story_merge_sql, null, null, null);
        }
        if (current_version < 5) {
            _ = c.sqlite3_exec(self.db, unblock_events_table_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, review_queue_table_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, agent_presence_table_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, gate_sla_table_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, notify_dependency_unblock_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, auto_enqueue_review_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, cleanup_stale_presence_sql, null, null, null);
            _ = c.sqlite3_exec(self.db, set_review_sla_sql, null, null, null);
        }
    }

    // Migration SQL constants
    const auto_approve_maintenance_sql =
        "CREATE TRIGGER IF NOT EXISTS auto_approve_maintenance_preflight " ++
        "BEFORE UPDATE OF status ON tasks " ++
        "WHEN NEW.status = 'IN_PROGRESS' AND OLD.status = 'TODO' " ++
        "BEGIN " ++
        "  INSERT OR IGNORE INTO gate_checkpoints (task_id, gate_type, status, approved_by) " ++
        "  SELECT NEW.id, 'approve', 'approved', '__system__' " ++
        "  FROM tasks t WHERE t.id = NEW.id AND t.story_id = '__maintenance__'; " ++
        "END;";

    const ensure_maintenance_sql =
        "INSERT OR IGNORE INTO stories (id, acts_version, title, status, spec_approved, type) " ++
        "VALUES ('__maintenance__', '1.0.0', 'Maintenance & Bug Fixes', 'APPROVED', 1, 'maintenance');";

    const active_story_table_sql =
        "CREATE TABLE IF NOT EXISTS active_story (" ++
        "  story_id TEXT PRIMARY KEY REFERENCES stories(id)," ++
        "  activated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))" ++
        ");" ++
        "CREATE TRIGGER IF NOT EXISTS single_active_story " ++
        "BEFORE INSERT ON active_story " ++
        "BEGIN " ++
        "  SELECT CASE WHEN (SELECT COUNT(*) FROM active_story) > 0 " ++
        "  THEN RAISE(ABORT, 'Only one active story. Run: acts story switch <id>') " ++
        "  END; " ++
        "END;";

    const story_gates_table_sql =
        "CREATE TABLE IF NOT EXISTS story_gates (" ++
        "  id INTEGER PRIMARY KEY AUTOINCREMENT," ++
        "  story_id TEXT NOT NULL REFERENCES stories(id)," ++
        "  gate_type TEXT NOT NULL CHECK(gate_type IN ('story-approve','story-merge','architecture-discuss'))," ++
        "  status TEXT NOT NULL CHECK(status IN ('pending','approved','changes_requested'))," ++
        "  approved_by TEXT," ++
        "  created_at TEXT NOT NULL DEFAULT (datetime('now'))" ++
        ");";

    const file_conflicts_table_sql =
        "CREATE TABLE IF NOT EXISTS file_conflicts (" ++
        "  id INTEGER PRIMARY KEY AUTOINCREMENT," ++
        "  file_path TEXT NOT NULL," ++
        "  story_a TEXT NOT NULL," ++
        "  story_b TEXT NOT NULL," ++
        "  detected_at TEXT DEFAULT (datetime('now'))," ++
        "  resolved INTEGER DEFAULT 0" ++
        ");";

    const cross_story_ownership_sql =
        "CREATE TRIGGER IF NOT EXISTS enforce_cross_story_ownership " ++
        "BEFORE INSERT ON task_files " ++
        "BEGIN " ++
        "  SELECT CASE WHEN EXISTS(" ++
        "    SELECT 1 FROM task_files tf JOIN tasks t ON t.id = tf.task_id " ++
        "    WHERE tf.file_path = NEW.file_path " ++
        "    AND t.story_id != (SELECT story_id FROM tasks WHERE id = NEW.task_id) " ++
        "    AND t.status = 'DONE' " ++
        "  ) THEN RAISE(ABORT, 'File already owned by a DONE task in another story') " ++
        "  END; " ++
        "END;";

    const detect_file_conflict_sql =
        "CREATE TRIGGER IF NOT EXISTS detect_file_conflict " ++
        "AFTER INSERT ON task_files " ++
        "BEGIN " ++
        "  INSERT INTO file_conflicts (file_path, story_a, story_b) " ++
        "  SELECT NEW.file_path, " ++
        "    (SELECT story_id FROM tasks WHERE id = NEW.task_id), " ++
        "    t.story_id " ++
        "  FROM task_files tf JOIN tasks t ON t.id = tf.task_id " ++
        "  WHERE tf.file_path = NEW.file_path " ++
        "  AND t.story_id != (SELECT story_id FROM tasks WHERE id = NEW.task_id) " ++
        "  AND t.status IN ('IN_PROGRESS', 'TODO') " ++
        "  AND NOT EXISTS (SELECT 1 FROM file_conflicts fc WHERE fc.file_path = NEW.file_path AND fc.resolved = 0); " ++
        "END;";

    const enforce_story_merge_sql =
        "CREATE TRIGGER IF NOT EXISTS enforce_story_merge " ++
        "BEFORE UPDATE OF status ON stories " ++
        "WHEN NEW.status = 'MERGED' AND OLD.status != 'MERGED' " ++
        "BEGIN " ++
        "  SELECT CASE WHEN EXISTS(SELECT 1 FROM tasks WHERE story_id = NEW.id AND status != 'DONE') " ++
        "  THEN RAISE(ABORT, 'Cannot merge story: open tasks remain') END; " ++
        "  SELECT CASE WHEN EXISTS(" ++
        "    SELECT 1 FROM tasks t WHERE t.story_id = NEW.id AND t.status = 'DONE' " ++
        "    AND NOT EXISTS (SELECT 1 FROM gate_checkpoints gc WHERE gc.task_id = t.id " ++
        "      AND gc.gate_type = 'task-review' AND gc.status = 'approved')) " ++
        "  THEN RAISE(ABORT, 'Cannot merge story: tasks without approved review') END; " ++
        "END;";

    const unblock_events_table_sql =
        "CREATE TABLE IF NOT EXISTS unblock_events (" ++
        "  id INTEGER PRIMARY KEY AUTOINCREMENT," ++
        "  unblocked_task_id TEXT NOT NULL REFERENCES tasks(id)," ++
        "  unblocked_by TEXT NOT NULL REFERENCES tasks(id)," ++
        "  created_at TEXT DEFAULT (datetime('now'))," ++
        "  acknowledged INTEGER DEFAULT 0" ++
        ");";

    const review_queue_table_sql =
        "CREATE TABLE IF NOT EXISTS review_queue (" ++
        "  id INTEGER PRIMARY KEY AUTOINCREMENT," ++
        "  task_id TEXT NOT NULL REFERENCES tasks(id)," ++
        "  requested_by TEXT," ++
        "  requested_at TEXT DEFAULT (datetime('now'))," ++
        "  assigned_to TEXT," ++
        "  status TEXT DEFAULT 'pending' CHECK(status IN ('pending','in_review','approved','rejected'))" ++
        ");";

    const agent_presence_table_sql =
        "CREATE TABLE IF NOT EXISTS agent_presence (" ++
        "  agent_id TEXT PRIMARY KEY," ++
        "  story_id TEXT REFERENCES stories(id)," ++
        "  task_id TEXT REFERENCES tasks(id)," ++
        "  current_action TEXT," ++
        "  heartbeat INTEGER NOT NULL" ++
        ");";

    const gate_sla_table_sql =
        "CREATE TABLE IF NOT EXISTS gate_sla (" ++
        "  gate_id INTEGER PRIMARY KEY REFERENCES gate_checkpoints(id)," ++
        "  deadline TEXT NOT NULL," ++
        "  breached INTEGER DEFAULT 0" ++
        ");";

    const notify_dependency_unblock_sql =
        "CREATE TRIGGER IF NOT EXISTS notify_dependency_unblock " ++
        "AFTER UPDATE OF status ON tasks " ++
        "WHEN NEW.status = 'DONE' AND OLD.status != 'DONE' " ++
        "BEGIN " ++
        "  INSERT INTO unblock_events (unblocked_task_id, unblocked_by) " ++
        "  SELECT td.task_id, NEW.id FROM task_dependencies td WHERE td.depends_on = NEW.id; " ++
        "END;";

    const auto_enqueue_review_sql =
        "CREATE TRIGGER IF NOT EXISTS auto_enqueue_review " ++
        "AFTER INSERT ON gate_checkpoints " ++
        "WHEN NEW.gate_type = 'task-review' AND NEW.status = 'pending' " ++
        "BEGIN " ++
        "  INSERT INTO review_queue (task_id, requested_by) " ++
        "  SELECT NEW.task_id, t.assigned_to FROM tasks t WHERE t.id = NEW.task_id; " ++
        "END;";

    const cleanup_stale_presence_sql =
        "CREATE TRIGGER IF NOT EXISTS cleanup_stale_presence " ++
        "AFTER INSERT ON agent_presence " ++
        "BEGIN " ++
        "  DELETE FROM agent_presence WHERE heartbeat < (strftime('%s','now') - 300); " ++
        "END;";

    const set_review_sla_sql =
        "CREATE TRIGGER IF NOT EXISTS set_review_sla " ++
        "AFTER INSERT ON gate_checkpoints " ++
        "WHEN NEW.gate_type = 'task-review' AND NEW.status = 'pending' " ++
        "BEGIN " ++
        "  INSERT INTO gate_sla (gate_id, deadline) VALUES (NEW.id, datetime('now', '+24 hours')); " ++
        "END;";

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

    // JSON escaping helper
    pub fn escapeJsonString(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
        var out = std.ArrayList(u8).init(allocator);
        errdefer out.deinit();
        const w = out.writer();
        for (input) |ch| {
            switch (ch) {
                '"' => try w.writeAll("\\\""),
                '\\' => try w.writeAll("\\\\"),
                '\n' => try w.writeAll("\\n"),
                '\r' => try w.writeAll("\\r"),
                '\t' => try w.writeAll("\\t"),
                else => try w.writeByte(ch),
            }
        }
        return out.toOwnedSlice();
    }

    pub fn initStory(self: *Database, story_id: []const u8, title: []const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO stories (id, acts_version, title, status, spec_approved, type) VALUES (?, '1.0.0', ?, 'ANALYSIS', 0, 'feature')";
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

        // Ensure maintenance story always exists
        _ = c.sqlite3_exec(self.db, ensure_maintenance_sql, null, null, null);

        try self.commit();
    }

    pub fn readState(self: *Database, allocator: std.mem.Allocator, story_id: ?[]const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const writer = output.writer();

        var story_stmt: ?*c.sqlite3_stmt = null;
        var rc: c_int = 0;
        if (story_id != null) {
            rc = c.sqlite3_prepare_v2(self.db, "SELECT id, acts_version, title, status, spec_approved, created_at, updated_at, context_budget, session_count, compressed, strict_mode, type, branch, semver FROM stories WHERE id = ?", -1, &story_stmt, null);
        } else {
            rc = c.sqlite3_prepare_v2(self.db, "SELECT id, acts_version, title, status, spec_approved, created_at, updated_at, context_budget, session_count, compressed, strict_mode, type, branch, semver FROM stories", -1, &story_stmt, null);
        }
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(story_stmt);

        if (story_id != null) {
            _ = c.sqlite3_bind_text(story_stmt, 1, story_id.?.ptr, @intCast(story_id.?.len), c.SQLITE_STATIC);
        }

        if (c.sqlite3_step(story_stmt) == c.SQLITE_ROW) {
            try writer.print("{{\n", .{});
            try writer.print("  \"story_id\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(story_stmt, 0))});
            try writer.print("  \"acts_version\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(story_stmt, 1))});
            try writer.print("  \"title\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(story_stmt, 2))});
            try writer.print("  \"status\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(story_stmt, 3))});
            try writer.print("  \"spec_approved\": {s},\n", .{if (c.sqlite3_column_int(story_stmt, 4) == 1) "true" else "false"});
            try writer.print("  \"created_at\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(story_stmt, 5))});
            try writer.print("  \"updated_at\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(story_stmt, 6))});
            try writer.print("  \"context_budget\": {d},\n", .{c.sqlite3_column_int(story_stmt, 7)});
            try writer.print("  \"session_count\": {d},\n", .{c.sqlite3_column_int(story_stmt, 8)});
            try writer.print("  \"compressed\": {s},\n", .{if (c.sqlite3_column_int(story_stmt, 9) == 1) "true" else "false"});
            try writer.print("  \"strict_mode\": {s},\n", .{if (c.sqlite3_column_int(story_stmt, 10) == 1) "true" else "false"});
            try writer.print("  \"type\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(story_stmt, 11))});
            const branch = ct(story_stmt, 12);
            if (branch.len > 0) {
                try writer.print("  \"branch\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, branch)});
            } else {
                try writer.writeAll("  \"branch\": null,\n");
            }
            const semver = ct(story_stmt, 13);
            if (semver.len > 0) {
                try writer.print("  \"semver\": \"{s}\"\n", .{try Database.escapeJsonString(allocator, semver)});
            } else {
                try writer.writeAll("  \"semver\": null\n");
            }

            // Get tasks
            try writer.writeAll("  \"tasks\": [\n");
            var task_stmt: ?*c.sqlite3_stmt = null;
            const task_sql = "SELECT id, title, description, status, assigned_to, context_priority, review_status, labels FROM tasks WHERE story_id = ?";
            rc = c.sqlite3_prepare_v2(self.db, task_sql, -1, &task_stmt, null);
            if (rc == c.SQLITE_OK) {
                defer _ = c.sqlite3_finalize(task_stmt);
                _ = c.sqlite3_bind_text(task_stmt, 1, c.sqlite3_column_text(story_stmt, 0), -1, c.SQLITE_STATIC);

                var first_task = true;
                while (c.sqlite3_step(task_stmt) == c.SQLITE_ROW) {
                    if (!first_task) try writer.writeAll(",\n");
                    first_task = false;

                    try writer.print("    {{\n", .{});
                    try writer.print("      \"id\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(task_stmt, 0))});
                    try writer.print("      \"title\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(task_stmt, 1))});
                    try writer.print("      \"description\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(task_stmt, 2))});
                    try writer.print("      \"status\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(task_stmt, 3))});

                    const assigned = c.sqlite3_column_text(task_stmt, 4);
                    if (assigned != null) {
                        try writer.print("      \"assigned_to\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(assigned))});
                    } else {
                        try writer.writeAll("      \"assigned_to\": null,\n");
                    }

                    try writer.print("      \"context_priority\": {d},\n", .{c.sqlite3_column_int(task_stmt, 5)});
                    try writer.print("      \"review_status\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(task_stmt, 6))});
                    const labels = c.sqlite3_column_text(task_stmt, 7);
                    if (labels != null) {
                        try writer.print("      \"labels\": {s}\n", .{std.mem.span(labels)});
                    } else {
                        try writer.writeAll("      \"labels\": null\n");
                    }

                    // Files
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
                            try writer.print("\"{s}\"", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(file_stmt, 0)))});
                        }
                    }
                    try writer.writeAll("],\n");

                    // Dependencies
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
                            try writer.print("\"{s}\"", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(dep_stmt, 0)))});
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

    fn ct(stmt: ?*c.sqlite3_stmt, idx: c_int) []const u8 {
        const val = c.sqlite3_column_text(stmt, idx);
        return if (val != null) std.mem.span(val) else "";
    }

    pub fn writeState(self: *Database, allocator: std.mem.Allocator, story_id: []const u8, json: []const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidJson;

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "UPDATE stories SET title = COALESCE(?, title), status = COALESCE(?, status), spec_approved = COALESCE(?, spec_approved), context_budget = COALESCE(?, context_budget), strict_mode = COALESCE(?, strict_mode) WHERE id = ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        if (root.object.get("title")) |title| {
            if (title == .string) _ = c.sqlite3_bind_text(stmt, 1, title.string.ptr, @intCast(title.string.len), c.SQLITE_STATIC) else _ = c.sqlite3_bind_null(stmt, 1);
        } else { _ = c.sqlite3_bind_null(stmt, 1); }

        if (root.object.get("status")) |status| {
            if (status == .string) _ = c.sqlite3_bind_text(stmt, 2, status.string.ptr, @intCast(status.string.len), c.SQLITE_STATIC) else _ = c.sqlite3_bind_null(stmt, 2);
        } else { _ = c.sqlite3_bind_null(stmt, 2); }

        if (root.object.get("spec_approved")) |sa| {
            if (sa == .bool) _ = c.sqlite3_bind_int(stmt, 3, if (sa.bool) 1 else 0) else _ = c.sqlite3_bind_null(stmt, 3);
        } else { _ = c.sqlite3_bind_null(stmt, 3); }

        if (root.object.get("context_budget")) |cb| {
            if (cb == .integer) _ = c.sqlite3_bind_int(stmt, 4, @intCast(cb.integer)) else _ = c.sqlite3_bind_null(stmt, 4);
        } else { _ = c.sqlite3_bind_null(stmt, 4); }

        if (root.object.get("strict_mode")) |sm| {
            if (sm == .bool) _ = c.sqlite3_bind_int(stmt, 5, if (sm.bool) 1 else 0) else _ = c.sqlite3_bind_null(stmt, 5);
        } else { _ = c.sqlite3_bind_null(stmt, 5); }

        _ = c.sqlite3_bind_text(stmt, 6, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.UpdateFailed;
        }

        if (root.object.get("tasks")) |tasks| {
            if (tasks == .array) {
                for (tasks.array.items) |task| {
                    if (task == .object) {
                        try self.upsertTask(task.object, story_id);
                    }
                }
            }
        }

        try self.commit();
    }

    fn upsertTask(self: *Database, task_obj: std.json.ObjectMap, story_id: []const u8) !void {
        const task_id = task_obj.get("id") orelse return error.MissingTaskId;
        if (task_id != .string) return error.InvalidTaskId;

        var check_stmt: ?*c.sqlite3_stmt = null;
        const check_sql = "SELECT COUNT(*) FROM tasks WHERE id = ?";
        var rc = c.sqlite3_prepare_v2(self.db, check_sql, -1, &check_stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(check_stmt);

        _ = c.sqlite3_bind_text(check_stmt, 1, task_id.string.ptr, @intCast(task_id.string.len), c.SQLITE_STATIC);
        const exists = c.sqlite3_step(check_stmt) == c.SQLITE_ROW and c.sqlite3_column_int(check_stmt, 0) > 0;

        if (exists) {
            var stmt: ?*c.sqlite3_stmt = null;
            const sql = "UPDATE tasks SET title = COALESCE(?, title), description = COALESCE(?, description), status = COALESCE(?, status), assigned_to = COALESCE(?, assigned_to), context_priority = COALESCE(?, context_priority), labels = COALESCE(?, labels) WHERE id = ?";
            rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
            if (rc != c.SQLITE_OK) return error.QueryFailed;
            defer _ = c.sqlite3_finalize(stmt);

            const bindStr = struct {
                fn inner(s: ?*c.sqlite3_stmt, idx: c_int, val: ?std.json.Value) void {
                    if (val) |v| {
                        if (v == .string) _ = c.sqlite3_bind_text(s, idx, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else _ = c.sqlite3_bind_null(s, idx);
                    } else { _ = c.sqlite3_bind_null(s, idx); }
                }
            }.inner;

            bindStr(stmt, 1, task_obj.get("title"));
            bindStr(stmt, 2, task_obj.get("description"));
            bindStr(stmt, 3, task_obj.get("status"));
            bindStr(stmt, 4, task_obj.get("assigned_to"));

            if (task_obj.get("context_priority")) |v| {
                if (v == .integer) _ = c.sqlite3_bind_int(stmt, 5, @intCast(v.integer)) else _ = c.sqlite3_bind_null(stmt, 5);
            } else { _ = c.sqlite3_bind_null(stmt, 5); }

            bindStr(stmt, 6, task_obj.get("labels"));

            _ = c.sqlite3_bind_text(stmt, 7, task_id.string.ptr, @intCast(task_id.string.len), c.SQLITE_STATIC);

            if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
                return error.UpdateFailed;
            }
        } else {
            var stmt: ?*c.sqlite3_stmt = null;
            const sql = "INSERT INTO tasks (id, story_id, title, description, status, assigned_to, context_priority, labels) VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
            rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
            if (rc != c.SQLITE_OK) return error.QueryFailed;
            defer _ = c.sqlite3_finalize(stmt);

            _ = c.sqlite3_bind_text(stmt, 1, task_id.string.ptr, @intCast(task_id.string.len), c.SQLITE_STATIC);
            _ = c.sqlite3_bind_text(stmt, 2, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);

            const bindStr = struct {
                fn inner(s: ?*c.sqlite3_stmt, idx: c_int, val: ?std.json.Value) void {
                    if (val) |v| {
                        if (v == .string) _ = c.sqlite3_bind_text(s, idx, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else _ = c.sqlite3_bind_null(s, idx);
                    } else { _ = c.sqlite3_bind_null(s, idx); }
                }
            }.inner;

            bindStr(stmt, 3, task_obj.get("title"));
            bindStr(stmt, 4, task_obj.get("description"));
            bindStr(stmt, 5, task_obj.get("status"));
            bindStr(stmt, 6, task_obj.get("assigned_to"));

            if (task_obj.get("context_priority")) |v| {
                if (v == .integer) _ = c.sqlite3_bind_int(stmt, 7, @intCast(v.integer)) else _ = c.sqlite3_bind_null(stmt, 7);
            } else { _ = c.sqlite3_bind_null(stmt, 7); }

            bindStr(stmt, 8, task_obj.get("labels"));

            if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
                return error.InsertFailed;
            }
        }

        // Update files
        if (task_obj.get("files_touched")) |files| {
            if (files == .array) {
                var del_stmt: ?*c.sqlite3_stmt = null;
                const del_sql = "DELETE FROM task_files WHERE task_id = ?";
                rc = c.sqlite3_prepare_v2(self.db, del_sql, -1, &del_stmt, null);
                if (rc == c.SQLITE_OK) {
                    defer _ = c.sqlite3_finalize(del_stmt);
                    _ = c.sqlite3_bind_text(del_stmt, 1, task_id.string.ptr, @intCast(task_id.string.len), c.SQLITE_STATIC);
                    _ = c.sqlite3_step(del_stmt);
                }

                for (files.array.items) |file| {
                    if (file == .string) {
                        var file_stmt: ?*c.sqlite3_stmt = null;
                        const file_sql = "INSERT INTO task_files (task_id, file_path) VALUES (?, ?)";
                        rc = c.sqlite3_prepare_v2(self.db, file_sql, -1, &file_stmt, null);
                        if (rc == c.SQLITE_OK) {
                            defer _ = c.sqlite3_finalize(file_stmt);
                            _ = c.sqlite3_bind_text(file_stmt, 1, task_id.string.ptr, @intCast(task_id.string.len), c.SQLITE_STATIC);
                            _ = c.sqlite3_bind_text(file_stmt, 2, file.string.ptr, @intCast(file.string.len), c.SQLITE_STATIC);
                            _ = c.sqlite3_step(file_stmt);
                        }
                    }
                }
            }
        }

        // Update dependencies
        if (task_obj.get("depends_on")) |deps| {
            if (deps == .array) {
                var del_stmt: ?*c.sqlite3_stmt = null;
                const del_sql = "DELETE FROM task_dependencies WHERE task_id = ?";
                rc = c.sqlite3_prepare_v2(self.db, del_sql, -1, &del_stmt, null);
                if (rc == c.SQLITE_OK) {
                    defer _ = c.sqlite3_finalize(del_stmt);
                    _ = c.sqlite3_bind_text(del_stmt, 1, task_id.string.ptr, @intCast(task_id.string.len), c.SQLITE_STATIC);
                    _ = c.sqlite3_step(del_stmt);
                }

                for (deps.array.items) |dep| {
                    if (dep == .string) {
                        var dep_stmt: ?*c.sqlite3_stmt = null;
                        const dep_sql = "INSERT INTO task_dependencies (task_id, depends_on) VALUES (?, ?)";
                        rc = c.sqlite3_prepare_v2(self.db, dep_sql, -1, &dep_stmt, null);
                        if (rc == c.SQLITE_OK) {
                            defer _ = c.sqlite3_finalize(dep_stmt);
                            _ = c.sqlite3_bind_text(dep_stmt, 1, task_id.string.ptr, @intCast(task_id.string.len), c.SQLITE_STATIC);
                            _ = c.sqlite3_bind_text(dep_stmt, 2, dep.string.ptr, @intCast(dep.string.len), c.SQLITE_STATIC);
                            _ = c.sqlite3_step(dep_stmt);
                        }
                    }
                }
            }
        }
    }

    pub fn getTask(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const writer = output.writer();

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT id, title, description, status, assigned_to, context_priority, review_status, labels, story_id FROM tasks WHERE id = ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            try writer.print("{{\n", .{});
            try writer.print("  \"id\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(stmt, 0))});
            try writer.print("  \"title\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(stmt, 1))});
            try writer.print("  \"description\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(stmt, 2))});
            try writer.print("  \"status\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(stmt, 3))});

            const assigned = c.sqlite3_column_text(stmt, 4);
            if (assigned != null) {
                try writer.print("  \"assigned_to\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(assigned))});
            } else {
                try writer.writeAll("  \"assigned_to\": null,\n");
            }

            try writer.print("  \"context_priority\": {d},\n", .{c.sqlite3_column_int(stmt, 5)});
            try writer.print("  \"review_status\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, ct(stmt, 6))});
            const labels = c.sqlite3_column_text(stmt, 7);
            if (labels != null) {
                try writer.print("  \"labels\": {s},\n", .{std.mem.span(labels)});
            } else {
                try writer.writeAll("  \"labels\": null,\n");
            }
            try writer.print("  \"story_id\": \"{s}\"\n", .{try Database.escapeJsonString(allocator, ct(stmt, 8))});
            try writer.writeAll("}");
        } else {
            return error.TaskNotFound;
        }

        return output.toOwnedSlice();
    }

    pub fn updateTask(self: *Database, task_id: []const u8, status: ?[]const u8, assigned_to: ?[]const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        if (status != null and assigned_to != null) {
            var stmt: ?*c.sqlite3_stmt = null;
            const sql = "UPDATE tasks SET status = ?, assigned_to = ? WHERE id = ?";
            const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
            if (rc != c.SQLITE_OK) return error.QueryFailed;
            defer _ = c.sqlite3_finalize(stmt);

            _ = c.sqlite3_bind_text(stmt, 1, status.?.ptr, @intCast(status.?.len), c.SQLITE_STATIC);
            _ = c.sqlite3_bind_text(stmt, 2, assigned_to.?.ptr, @intCast(assigned_to.?.len), c.SQLITE_STATIC);
            _ = c.sqlite3_bind_text(stmt, 3, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);

            const step_rc = c.sqlite3_step(stmt);
            if (step_rc != c.SQLITE_DONE) {
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

        try self.commit();
    }

    pub fn addGate(self: *Database, task_id: []const u8, gate_type: []const u8, status: []const u8, approved_by: ?[]const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

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

        try self.commit();
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
            try writer.print("    \"gate_type\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 1)))});
            try writer.print("    \"status\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 2)))});

            const approved_by = c.sqlite3_column_text(stmt, 3);
            if (approved_by != null) {
                try writer.print("    \"approved_by\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(approved_by))});
            } else {
                try writer.writeAll("    \"approved_by\": null,\n");
            }

            try writer.print("    \"created_at\": \"{s}\"\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 4)))});
            try writer.writeAll("  }");
        }

        try writer.writeAll("\n]");
        return output.toOwnedSlice();
    }

    pub fn hasApprovedReviewGate(self: *Database, task_id: []const u8) !bool {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT COUNT(*) FROM gate_checkpoints WHERE task_id = ? AND gate_type = 'task-review' AND status = 'approved'";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            return c.sqlite3_column_int(stmt, 0) > 0;
        }
        return false;
    }

    pub fn addDecision(self: *Database, allocator: std.mem.Allocator, json: []const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidJson;

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO decisions (task_id, session, topic, plan_said, decided, reason, evidence, authority, tags) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        const obj = root.object;

        if (obj.get("task_id")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 1, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("session")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 2, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else _ = c.sqlite3_bind_text(stmt, 2, "default", 7, c.SQLITE_STATIC);
        } else _ = c.sqlite3_bind_text(stmt, 2, "default", 7, c.SQLITE_STATIC);

        if (obj.get("topic")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 3, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("plan_said")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 4, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else _ = c.sqlite3_bind_null(stmt, 4);
        } else _ = c.sqlite3_bind_null(stmt, 4);

        if (obj.get("decided")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 5, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("reason")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 6, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("evidence")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 7, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("authority")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 8, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("tags")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 9, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else _ = c.sqlite3_bind_null(stmt, 9);
        } else _ = c.sqlite3_bind_null(stmt, 9);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.InsertFailed;
        }

        try self.commit();
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
            try writer.print("    \"topic\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 1)))});
            try writer.print("    \"decided\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 2)))});
            try writer.print("    \"reason\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 3)))});
            try writer.print("    \"authority\": \"{s}\"\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 4)))});
            try writer.writeAll("  }");
        }

        try writer.writeAll("\n]");
        return output.toOwnedSlice();
    }

    pub fn addRejectedApproach(self: *Database, allocator: std.mem.Allocator, json: []const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidJson;

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO rejected_approaches (task_id, session, approach, reason, evidence, tags) VALUES (?, ?, ?, ?, ?, ?)";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        const obj = root.object;

        if (obj.get("task_id")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 1, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("session")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 2, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else _ = c.sqlite3_bind_text(stmt, 2, "default", 7, c.SQLITE_STATIC);
        } else _ = c.sqlite3_bind_text(stmt, 2, "default", 7, c.SQLITE_STATIC);

        if (obj.get("approach")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 3, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("reason")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 4, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("evidence")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 5, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("tags")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 6, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else _ = c.sqlite3_bind_null(stmt, 6);
        } else _ = c.sqlite3_bind_null(stmt, 6);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.InsertFailed;
        }

        try self.commit();
    }

    pub fn addQuestion(self: *Database, allocator: std.mem.Allocator, json: []const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidJson;

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO open_questions (task_id, question, raised_by) VALUES (?, ?, ?)";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        const obj = root.object;

        if (obj.get("task_id")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 1, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("question")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 2, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (obj.get("raised_by")) |v| {
            if (v == .string) _ = c.sqlite3_bind_text(stmt, 3, v.string.ptr, @intCast(v.string.len), c.SQLITE_STATIC) else return error.MissingField;
        } else return error.MissingField;

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.InsertFailed;
        }

        try self.commit();
    }

    pub fn resolveQuestion(self: *Database, question_id: []const u8, resolution: ?[]const u8, resolved_by: ?[]const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

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

        try self.commit();
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
                try writer.print("\n  \"{s}\": {{\n    \"status\": \"{s}\",\n    \"files\": [", .{ task_id, status });
                current_task = task_id;
                if (file_path != null) {
                    try writer.print("\"{s}\"", .{try Database.escapeJsonString(allocator, std.mem.span(file_path))});
                }
            } else if (file_path != null) {
                try writer.print(", \"{s}\"", .{try Database.escapeJsonString(allocator, std.mem.span(file_path))});
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
        try writer.print("  \"file_path\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, file_path)});
        try writer.print("  \"requesting_task\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, task_id)});

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const owner_id = std.mem.span(c.sqlite3_column_text(stmt, 0));
            const owner_status = std.mem.span(c.sqlite3_column_text(stmt, 1));

            try writer.print("  \"owned_by\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, owner_id)});
            try writer.print("  \"owner_status\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, owner_status)});

            if (std.mem.eql(u8, owner_status, "DONE")) {
                try writer.writeAll("  \"action\": \"error\",\n");
                try writer.print("  \"message\": \"File is owned by DONE task {s}. Modifications require explicit approval.\"\n", .{ owner_id });
            } else {
                try writer.writeAll("  \"action\": \"warn\",\n");
                try writer.print("  \"message\": \"File is owned by in-progress task {s}.\"\n", .{ owner_id });
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

        try self.beginImmediate();
        errdefer self.rollback();

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

        try self.commit();
    }

    pub fn listOperations(self: *Database, allocator: std.mem.Allocator, task_id: ?[]const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const writer = output.writer();

        try writer.writeAll("[\n");

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = if (task_id != null)
            "SELECT id, operation_id, task_id, timestamp, caller FROM operation_log WHERE task_id = ? ORDER BY timestamp DESC"
        else
            "SELECT id, operation_id, task_id, timestamp, caller FROM operation_log ORDER BY timestamp DESC";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        if (task_id) |t| {
            _ = c.sqlite3_bind_text(stmt, 1, t.ptr, @intCast(t.len), c.SQLITE_STATIC);
        }

        var first = true;
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            if (!first) try writer.writeAll(",\n");
            first = false;

            try writer.writeAll("  {\n");
            try writer.print("    \"id\": {d},\n", .{c.sqlite3_column_int(stmt, 0)});
            try writer.print("    \"operation_id\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 1)))});

            const tid = c.sqlite3_column_text(stmt, 2);
            if (tid != null) {
                try writer.print("    \"task_id\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(tid))});
            } else {
                try writer.writeAll("    \"task_id\": null,\n");
            }

            try writer.print("    \"timestamp\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 3)))});

            const caller = c.sqlite3_column_text(stmt, 4);
            if (caller != null) {
                try writer.print("    \"caller\": \"{s}\"\n", .{try Database.escapeJsonString(allocator, std.mem.span(caller))});
            } else {
                try writer.writeAll("    \"caller\": null\n");
            }
            try writer.writeAll("  }");
        }

        try writer.writeAll("\n]");
        return output.toOwnedSlice();
    }

    pub fn getOperation(self: *Database, allocator: std.mem.Allocator, operation_id: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const writer = output.writer();

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT id, operation_id, task_id, timestamp, caller, input_json, output_json, exit_code FROM operation_log WHERE operation_id = ? ORDER BY timestamp DESC LIMIT 1";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, operation_id.ptr, @intCast(operation_id.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            try writer.writeAll("{\n");
            try writer.print("  \"id\": {d},\n", .{c.sqlite3_column_int(stmt, 0)});
            try writer.print("  \"operation_id\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 1)))});

            const tid = c.sqlite3_column_text(stmt, 2);
            if (tid != null) {
                try writer.print("  \"task_id\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(tid))});
            } else {
                try writer.writeAll("  \"task_id\": null,\n");
            }

            try writer.print("  \"timestamp\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(c.sqlite3_column_text(stmt, 3)))});

            const caller = c.sqlite3_column_text(stmt, 4);
            if (caller != null) {
                try writer.print("  \"caller\": \"{s}\",\n", .{try Database.escapeJsonString(allocator, std.mem.span(caller))});
            } else {
                try writer.writeAll("  \"caller\": null,\n");
            }

            const input_json = c.sqlite3_column_text(stmt, 5);
            if (input_json != null) {
                try writer.print("  \"input_json\": {s},\n", .{std.mem.span(input_json)});
            } else {
                try writer.writeAll("  \"input_json\": null,\n");
            }

            const output_json = c.sqlite3_column_text(stmt, 6);
            if (output_json != null) {
                try writer.print("  \"output_json\": {s},\n", .{std.mem.span(output_json)});
            } else {
                try writer.writeAll("  \"output_json\": null,\n");
            }

            if (c.sqlite3_column_type(stmt, 7) != c.SQLITE_NULL) {
                try writer.print("  \"exit_code\": {d}\n", .{c.sqlite3_column_int(stmt, 7)});
            } else {
                try writer.writeAll("  \"exit_code\": null\n");
            }
            try writer.writeAll("}");
        } else {
            return error.OperationNotFound;
        }

        return output.toOwnedSlice();
    }

    pub fn updateReviewMetadata(self: *Database, task_id: []const u8, metadata_json: ?[]const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "UPDATE tasks SET review_metadata = ? WHERE id = ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        if (metadata_json) |json| {
            _ = c.sqlite3_bind_text(stmt, 1, json.ptr, @intCast(json.len), c.SQLITE_STATIC);
        } else {
            _ = c.sqlite3_bind_null(stmt, 1);
        }
        _ = c.sqlite3_bind_text(stmt, 2, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.UpdateFailed;
        }

        try self.commit();
    }

    pub fn getReviewMetadata(self: *Database, allocator: std.mem.Allocator, task_id: []const u8) !?[]const u8 {
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT review_metadata FROM tasks WHERE id = ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const val = c.sqlite3_column_text(stmt, 0);
            if (val != null) {
                return try allocator.dupe(u8, std.mem.span(val));
            }
        }
        return null;
    }

    // ============================================================
    // PHASE 1: Maintenance Story
    // ============================================================

    pub fn createTask(self: *Database, task_id: []const u8, story_id: ?[]const u8, title: []const u8, description: ?[]const u8, labels: ?[]const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        const actual_story = story_id orelse "__maintenance__";
        const desc = description orelse "";

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO tasks (id, story_id, title, description, status, labels) VALUES (?, ?, ?, ?, 'TODO', ?)";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, actual_story.ptr, @intCast(actual_story.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 3, title.ptr, @intCast(title.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 4, desc.ptr, @intCast(desc.len), c.SQLITE_STATIC);
        if (labels) |l| {
            _ = c.sqlite3_bind_text(stmt, 5, l.ptr, @intCast(l.len), c.SQLITE_STATIC);
        } else {
            _ = c.sqlite3_bind_null(stmt, 5);
        }

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            const err = c.sqlite3_errmsg(self.db);
            std.debug.print("Create task failed: {s}\n", .{err});
            return error.InsertFailed;
        }

        try self.commit();
    }

    pub fn moveTask(self: *Database, task_id: []const u8, new_story_id: []const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        // Check task is not DONE
        var check_stmt: ?*c.sqlite3_stmt = null;
        _ = c.sqlite3_prepare_v2(self.db, "SELECT status FROM tasks WHERE id = ?", -1, &check_stmt, null);
        if (check_stmt) |s| {
            defer _ = c.sqlite3_finalize(s);
            _ = c.sqlite3_bind_text(s, 1, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);
            if (c.sqlite3_step(s) == c.SQLITE_ROW) {
                const status = std.mem.span(c.sqlite3_column_text(s, 0));
                if (std.mem.eql(u8, status, "DONE")) {
                    return error.CannotMoveDoneTask;
                }
            } else {
                return error.TaskNotFound;
            }
        }

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "UPDATE tasks SET story_id = ? WHERE id = ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, new_story_id.ptr, @intCast(new_story_id.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, task_id.ptr, @intCast(task_id.len), c.SQLITE_STATIC);

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.UpdateFailed;
        }

        try self.commit();
    }

    pub fn listTasks(self: *Database, allocator: std.mem.Allocator, story_id: ?[]const u8, maintenance_only: bool, status_filter: ?[]const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const w = output.writer();

        var sql_buf = std.ArrayList(u8).init(allocator);
        defer sql_buf.deinit();
        const sw = sql_buf.writer();
        try sw.writeAll("SELECT id, title, description, status, assigned_to, context_priority, review_status, story_id, labels FROM tasks WHERE 1=1");

        if (maintenance_only) {
            try sw.writeAll(" AND story_id = '__maintenance__'");
        } else if (story_id != null) {
            try sw.writeAll(" AND story_id = ?");
        }

        if (status_filter != null) {
            try sw.writeAll(" AND status = ?");
        }

        try sw.writeAll(" ORDER BY id");

        try w.writeAll("[\n");

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql_buf.items.ptr, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        var param_idx: c_int = 1;
        if (!maintenance_only and story_id != null) {
            const sid = story_id.?;
            _ = c.sqlite3_bind_text(stmt, param_idx, sid.ptr, @intCast(sid.len), c.SQLITE_STATIC);
            param_idx += 1;
        }
        if (status_filter) |sf| {
            _ = c.sqlite3_bind_text(stmt, param_idx, sf.ptr, @intCast(sf.len), c.SQLITE_STATIC);
            param_idx += 1;
        }

        var first = true;
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            if (!first) try w.writeAll(",\n");
            first = false;

            try w.print("  {{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"assigned_to\":", .{
                try Database.escapeJsonString(allocator, ct(stmt, 0)),
                try Database.escapeJsonString(allocator, ct(stmt, 1)),
                try Database.escapeJsonString(allocator, ct(stmt, 3)),
            });

            const assigned = c.sqlite3_column_text(stmt, 4);
            if (assigned != null) {
                try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, std.mem.span(assigned))});
            } else {
                try w.writeAll("null");
            }

            try w.print(",\"story_id\":\"{s}\"", .{try Database.escapeJsonString(allocator, ct(stmt, 7))});

            const labels = c.sqlite3_column_text(stmt, 8);
            if (labels != null) {
                try w.print(",\"labels\":{s}", .{std.mem.span(labels)});
            } else {
                try w.writeAll(",\"labels\":null");
            }

            try w.writeAll("}");
        }

        try w.writeAll("\n]");
        return output.toOwnedSlice();
    }

    // ============================================================
    // PHASE 2: Multi-Story
    // ============================================================

    pub fn createStory(self: *Database, id: []const u8, title: []const u8, branch: ?[]const u8, worktree_path: ?[]const u8, parent_story: ?[]const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO stories (id, acts_version, title, status, spec_approved, type, branch, worktree_path, parent_story) VALUES (?, '1.0.0', ?, 'ANALYSIS', 0, 'feature', ?, ?, ?)";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, id.ptr, @intCast(id.len), c.SQLITE_STATIC);
        _ = c.sqlite3_bind_text(stmt, 2, title.ptr, @intCast(title.len), c.SQLITE_STATIC);
        if (branch) |b| { _ = c.sqlite3_bind_text(stmt, 3, b.ptr, @intCast(b.len), c.SQLITE_STATIC); } else { _ = c.sqlite3_bind_null(stmt, 3); }
        if (worktree_path) |wp| { _ = c.sqlite3_bind_text(stmt, 4, wp.ptr, @intCast(wp.len), c.SQLITE_STATIC); } else { _ = c.sqlite3_bind_null(stmt, 4); }
        if (parent_story) |ps| { _ = c.sqlite3_bind_text(stmt, 5, ps.ptr, @intCast(ps.len), c.SQLITE_STATIC); } else { _ = c.sqlite3_bind_null(stmt, 5); }

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            const err = c.sqlite3_errmsg(self.db);
            std.debug.print("Create story failed: {s}\n", .{err});
            return error.InsertFailed;
        }

        // Ensure maintenance story exists
        _ = c.sqlite3_exec(self.db, ensure_maintenance_sql, null, null, null);

        try self.commit();
    }

    pub fn listStories(self: *Database, allocator: std.mem.Allocator, include_archived: bool, include_maintenance: bool) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const w = output.writer();

        var sql_buf = std.ArrayList(u8).init(allocator);
        defer sql_buf.deinit();
        const sw = sql_buf.writer();
        try sw.writeAll("SELECT id, title, status, type, branch, semver, parent_story FROM stories WHERE 1=1");
        if (!include_archived) {
            try sw.writeAll(" AND status != 'ARCHIVED'");
        }
        if (!include_maintenance) {
            try sw.writeAll(" AND id != '__maintenance__'");
        }
        try sw.writeAll(" ORDER BY id");

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql_buf.items.ptr, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        try w.writeAll("[\n");
        var first = true;
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            if (!first) try w.writeAll(",\n");
            first = false;
            try w.print("  {{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"type\":\"{s}\",\"branch\":", .{
                try Database.escapeJsonString(allocator, ct(stmt, 0)),
                try Database.escapeJsonString(allocator, ct(stmt, 1)),
                try Database.escapeJsonString(allocator, ct(stmt, 2)),
                try Database.escapeJsonString(allocator, ct(stmt, 3)),
            });
            const branch = ct(stmt, 4);
            if (branch.len > 0) try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, branch)}) else try w.writeAll("null");
            const semver = ct(stmt, 5);
            try w.writeAll(",\"semver\":");
            if (semver.len > 0) try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, semver)}) else try w.writeAll("null");
            const parent = ct(stmt, 6);
            try w.writeAll(",\"parent\":");
            if (parent.len > 0) try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, parent)}) else try w.writeAll("null");
            try w.writeAll("}");
        }
        try w.writeAll("\n]");
        return output.toOwnedSlice();
    }

    pub fn switchStory(self: *Database, story_id: []const u8) !void {
        // Verify story exists and is not archived
        var check_stmt: ?*c.sqlite3_stmt = null;
        _ = c.sqlite3_prepare_v2(self.db, "SELECT status FROM stories WHERE id = ?", -1, &check_stmt, null);
        if (check_stmt) |s| {
            defer _ = c.sqlite3_finalize(s);
            _ = c.sqlite3_bind_text(s, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);
            if (c.sqlite3_step(s) == c.SQLITE_ROW) {
                const status = std.mem.span(c.sqlite3_column_text(s, 0));
                if (std.mem.eql(u8, status, "ARCHIVED")) return error.StoryArchived;
            } else {
                return error.StoryNotFound;
            }
        }

        try self.beginImmediate();
        errdefer self.rollback();

        // Delete current active story
        _ = c.sqlite3_exec(self.db, "DELETE FROM active_story", null, null, null);

        // Insert new active story
        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO active_story (story_id) VALUES (?)";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.InsertFailed;
        }

        try self.commit();
    }

    pub fn archiveStory(self: *Database, story_id: []const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        // Check all tasks are DONE
        var check_stmt: ?*c.sqlite3_stmt = null;
        _ = c.sqlite3_prepare_v2(self.db, "SELECT COUNT(*) FROM tasks WHERE story_id = ? AND status != 'DONE'", -1, &check_stmt, null);
        if (check_stmt) |s| {
            defer _ = c.sqlite3_finalize(s);
            _ = c.sqlite3_bind_text(s, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);
            if (c.sqlite3_step(s) == c.SQLITE_ROW and c.sqlite3_column_int(s, 0) > 0) {
                return error.OpenTasksRemain;
            }
        }

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "UPDATE stories SET status = 'ARCHIVED', archived_at = strftime('%s','now') WHERE id = ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.UpdateFailed;
        }

        // Remove from active_story if active
        _ = c.sqlite3_exec(self.db, "DELETE FROM active_story WHERE story_id = ?", null, null, null);
        // Need to bind - use exec with formatted SQL
        var del_stmt: ?*c.sqlite3_stmt = null;
        _ = c.sqlite3_prepare_v2(self.db, "DELETE FROM active_story WHERE story_id = ?", -1, &del_stmt, null);
        if (del_stmt) |ds| {
            defer _ = c.sqlite3_finalize(ds);
            _ = c.sqlite3_bind_text(ds, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);
            _ = c.sqlite3_step(ds);
        }

        try self.commit();
    }

    pub fn addStoryGate(self: *Database, story_id: []const u8, gate_type: []const u8, status: []const u8, approved_by: ?[]const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT INTO story_gates (story_id, gate_type, status, approved_by) VALUES (?, ?, ?, ?)";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);
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

        try self.commit();
    }

    pub fn getStoryGraph(self: *Database, allocator: std.mem.Allocator, format: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const w = output.writer();

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT id, title, parent_story, status FROM stories WHERE parent_story IS NOT NULL AND status != 'ARCHIVED'";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        if (std.mem.eql(u8, format, "dot")) {
            try w.writeAll("digraph stories {\n");
            while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
                try w.print("  \"{s}\" -> \"{s}\";\n", .{ ct(stmt, 2), ct(stmt, 0) });
            }
            try w.writeAll("}\n");
        } else {
            try w.writeAll("[\n");
            var first = true;
            while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
                if (!first) try w.writeAll(",\n");
                first = false;
                try w.print("  {{\"id\":\"{s}\",\"title\":\"{s}\",\"parent\":\"{s}\",\"status\":\"{s}\"}}", .{
                    try Database.escapeJsonString(allocator, ct(stmt, 0)),
                    try Database.escapeJsonString(allocator, ct(stmt, 1)),
                    try Database.escapeJsonString(allocator, ct(stmt, 2)),
                    try Database.escapeJsonString(allocator, ct(stmt, 3)),
                });
            }
            try w.writeAll("\n]");
        }

        return output.toOwnedSlice();
    }

    // ============================================================
    // PHASE 3: Proactive Triggers
    // ============================================================

    pub fn setPresence(self: *Database, agent_id: []const u8, story_id: ?[]const u8, task_id: ?[]const u8, action: ?[]const u8) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "INSERT OR REPLACE INTO agent_presence (agent_id, story_id, task_id, current_action, heartbeat) VALUES (?, ?, ?, ?, strftime('%s','now'))";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_text(stmt, 1, agent_id.ptr, @intCast(agent_id.len), c.SQLITE_STATIC);
        if (story_id) |s| { _ = c.sqlite3_bind_text(stmt, 2, s.ptr, @intCast(s.len), c.SQLITE_STATIC); } else { _ = c.sqlite3_bind_null(stmt, 2); }
        if (task_id) |t| { _ = c.sqlite3_bind_text(stmt, 3, t.ptr, @intCast(t.len), c.SQLITE_STATIC); } else { _ = c.sqlite3_bind_null(stmt, 3); }
        if (action) |a| { _ = c.sqlite3_bind_text(stmt, 4, a.ptr, @intCast(a.len), c.SQLITE_STATIC); } else { _ = c.sqlite3_bind_null(stmt, 4); }

        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.InsertFailed;
        }

        try self.commit();
    }

    pub fn listPresence(self: *Database, allocator: std.mem.Allocator, story_id: ?[]const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const w = output.writer();

        var sql_buf = std.ArrayList(u8).init(allocator);
        defer sql_buf.deinit();
        const sw = sql_buf.writer();
        try sw.writeAll("SELECT agent_id, story_id, task_id, current_action, heartbeat FROM agent_presence WHERE heartbeat > (strftime('%s','now') - 300)");
        if (story_id != null) {
            try sw.writeAll(" AND story_id = ?");
        }
        try sw.writeAll(" ORDER BY agent_id");

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql_buf.items.ptr, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        if (story_id) |s| {
            _ = c.sqlite3_bind_text(stmt, 1, s.ptr, @intCast(s.len), c.SQLITE_STATIC);
        }

        try w.writeAll("[\n");
        var first = true;
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            if (!first) try w.writeAll(",\n");
            first = false;
            try w.print("  {{\"agent_id\":\"{s}\",\"story_id\":", .{try Database.escapeJsonString(allocator, ct(stmt, 0))});
            const sid = ct(stmt, 1);
            if (sid.len > 0) try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, sid)}) else try w.writeAll("null");
            try w.writeAll(",\"task_id\":");
            const tid = ct(stmt, 2);
            if (tid.len > 0) try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, tid)}) else try w.writeAll("null");
            try w.writeAll(",\"action\":");
            const act = ct(stmt, 3);
            if (act.len > 0) try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, act)}) else try w.writeAll("null");
            try w.print(",\"heartbeat\":{s}}}", .{ct(stmt, 4)});
        }
        try w.writeAll("\n]");
        return output.toOwnedSlice();
    }

    pub fn listUnblockEvents(self: *Database, allocator: std.mem.Allocator, acknowledged: bool) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const w = output.writer();

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "SELECT id, unblocked_task_id, unblocked_by, created_at, acknowledged FROM unblock_events ORDER BY created_at DESC";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        try w.writeAll("[\n");
        var first = true;
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            const ack = c.sqlite3_column_int(stmt, 4);
            if (acknowledged and ack == 0) continue;
            if (!acknowledged and ack != 0) continue;

            if (!first) try w.writeAll(",\n");
            first = false;
            try w.print("  {{\"id\":{d},\"unblocked_task\":\"{s}\",\"unblocked_by\":\"{s}\",\"created_at\":\"{s}\",\"acknowledged\":{s}}}", .{
                c.sqlite3_column_int(stmt, 0),
                try Database.escapeJsonString(allocator, ct(stmt, 1)),
                try Database.escapeJsonString(allocator, ct(stmt, 2)),
                try Database.escapeJsonString(allocator, ct(stmt, 3)),
                if (ack != 0) "true" else "false",
            });
        }
        try w.writeAll("\n]");
        return output.toOwnedSlice();
    }

    pub fn ackUnblockEvent(self: *Database, event_id: i32) !void {
        try self.beginImmediate();
        errdefer self.rollback();

        var stmt: ?*c.sqlite3_stmt = null;
        const sql = "UPDATE unblock_events SET acknowledged = 1 WHERE id = ?";
        const rc = c.sqlite3_prepare_v2(self.db, sql, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        _ = c.sqlite3_bind_int(stmt, 1, event_id);
        if (c.sqlite3_step(stmt) != c.SQLITE_DONE) {
            return error.UpdateFailed;
        }

        try self.commit();
    }

    pub fn listReviewQueue(self: *Database, allocator: std.mem.Allocator, story_id: ?[]const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const w = output.writer();

        var sql_buf = std.ArrayList(u8).init(allocator);
        defer sql_buf.deinit();
        const sw = sql_buf.writer();
        try sw.writeAll("SELECT rq.id, rq.task_id, rq.requested_by, rq.requested_at, rq.status, t.title, t.story_id FROM review_queue rq JOIN tasks t ON t.id = rq.task_id WHERE 1=1");
        if (story_id != null) {
            try sw.writeAll(" AND t.story_id = ?");
        }
        try sw.writeAll(" ORDER BY rq.requested_at DESC");

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql_buf.items.ptr, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        if (story_id) |s| {
            _ = c.sqlite3_bind_text(stmt, 1, s.ptr, @intCast(s.len), c.SQLITE_STATIC);
        }

        try w.writeAll("[\n");
        var first = true;
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            if (!first) try w.writeAll(",\n");
            first = false;
            try w.print("  {{\"id\":{d},\"task_id\":\"{s}\",\"title\":\"{s}\",\"story_id\":\"{s}\",\"requested_by\":", .{
                c.sqlite3_column_int(stmt, 0),
                try Database.escapeJsonString(allocator, ct(stmt, 1)),
                try Database.escapeJsonString(allocator, ct(stmt, 5)),
                try Database.escapeJsonString(allocator, ct(stmt, 6)),
            });
            const req = c.sqlite3_column_text(stmt, 2);
            if (req != null) try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, std.mem.span(req))}) else try w.writeAll("null");
            try w.print(",\"status\":\"{s}\",\"requested_at\":\"{s}\"}}", .{
                try Database.escapeJsonString(allocator, ct(stmt, 4)),
                try Database.escapeJsonString(allocator, ct(stmt, 3)),
            });
        }
        try w.writeAll("\n]");
        return output.toOwnedSlice();
    }

    pub fn listGateSla(self: *Database, allocator: std.mem.Allocator, breached_only: bool) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const w = output.writer();

        var sql_buf = std.ArrayList(u8).init(allocator);
        defer sql_buf.deinit();
        const sw = sql_buf.writer();
        try sw.writeAll("SELECT gs.gate_id, gs.deadline, gs.breached, gc.task_id, gc.gate_type, gc.status FROM gate_sla gs JOIN gate_checkpoints gc ON gc.id = gs.gate_id WHERE 1=1");
        if (breached_only) {
            try sw.writeAll(" AND gs.breached = 1");
        }
        try sw.writeAll(" ORDER BY gs.deadline");

        var stmt: ?*c.sqlite3_stmt = null;
        const rc = c.sqlite3_prepare_v2(self.db, sql_buf.items.ptr, -1, &stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(stmt);

        try w.writeAll("[\n");
        var first = true;
        while (c.sqlite3_step(stmt) == c.SQLITE_ROW) {
            if (!first) try w.writeAll(",\n");
            first = false;
            const breached = c.sqlite3_column_int(stmt, 2);
            try w.print("  {{\"gate_id\":{d},\"task_id\":\"{s}\",\"gate_type\":\"{s}\",\"gate_status\":\"{s}\",\"deadline\":\"{s}\",\"breached\":{s}}}", .{
                c.sqlite3_column_int(stmt, 0),
                try Database.escapeJsonString(allocator, ct(stmt, 3)),
                try Database.escapeJsonString(allocator, ct(stmt, 4)),
                try Database.escapeJsonString(allocator, ct(stmt, 5)),
                try Database.escapeJsonString(allocator, ct(stmt, 1)),
                if (breached != 0) "true" else "false",
            });
        }
        try w.writeAll("\n]");
        return output.toOwnedSlice();
    }

    // ============================================================
    // PHASE 4: Changelog
    // ============================================================

    pub fn generateChangelog(self: *Database, allocator: std.mem.Allocator, story_id: []const u8, format: []const u8) ![]u8 {
        var output = std.ArrayList(u8).init(allocator);
        defer output.deinit();
        const w = output.writer();

        // Query DONE tasks for this story
        var task_stmt: ?*c.sqlite3_stmt = null;
        const task_sql = "SELECT id, title, assigned_to, labels FROM tasks WHERE story_id = ? AND status = 'DONE' ORDER BY id";
        const rc = c.sqlite3_prepare_v2(self.db, task_sql, -1, &task_stmt, null);
        if (rc != c.SQLITE_OK) return error.QueryFailed;
        defer _ = c.sqlite3_finalize(task_stmt);

        _ = c.sqlite3_bind_text(task_stmt, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);

        var added = std.ArrayList([]const u8).init(allocator);
        defer { for (added.items) |s| allocator.free(s); added.deinit(); }
        var fixed = std.ArrayList([]const u8).init(allocator);
        defer { for (fixed.items) |s| allocator.free(s); fixed.deinit(); }
        var changed = std.ArrayList([]const u8).init(allocator);
        defer { for (changed.items) |s| allocator.free(s); changed.deinit(); }

        while (c.sqlite3_step(task_stmt) == c.SQLITE_ROW) {
            const tid = std.mem.span(c.sqlite3_column_text(task_stmt, 0));
            const title = std.mem.span(c.sqlite3_column_text(task_stmt, 1));
            const assigned = c.sqlite3_column_text(task_stmt, 2);
            const labels_raw = c.sqlite3_column_text(task_stmt, 3);

            // Get reviewer
            var reviewer: []const u8 = "unreviewed";
            var gate_stmt: ?*c.sqlite3_stmt = null;
            _ = c.sqlite3_prepare_v2(self.db, "SELECT approved_by FROM gate_checkpoints WHERE task_id = ? AND gate_type = 'task-review' AND status = 'approved' LIMIT 1", -1, &gate_stmt, null);
            if (gate_stmt) |gs| {
                defer _ = c.sqlite3_finalize(gs);
                _ = c.sqlite3_bind_text(gs, 1, tid.ptr, @intCast(tid.len), c.SQLITE_STATIC);
                if (c.sqlite3_step(gs) == c.SQLITE_ROW) {
                    reviewer = std.mem.span(c.sqlite3_column_text(gs, 0));
                }
            }

            // Get files
            var files_buf = std.ArrayList(u8).init(allocator);
            defer files_buf.deinit();
            var fw = files_buf.writer();
            var file_stmt: ?*c.sqlite3_stmt = null;
            _ = c.sqlite3_prepare_v2(self.db, "SELECT file_path FROM task_files WHERE task_id = ?", -1, &file_stmt, null);
            if (file_stmt) |fs| {
                defer _ = c.sqlite3_finalize(fs);
                _ = c.sqlite3_bind_text(fs, 1, tid.ptr, @intCast(tid.len), c.SQLITE_STATIC);
                var first_f = true;
                while (c.sqlite3_step(fs) == c.SQLITE_ROW) {
                    if (!first_f) try fw.writeAll(", ");
                    first_f = false;
                    try fw.print("{s}", .{std.mem.span(c.sqlite3_column_text(fs, 0))});
                }
            }
            const files_str = try files_buf.toOwnedSlice();
            defer allocator.free(files_str);

            const assigned_str = if (assigned != null) std.mem.span(assigned) else "unassigned";

            const entry = try std.fmt.allocPrint(allocator, "- {s} {s} ({s}, reviewed by {s}) — {s}", .{ tid, title, assigned_str, reviewer, files_str });
            errdefer allocator.free(entry);

            // Categorize by labels or title heuristics
            const labels_str = if (labels_raw != null) std.mem.span(labels_raw) else "";
            const title_lower = try std.ascii.allocLowerString(allocator, title);
            defer allocator.free(title_lower);

            var categorized = false;
            if (std.mem.indexOf(u8, labels_str, "feat") != null or
                std.mem.indexOf(u8, title_lower, "feat:") != null or
                std.mem.indexOf(u8, title_lower, "add ") != null or
                std.mem.indexOf(u8, title_lower, "implement") != null)
            {
                try added.append(entry);
                categorized = true;
            }
            if (std.mem.indexOf(u8, labels_str, "fix") != null or
                std.mem.indexOf(u8, labels_str, "bug") != null or
                std.mem.indexOf(u8, title_lower, "fix:") != null or
                std.mem.indexOf(u8, title_lower, "bug") != null)
            {
                try fixed.append(entry);
                categorized = true;
            }
            if (std.mem.indexOf(u8, labels_str, "refactor") != null or
                std.mem.indexOf(u8, labels_str, "change") != null or
                std.mem.indexOf(u8, title_lower, "refactor:") != null)
            {
                try changed.append(entry);
                categorized = true;
            }
            if (!categorized) {
                try added.append(entry); // default to Added
            }
        }

        // Query decisions
        var decisions_buf = std.ArrayList(u8).init(allocator);
        defer decisions_buf.deinit();
        var dw = decisions_buf.writer();
        var dec_stmt: ?*c.sqlite3_stmt = null;
        _ = c.sqlite3_prepare_v2(self.db,
            "SELECT d.topic, d.decided FROM decisions d JOIN tasks t ON t.id = d.task_id WHERE t.story_id = ?",
            -1, &dec_stmt, null);
        if (dec_stmt) |ds| {
            defer _ = c.sqlite3_finalize(ds);
            _ = c.sqlite3_bind_text(ds, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);
            while (c.sqlite3_step(ds) == c.SQLITE_ROW) {
                try dw.print("- {s}: {s}\n", .{ std.mem.span(c.sqlite3_column_text(ds, 0)), std.mem.span(c.sqlite3_column_text(ds, 1)) });
            }
        }

        // Query rejected approaches
        var rejected_buf = std.ArrayList(u8).init(allocator);
        defer rejected_buf.deinit();
        var rw = rejected_buf.writer();
        var rej_stmt: ?*c.sqlite3_stmt = null;
        _ = c.sqlite3_prepare_v2(self.db,
            "SELECT r.approach, r.reason FROM rejected_approaches r JOIN tasks t ON t.id = r.task_id WHERE t.story_id = ?",
            -1, &rej_stmt, null);
        if (rej_stmt) |rs| {
            defer _ = c.sqlite3_finalize(rs);
            _ = c.sqlite3_bind_text(rs, 1, story_id.ptr, @intCast(story_id.len), c.SQLITE_STATIC);
            while (c.sqlite3_step(rs) == c.SQLITE_ROW) {
                try rw.print("- {s} (rationale: {s})\n", .{ std.mem.span(c.sqlite3_column_text(rs, 0)), std.mem.span(c.sqlite3_column_text(rs, 1)) });
            }
        }

        if (std.mem.eql(u8, format, "json")) {
            try w.print("{{\"story_id\":\"{s}\",\"added\":[", .{story_id});
            for (added.items, 0..) |item, i| {
                if (i > 0) try w.writeAll(",");
                try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, item)});
            }
            try w.writeAll("],\"fixed\":[");
            for (fixed.items, 0..) |item, i| {
                if (i > 0) try w.writeAll(",");
                try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, item)});
            }
            try w.writeAll("],\"changed\":[");
            for (changed.items, 0..) |item, i| {
                if (i > 0) try w.writeAll(",");
                try w.print("\"{s}\"", .{try Database.escapeJsonString(allocator, item)});
            }
            try w.writeAll("]}");
        } else {
            // Markdown / keepachangelog
            try w.print("## [{s}]\n", .{story_id});

            if (added.items.len > 0) {
                try w.writeAll("### Added\n");
                for (added.items) |item| {
                    try w.print("{s}\n", .{item});
                }
            }
            if (fixed.items.len > 0) {
                try w.writeAll("### Fixed\n");
                for (fixed.items) |item| {
                    try w.print("{s}\n", .{item});
                }
            }
            if (changed.items.len > 0) {
                try w.writeAll("### Changed\n");
                for (changed.items) |item| {
                    try w.print("{s}\n", .{item});
                }
            }
            if (decisions_buf.items.len > 0) {
                try w.writeAll("### Decisions\n");
                try w.writeAll(decisions_buf.items);
            }
            if (rejected_buf.items.len > 0) {
                try w.writeAll("### Rejected approaches\n");
                try w.writeAll(rejected_buf.items);
            }
        }

        return output.toOwnedSlice();
    }
};
