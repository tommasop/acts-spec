# ACTS CLI Bug Fixes

## Bug 1: Memory leaks in `listStories` and `listTasks`

**File:** `acts-core/src/db.zig`

Every call to `Database.escapeJsonString()` allocates memory that is never freed. In both `listStories` (line 1682-1695) and `listTasks` (line 1594-1607), the returned slices are passed directly to `w.print()` and lost.

**Fix:** Store each escaped result in a variable, use it, then free it.

### `listStories` (lines 1682-1696)

Replace:
```zig
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
```

With:
```zig
const eid = try Database.escapeJsonString(allocator, ct(stmt, 0));
defer allocator.free(eid);
const etitle = try Database.escapeJsonString(allocator, ct(stmt, 1));
defer allocator.free(etitle);
const estatus = try Database.escapeJsonString(allocator, ct(stmt, 2));
defer allocator.free(estatus);
const etype = try Database.escapeJsonString(allocator, ct(stmt, 3));
defer allocator.free(etype);
try w.print("  {{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"type\":\"{s}\",\"branch\":", .{
    eid, etitle, estatus, etype,
});
const branch = ct(stmt, 4);
if (branch.len > 0) {
    const ebranch = try Database.escapeJsonString(allocator, branch);
    defer allocator.free(ebranch);
    try w.print("\"{s}\"", .{ebranch});
} else try w.writeAll("null");
const semver = ct(stmt, 5);
try w.writeAll(",\"semver\":");
if (semver.len > 0) {
    const esemver = try Database.escapeJsonString(allocator, semver);
    defer allocator.free(esemver);
    try w.print("\"{s}\"", .{esemver});
} else try w.writeAll("null");
const parent = ct(stmt, 6);
try w.writeAll(",\"parent\":");
if (parent.len > 0) {
    const eparent = try Database.escapeJsonString(allocator, parent);
    defer allocator.free(eparent);
    try w.print("\"{s}\"", .{eparent});
} else try w.writeAll("null");
try w.writeAll("}");
```

### `listTasks` (lines 1594-1616)

Replace:
```zig
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
```

With:
```zig
const eid = try Database.escapeJsonString(allocator, ct(stmt, 0));
defer allocator.free(eid);
const etitle = try Database.escapeJsonString(allocator, ct(stmt, 1));
defer allocator.free(etitle);
const estatus = try Database.escapeJsonString(allocator, ct(stmt, 3));
defer allocator.free(estatus);
try w.print("  {{\"id\":\"{s}\",\"title\":\"{s}\",\"status\":\"{s}\",\"assigned_to\":", .{
    eid, etitle, estatus,
});

const assigned = c.sqlite3_column_text(stmt, 4);
if (assigned != null) {
    const eassigned = try Database.escapeJsonString(allocator, std.mem.span(assigned));
    defer allocator.free(eassigned);
    try w.print("\"{s}\"", .{eassigned});
} else {
    try w.writeAll("null");
}

const estory = try Database.escapeJsonString(allocator, ct(stmt, 7));
defer allocator.free(estory);
try w.print(",\"story_id\":\"{s}\"", .{estory});

const labels = c.sqlite3_column_text(stmt, 8);
if (labels != null) {
    try w.print(",\"labels\":{s}", .{std.mem.span(labels)});
} else {
    try w.writeAll(",\"labels\":null");
}

try w.writeAll("}");
```

---

## Bug 2: Unbound SQL parameters in `listTasks`

**File:** `acts-core/src/db.zig`, lines 1557-1587

When `maintenance_only=false` and `story_id=null` (default for `acts task list`), the SQL includes `AND story_id = ?` but nothing is bound.

**Fix:** Only add the `?` placeholder when we will actually bind a value.

Replace lines 1557-1567:
```zig
try sw.writeAll("SELECT id, title, description, status, assigned_to, context_priority, review_status, story_id, labels FROM tasks WHERE 1=1");

if (maintenance_only) {
    try sw.writeAll(" AND story_id = '__maintenance__'");
} else if (story_id != null) {
    try sw.writeAll(" AND story_id = ?");
}

if (status_filter != null) {
    try sw.writeAll(" AND status = ?");
}
```

With:
```zig
try sw.writeAll("SELECT id, title, description, status, assigned_to, context_priority, review_status, story_id, labels FROM tasks WHERE 1=1");

if (maintenance_only) {
    try sw.writeAll(" AND story_id = '__maintenance__'");
}
// No else branch — when story_id is null and not maintenance, don't filter by story

if (status_filter != null) {
    try sw.writeAll(" AND status = ?");
}
```

And fix the binding (lines 1578-1587):
```zig
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
```

Replace with:
```zig
var param_idx: c_int = 1;
if (story_id) |sid| {
    _ = c.sqlite3_bind_text(stmt, param_idx, sid.ptr, @intCast(sid.len), c.SQLITE_STATIC);
    param_idx += 1;
}
if (status_filter) |sf| {
    _ = c.sqlite3_bind_text(stmt, param_idx, sf.ptr, @intCast(sf.len), c.SQLITE_STATIC);
    param_idx += 1;
}
```

---

## Bug 3: Version string mismatch

**File:** `acts-core/src/main.zig`, line 88

The help banner hardcodes `v1.1.0` while `acts version` uses `build_options.version`.

Replace line 88:
```zig
\\ACTS Core v1.1.0 - Agent Collaborative Tracking Standard
```

With:
```zig
try stdout.print("ACTS Core {s} - Agent Collaborative Tracking Standard\n", .{build_options.version});
```

And remove the hardcoded version from the raw string. The `printUsage()` function needs to be refactored from a single `writeAll` to use `print` for the version line.

Alternatively, change the raw string to not include the version on that line, and print it separately before the rest.

---

## Bug 4: Better error reporting for `QueryFailed`

**File:** `acts-core/src/db.zig` (multiple locations)

Currently `QueryFailed` gives no context. Replace bare `return error.QueryFailed` after `sqlite3_prepare_v2` with an error message that includes the SQLite error.

For `listStories` (line 1673-1674):
```zig
const rc = c.sqlite3_prepare_v2(self.db, sql_buf.items.ptr, -1, &stmt, null);
if (rc != c.SQLITE_OK) return error.QueryFailed;
```

Replace with:
```zig
const rc = c.sqlite3_prepare_v2(self.db, sql_buf.items.ptr, -1, &stmt, null);
if (rc != c.SQLITE_OK) {
    const errmsg = c.sqlite3_errmsg(self.db);
    std.debug.print("QueryFailed: {s}\n", .{std.mem.span(errmsg)});
    return error.QueryFailed;
}
```

Same pattern for `listTasks` (line 1574-1575) and other critical query paths.

---

## Build & test

```bash
cd acts-core
zig build
./zig-out/bin/acts version
./zig-out/bin/acts help | head -1
```
