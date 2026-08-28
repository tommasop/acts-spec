# Single-Branch Stacks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the nested stacked-branch model with single-branch stacks: one feature branch per stack, changes as checkpoints (`start_sha`/`end_sha`), one PR per stack, whole-branch landing.

**Architecture:** A stack creates a feature branch `acts/<id>/feature` off the current branch (captured as `base_branch`, e.g. `master`). `acts change add` records `start_sha = HEAD` instead of creating a branch. `acts review` creates/updates ONE PR (`feature` → `base_branch`). `acts stack land` refuses unless all changes are APPROVED, then does one `git merge --no-ff feature` into the integration branch and closes the PR. Legacy v2 manifests (per-change `branch`/`parent`) still parse and validate.

**Tech Stack:** Zig 0.13 (acts-core binary), Node.js (OpenCode plugin), archify (diagrams).

**Spec:** `docs/superpowers/specs/2026-08-28-single-branch-stacks-design.md`

---

## File map

| File | Responsibility after change |
|---|---|
| `acts-core/src/stack.zig` | v3 manifest schema: `branchOf`, `integrationBranch`, `start_sha`/`end_sha`, `stackPrUrl`, `changeDiffRange`, `allApproved`, `unapprovedChanges`, tolerant `validate` |
| `acts-core/src/git.zig` | Add `headSha`, `mergeNoFf` |
| `acts-core/src/main.zig` | Rework stack/change/verify/review/approve/land/scope/validate/migrate/risk/context wiring |
| `acts-core/src/context.zig` | v3 context pack (feature branch, preceding changes, range-based files) |
| `acts-core/src/diagram.zig` | Per-change ranges (`start_sha..end_sha`) + whole-stack `cmdStackDiagram` |
| `.opencode/plugins/acts.js` | v3 active-change resolution, system context, blast radius |
| `tests/acts-plugin.test.mjs` | v3 manifest fixture + assertions |
| Docs | README, INTEGRATION, SKILL, AGENTS, setup `agents_section`, MIGRATION, faq, minimal-viable-acts, example-* |

Build/test commands:
- Zig: `cd acts-core && zig build test` (unit tests), `zig build` (binary)
- Plugin: `npm test`
- Gate: `acts verify <id>` → `npm test && cd acts-core && zig build test`, `node --check .opencode/plugins/acts.js`, `cd acts-core && zig build`

---

## Task 1: `git.zig` helpers

**Files:**
- Modify: `acts-core/src/git.zig` (append before the final `diffAdditions` section)

- [ ] **Step 1: Add `headSha` and `mergeNoFf`**

```zig
/// Full SHA of HEAD. Empty on failure.
pub fn headSha(arena: std.mem.Allocator) ![]const u8 {
    const res = try run(arena, &.{ "git", "rev-parse", "HEAD" }, 512);
    if (res.exit_code != 0) return "";
    return std.mem.trim(u8, res.stdout, " \n\r");
}

/// Merge `branch` into the current branch with --no-ff (used by stack land).
pub fn mergeNoFf(arena: std.mem.Allocator, branch: []const u8, message: []const u8) !CmdResult {
    return run(arena, &.{ "git", "merge", "--no-ff", branch, "-m", message }, 8192);
}
```

- [ ] **Step 2: Verify it builds**

Run: `cd acts-core && zig build`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add acts-core/src/git.zig
git commit -m "feat: git headSha + mergeNoFf helpers (single-branch landing)"
```

---

## Task 2: `stack.zig` v3 schema + helpers (TDD)

**Files:**
- Modify: `acts-core/src/stack.zig`
- Test: `acts-core/src/stack.zig` (tests appended at end)

- [ ] **Step 1: Write failing tests** (append at end of `stack.zig`)

```zig
test "v3 manifest validates and legacy v2 still validates" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // v3 fixture
    var r3 = std.json.ObjectMap.init(a);
    try r3.put("version", .{ .integer = 3 });
    try r3.put("id", .{ .string = "auth" });
    try r3.put("title", .{ .string = "Add auth" });
    try r3.put("branch", .{ .string = "acts/auth/feature" });
    try r3.put("base_branch", .{ .string = "master" });
    var ch3 = std.json.Array.init(a);
    var c3 = std.json.ObjectMap.init(a);
    try c3.put("id", .{ .string = "c1" });
    try c3.put("title", .{ .string = "JWT" });
    try c3.put("status", .{ .string = "TODO" });
    try c3.put("start_sha", .{ .string = "abc" });
    try ch3.append(.{ .object = c3 });
    try r3.put("changes", .{ .array = ch3 });
    const v3: std.json.Value = .{ .object = r3 };
    const problems3 = try validate(a, v3);
    try std.testing.expectEqual(@as(usize, 0), std.mem.trim(u8, problems3, " \n\r").len);

    // v2 fixture (per-change branch, no start_sha) still validates
    var r2 = std.json.ObjectMap.init(a);
    try r2.put("version", .{ .integer = 2 });
    try r2.put("id", .{ .string = "legacy" });
    try r2.put("title", .{ .string = "Legacy" });
    try r2.put("base_branch", .{ .string = "acts/legacy/base" });
    var ch2 = std.json.Array.init(a);
    var c2 = std.json.ObjectMap.init(a);
    try c2.put("id", .{ .string = "c1" });
    try c2.put("title", .{ .string = "JWT" });
    try c2.put("status", .{ .string = "MERGED" });
    try c2.put("branch", .{ .string = "acts/legacy/c1-jwt" });
    try ch2.append(.{ .object = c2 });
    try r2.put("changes", .{ .array = ch2 });
    const v2: std.json.Value = .{ .object = r2 };
    const problems2 = try validate(a, v2);
    try std.testing.expectEqual(@as(usize, 0), std.mem.trim(u8, problems2, " \n\r").len);

    // v3 change missing both branch and start_sha → error
    var cbad = std.json.ObjectMap.init(a);
    try cbad.put("id", .{ .string = "c2" });
    try cbad.put("title", .{ .string = "Bad" });
    try cbad.put("status", .{ .string = "TODO" });
    var chbad = std.json.Array.init(a);
    try chbad.append(.{ .object = cbad });
    try r3.put("changes", .{ .array = chbad });
    const vbad: std.json.Value = .{ .object = r3 };
    const problems_bad = try validate(a, vbad);
    try std.testing.expect(std.mem.indexOf(u8, problems_bad, "branch") != null or std.mem.indexOf(u8, problems_bad, "start_sha") != null);
}

test "branchOf and changeDiffRange resolve v3 checkpoints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var r = std.json.ObjectMap.init(a);
    try r.put("version", .{ .integer = 3 });
    try r.put("branch", .{ .string = "acts/auth/feature" });
    try r.put("base_branch", .{ .string = "master" });
    var ch = std.json.Array.init(a);
    var c = std.json.ObjectMap.init(a);
    try c.put("id", .{ .string = "c1" });
    try c.put("status", .{ .string = "TODO" });
    try c.put("start_sha", .{ .string = "abc" });
    try c.put("end_sha", .{ .string = "def" });
    try ch.append(.{ .object = c });
    try r.put("changes", .{ .array = ch });
    const v: std.json.Value = .{ .object = r };

    try std.testing.expectEqualStrings("acts/auth/feature", branchOf(v).?);
    try std.testing.expectEqualStrings("master", integrationBranch(v));
    const range = changeDiffRange(v, "c1");
    try std.testing.expectEqualStrings("abc", range.from);
    try std.testing.expectEqualStrings("def", range.to);
    try std.testing.expect(allApproved(v) == false);
    const un = try unapprovedChanges(a, v);
    try std.testing.expectEqual(@as(usize, 1), un.len);
    try std.testing.expectEqualStrings("c1", un[0]);
}

test "setStackPrUrl roundtrips and allApproved" {
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
    try c1.put("status", .{ .string = "APPROVED" });
    try ch.append(.{ .object = c1 });
    var c2 = std.json.ObjectMap.init(a);
    try c2.put("id", .{ .string = "c2" });
    try c2.put("status", .{ .string = "APPROVED" });
    try ch.append(.{ .object = c2 });
    try r.put("changes", .{ .array = ch });
    const v: std.json.Value = .{ .object = r };

    _ = try setStackPrUrl(a, v, "https://github.com/x/pull/9");
    try std.testing.expectEqualStrings("https://github.com/x/pull/9", stackPrUrl(v).?);
    try std.testing.expect(allApproved(v));
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `cd acts-core && zig build test`
Expected: compile errors (`branchOf`, `changeDiffRange`, `allApproved`, `unapprovedChanges`, `setStackPrUrl`, `stackPrUrl`, `integrationBranch` undeclared) and/or `validate` failures.

- [ ] **Step 3: Implement the schema helpers** (insert after `changeStatus` in `stack.zig`)

```zig
/// The stack's feature branch (root `branch`); legacy v2 falls back to the old
/// `base_branch` (which then meant the stack's own base branch).
pub fn branchOf(v: std.json.Value) ?[]const u8 {
    if (v.object.get("branch")) |b| {
        if (b == .string and b.string.len > 0) return b.string;
    }
    if (v.object.get("base_branch")) |b| {
        if (b == .string and b.string.len > 0) return b.string;
    }
    return null;
}

/// The integration target (master/main) this stack merges into. In v3 this is
/// captured in root `base_branch` at stack-create time.
pub fn integrationBranch(v: std.json.Value) []const u8 {
    if (v.object.get("base_branch")) |b| {
        if (b == .string) return b.string;
    }
    return "";
}

pub fn setBranch(allocator: std.mem.Allocator, v: std.json.Value, branch: []const u8) !bool {
    try v.object.put("branch", .{ .string = branch });
    return true;
}
```

- [ ] **Step 4: Implement change-range + approval helpers** (insert after `changeStatus`/before `parentOf`)

```zig
pub fn changeStartSha(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    if (m.get("start_sha")) |s| {
        if (s == .string and s.string.len > 0) return s.string;
    }
    return null;
}

pub fn setChangeStartSha(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, sha: []const u8) !bool {
    const m = getChange(v, id) orelse return false;
    try m.put("start_sha", .{ .string = sha });
    return true;
}

pub fn changeEndSha(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    if (m.get("end_sha")) |s| {
        if (s == .string and s.string.len > 0) return s.string;
    }
    return null;
}

pub fn setChangeEndSha(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, sha: []const u8) !bool {
    const m = getChange(v, id) orelse return false;
    try m.put("end_sha", .{ .string = sha });
    return true;
}

/// True when this is a legacy v2 change (per-change `branch`, no `start_sha`).
pub fn changeIsLegacy(v: std.json.Value, id: []const u8) bool {
    return legacyChangeBranch(v, id) != null and changeStartSha(v, id) == null;
}

pub fn legacyChangeBranch(v: std.json.Value, id: []const u8) ?[]const u8 {
    const m = getChange(v, id) orelse return null;
    if (m.get("branch")) |b| {
        if (b == .string and b.string.len > 0) return b.string;
    }
    return null;
}

/// The git diff range that defines a change's scope.
///   v3: start_sha .. end_sha (end_sha = "HEAD" while open)
///   v2 legacy: integration branch .. change branch
pub const DiffRange = struct { from: []const u8, to: []const u8 };

pub fn changeDiffRange(v: std.json.Value, id: []const u8) DiffRange {
    if (changeStartSha(v, id)) |start| {
        return .{ .from = start, .to = changeEndSha(v, id) orelse "HEAD" };
    }
    if (legacyChangeBranch(v, id)) |cbranch| {
        return .{ .from = integrationBranch(v), .to = cbranch };
    }
    return .{ .from = "", .to = "" };
}

/// Stack-level PR URL (one PR per stack, v3). Legacy v2 used per-change `pr`.
pub fn stackPrUrl(v: std.json.Value) ?[]const u8 {
    const pr = v.object.get("pr") orelse return null;
    if (pr != .object) return null;
    if (pr.object.get("url")) |u| {
        if (u == .string and u.string.len > 0) return u.string;
    }
    return null;
}

pub fn setStackPrUrl(allocator: std.mem.Allocator, v: std.json.Value, url: []const u8) !bool {
    const gop = try v.object.getOrPut("pr");
    if (!gop.found_existing) gop.value_ptr.* = .{ .object = std.json.ObjectMap.init(allocator) };
    try gop.value_ptr.*.object.put("url", .{ .string = url });
    return true;
}

/// True when every non-merged change is APPROVED.
pub fn allApproved(v: std.json.Value) bool {
    const changes = v.object.get("changes") orelse return false;
    if (changes != .array) return false;
    var any_non_merged = false;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const st = c.object.get("status") orelse continue;
        const s = if (st == .string) st.string else "";
        if (std.mem.eql(u8, s, status_merged)) continue;
        any_non_merged = true;
        if (!std.mem.eql(u8, s, status_approved)) return false;
    }
    return any_non_merged;
}

/// Ids of non-merged changes that are not APPROVED.
pub fn unapprovedChanges(allocator: std.mem.Allocator, v: std.json.Value) ![][]const u8 {
    var out = std.ArrayList([]const u8).init(allocator);
    const changes = v.object.get("changes") orelse return out.toOwnedSlice();
    if (changes != .array) return out.toOwnedSlice();
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const st = c.object.get("status") orelse continue;
        const s = if (st == .string) st.string else "";
        if (std.mem.eql(u8, s, status_merged)) continue;
        if (std.mem.eql(u8, s, status_approved)) continue;
        if (c.object.get("id")) |idv| {
            if (idv == .string) try out.append(idv.string);
        }
    }
    return out.toOwnedSlice();
}
```

- [ ] **Step 5: Update `validate` for v2/v3** (replace the body of `validate` in `stack.zig`)

```zig
pub fn validate(allocator: std.mem.Allocator, v: std.json.Value) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    const root = &v.object;

    var ver: i64 = 0;
    if (root.get("version")) |verv| {
        if (verv == .integer) ver = verv.integer;
    }
    if (ver != 2 and ver != 3) {
        try out.writer().print("manifest version must be 2 or 3 (got {any})\n", .{root.get("version")});
    }
    if (root.get("id") == null) try out.appendSlice("missing 'id'\n");
    if (root.get("title") == null) try out.appendSlice("missing 'title'\n");
    // v3: feature `branch` + integration `base_branch`. v2: `base_branch` only.
    if (ver == 3 and root.get("branch") == null) try out.appendSlice("missing 'branch'\n");
    if (root.get("base_branch") == null) try out.appendSlice("missing 'base_branch'\n");

    const changes = root.get("changes") orelse {
        try out.appendSlice("missing 'changes'\n");
        return out.toOwnedSlice();
    };
    if (changes != .array) {
        try out.appendSlice("'changes' must be an array\n");
        return out.toOwnedSlice();
    }

    for (changes.array.items) |*c| {
        if (c.* != .object) {
            try out.appendSlice("change entry is not an object\n");
            continue;
        }
        const id = c.object.get("id") orelse {
            try out.appendSlice("change missing 'id'\n");
            continue;
        };
        const id_str = if (id == .string) id.string else "";
        if (c.object.get("title") == null) try out.writer().print("change {s}: missing 'title'\n", .{id_str});
        if (c.object.get("status") == null) try out.writer().print("change {s}: missing 'status'\n", .{id_str});
        const has_branch = c.object.get("branch") != null;
        const has_start = c.object.get("start_sha") != null;
        if (!has_branch and !has_start) {
            try out.writer().print("change {s}: missing 'branch' (legacy v2) or 'start_sha' (v3)\n", .{id_str});
        }
        if (c.object.get("acceptance") != null) {
            if (c.object.get("acceptance").? != .array) {
                try out.writer().print("change {s}: 'acceptance' must be array\n", .{id_str});
            }
        }
        if (c.object.get("parent") != null and c.object.get("parent").? != .null and c.object.get("parent").? != .string) {
            try out.writer().print("change {s}: 'parent' must be string or null\n", .{id_str});
        }
    }
    return out.toOwnedSlice();
}
```

- [ ] **Step 6: Run tests, verify they pass**

Run: `cd acts-core && zig build test`
Expected: PASS (3 new tests).

- [ ] **Step 7: Commit**

```bash
git add acts-core/src/stack.zig
git commit -m "feat: v3 manifest schema — feature branch, change checkpoints, stack PR, allApproved"
```

---

## Task 3: `main.zig` pure resolvers (TDD)

**Files:**
- Modify: `acts-core/src/main.zig`
- Test: `acts-core/src/main.zig` (append at end)

- [ ] **Step 1: Write failing tests** (append at end of `main.zig`)

```zig
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
    // legacy per-change branch match
    try std.testing.expect(activeChangeForBranch(v, "master") == null);
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
    try r.put("changes", .{ .array = ch });
    const v: std.json.Value = .{ .object = r };

    const body = try buildReviewBody(a, v);
    try std.testing.expect(std.mem.indexOf(u8, body, "Add auth") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "JWT middleware") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "token validated") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "npm test") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "LOW") != null);
}
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `cd acts-core && zig build test`
Expected: compile errors (`activeChangeForBranch`, `buildReviewBody` undeclared).

- [ ] **Step 3: Implement `activeChangeForBranch`** (add before `resolveCurrentChange` in `main.zig`)

```zig
/// Resolve the active change for a checked-out branch. On the stack's feature
/// branch this is the top (last non-merged) change; on any other branch it
/// matches a legacy v2 per-change branch, else null.
fn activeChangeForBranch(v: std.json.Value, branch: []const u8) ?[]const u8 {
    const changes = v.object.get("changes") orelse return null;
    if (changes != .array) return null;
    const feat = stack.branchOf(v) orelse "";
    if (std.mem.eql(u8, branch, feat)) {
        var top: ?[]const u8 = null;
        for (changes.array.items) |*c| {
            if (c.* != .object) continue;
            if (c.object.get("status")) |st| {
                if (st == .string and std.mem.eql(u8, st.string, stack.status_merged)) continue;
            }
            if (c.object.get("id")) |idv| {
                if (idv == .string) top = idv.string;
            }
        }
        return top;
    }
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
```

- [ ] **Step 4: Rewrite `resolveCurrentChange` to use it**

Replace the body of `resolveCurrentChange` (currently at `main.zig:1522`):

```zig
fn resolveCurrentChange(allocator: std.mem.Allocator, v: std.json.Value) ?[]const u8 {
    const branch = git.currentBranch(allocator) catch null orelse return null;
    return activeChangeForBranch(v, branch);
}
```

- [ ] **Step 5: Implement `buildReviewBody`** (add after `computeRiskForChange` in `main.zig`)

```zig
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
            }
        }
    }
    try w.writeAll("\n---\nGenerated by ACTS. Review the changes and approve each checkpoint before `acts stack land`.\n");
    return buf.toOwnedSlice();
}
```

- [ ] **Step 6: Run tests, verify they pass**

Run: `cd acts-core && zig build test`
Expected: PASS (2 new tests).

- [ ] **Step 7: Commit**

```bash
git add acts-core/src/main.zig
git commit -m "feat: active change resolution + whole-stack PR body builder"
```

---

## Task 4: `cmdStackCreate` v3

**Files:**
- Modify: `acts-core/src/main.zig:348` (`cmdStackCreate`)

- [ ] **Step 1: Rewrite `cmdStackCreate`**

Replace the whole function body:

```zig
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
```

- [ ] **Step 2: Verify it builds**

Run: `cd acts-core && zig build`
Expected: exit 0.

- [ ] **Step 3: Manual smoke check (in a throwaway temp repo, not acts-spec)**

```bash
T=$(mktemp -d) && cd "$T" && git init -q && git commit -q --allow-empty -m init
# build the binary first
cd /home/tommasop/code/ai/acts-spec && cd acts-core && zig build && cd "$T"
/home/tommasop/code/ai/acts-spec/acts-core/zig-out/bin/acts stack create auth -t "Add auth"
```
Expected: `stack auth created on feature branch acts/auth/feature (off master)`; `.acts/stack.json` has `version: 3`, `branch`, `base_branch: master`, `pr`, `changes: []`. Then clean up: `rm -rf "$T"`.

- [ ] **Step 4: Commit**

```bash
git add acts-core/src/main.zig
git commit -m "feat: stack create — feature branch + v3 manifest"
```

---

## Task 5: `cmdChangeAdd` v3 (checkpoint)

**Files:**
- Modify: `acts-core/src/main.zig:499` (`cmdChangeAdd`)

- [ ] **Step 1: Rewrite `cmdChangeAdd`**

Replace the whole function body (no branch creation, no parent, no per-change pr):

```zig
fn cmdChangeAdd(allocator: std.mem.Allocator, id: []const u8, args: *const Args) !void {
    if (!validId(id)) return error.InvalidChangeId;
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) != null) return error.ChangeExists;

    const title = args.flag("--title") orelse args.flag("-t") orelse return error.MissingTitle;
    const root = &v.object;
    const sid = if (root.get("id")) |s| if (s == .string) s.string else "" else "";
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
```

- [ ] **Step 2: Verify it builds**

Run: `cd acts-core && zig build`
Expected: exit 0.

- [ ] **Step 3: Manual smoke check (temp repo)**

```bash
T=$(mktemp -d) && cd "$T" && git init -q && git commit -q --allow-empty -m init
B=/home/tommasop/code/ai/acts-spec/acts-core/zig-out/bin/acts
$B stack create auth -t "Add auth" >/dev/null
$B change add c1 -t "JWT middleware" --accept "token validated"
cat .acts/stack.json
```
Expected: change c1 has `start_sha` (a 40-char SHA) and `end_sha: null`, no `branch`, no `parent`. `git branch --show-current` is still `acts/auth/feature`. Clean up: `rm -rf "$T"`.

- [ ] **Step 4: Commit**

```bash
git add acts-core/src/main.zig
git commit -m "feat: change add — record checkpoint start_sha, no branch"
```

---

## Task 6: `cmdStackStatus` + `cmdChangeStatus` v3

**Files:**
- Modify: `acts-core/src/main.zig:376` (`cmdStackStatus`), `:564` (`cmdChangeStatus`)

- [ ] **Step 1: Rewrite `cmdStackStatus` (linear, with PR)**

Replace the body:

```zig
fn cmdStackStatus(allocator: std.mem.Allocator, args: *const Args) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    const root = &v.object;
    const sid = if (root.get("id")) |s| if (s == .string) s.string else "" else "";
    const stitle = if (root.get("title")) |s| if (s == .string) s.string else "" else "";
    const feat = stack.branchOf(v) orelse "";
    const integ = stack.integrationBranch(v);

    try stdout("Stack: {s} — {s}\n", .{ sid, stitle });
    try stdout("  feature: {s} (off {s})\n", .{ feat, integ });
    if (stack.stackPrUrl(v)) |url| {
        try stdout("  PR: {s}\n", .{url});
    }

    const changes = root.get("changes") orelse return;
    if (changes != .array) return;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const m = &c.*.object;
        const cid = if (m.get("id")) |s| if (s == .string) s.string else "" else "";
        const ctitle = if (m.get("title")) |s| if (s == .string) s.string else "" else "";
        const cstatus = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
        const start = if (stack.changeStartSha(v, cid)) |s| s[0..@min(@as(usize, 7), s.len)] else "-";
        const end = if (stack.changeEndSha(v, cid)) |s| s[0..@min(@as(usize, 7), s.len)] else "…";
        try stdout("  [{s}] {s}  {s}  ({s}..{s})\n", .{ if (std.mem.eql(u8, cstatus, stack.status_merged)) "x" else " ", cstatus, ctitle, start, end });
    }

    if (args.has("--json")) {
        var buf = std.ArrayList(u8).init(allocator);
        defer buf.deinit();
        try std.json.stringify(v, .{ .whitespace = .indent_2 }, buf.writer());
        try stdout("{s}\n", .{buf.items});
    }
}
```

- [ ] **Step 2: Rewrite `cmdChangeStatus` (SHAs + diff stat)**

Replace the body of `cmdChangeStatus` (currently at `main.zig:564`) with:

```zig
fn cmdChangeStatus(allocator: std.mem.Allocator, id_arg: ?[]const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    const id = id_arg orelse (resolveCurrentChange(allocator, v) orelse return error.NoActiveChange);
    const m = stack.getChange(v, id) orelse return error.ChangeNotFound;

    const ctitle = if (m.get("title")) |s| if (s == .string) s.string else "" else "";
    const cstatus = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
    const start = stack.changeStartSha(v, id) orelse "-";
    const end = stack.changeEndSha(v, id) orelse "HEAD";
    const risk = stack.getRisk(v, id) orelse "UNKNOWN";

    try stdout("Change: {s} — {s}\n", .{ id, ctitle });
    try stdout("  status: {s}\n", .{cstatus});
    try stdout("  range: {s}..{s}\n", .{ start, end });
    try stdout("  risk: {s}\n", .{risk});

    const range = stack.changeDiffRange(v, id);
    if (range.from.len > 0 and range.to.len > 0) {
        const stat = try git.run(allocator, &.{ "git", "diff", "--stat", range.from, range.to }, 8192);
        if (stat.exit_code == 0 and std.mem.trim(u8, stat.stdout, " \n\r").len > 0) {
            try stdout("{s}\n", .{stat.stdout});
        }
    }
}
```

- [ ] **Step 3: Verify it builds**

Run: `cd acts-core && zig build`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add acts-core/src/main.zig
git commit -m "feat: stack/change status — linear view with checkpoint ranges"
```

---

## Task 7: `cmdVerify` / `runVerifyForChange` v3

**Files:**
- Modify: `acts-core/src/main.zig:609` (`cmdVerify`), `:644` (`runVerifyForChange`), `:732` (`failingFilesOwnedByChange`)

- [ ] **Step 1: Update `cmdVerify` base resolution**

In `cmdVerify`, replace:

```zig
const base = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";
```
with:
```zig
const base = stack.integrationBranch(v);
```

- [ ] **Step 2: Rewrite `runVerifyForChange` (no checkout, freeze end_sha, range-based risk)**

Replace the whole function:

```zig
fn runVerifyForChange(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, base: []const u8, force: bool, manual: ?[]const u8, reason: ?[]const u8) !bool {
    // v3: there is no per-change branch — gates run on the feature branch.
    // Legacy v2 changes still get their branch checked out.
    const m = stack.getChange(v, id).?;
    if (stack.legacyChangeBranch(v, id)) |cbranch| {
        const cur = (try git.currentBranch(allocator)) orelse "";
        if (!std.mem.eql(u8, cur, cbranch)) {
            _ = try git.checkoutBranch(allocator, cbranch);
        }
    }

    var all_ok = true;

    // ── Manual verification: skip gates entirely, record evidence ──
    if (manual) |evidence| {
        _ = try stack.setVerifyForced(allocator, v, id, "manual", evidence);
        _ = try stack.setChangeString(v, id, "status", stack.status_verified);
        const head = try git.headSha(allocator);
        if (head.len > 0) _ = try stack.setChangeEndSha(allocator, v, id, head);
        const base_sha = try git.refSha(allocator, base);
        if (base_sha.len > 0) _ = try stack.setVerifyBaseSha(allocator, v, id, base_sha);
        const range = stack.changeDiffRange(v, id);
        const tier = try computeRiskForChange(allocator, v, id, range.from, range.to);
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

    const range = stack.changeDiffRange(v, id);

    // ── Force override with enforcement ──
    if (!all_ok and force) {
        const fail_owned = try failingFilesOwnedByChange(allocator, range.from, range.to, failing_outputs.items);
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

    // Freeze the change's scope at the verified HEAD.
    const head = try git.headSha(allocator);
    if (head.len > 0) _ = try stack.setChangeEndSha(allocator, v, id, head);

    // Record the integration SHA verification ran against (stale-verify guard).
    const base_sha = try git.refSha(allocator, base);
    if (base_sha.len > 0) {
        _ = try stack.setVerifyBaseSha(allocator, v, id, base_sha);
    }
    const tier = try computeRiskForChange(allocator, v, id, range.from, range.to);
    _ = try stack.setRisk(v, id, tier.label());
    try stdout("  risk: {s}\n", .{tier.label()});

    return all_ok or (force and stack.isVerifyForced(v, id));
}
```

- [ ] **Step 3: Update `failingFilesOwnedByChange` to take a range**

Replace `failingFilesOwnedByChange` (at `main.zig:732`):

```zig
fn failingFilesOwnedByChange(allocator: std.mem.Allocator, from: []const u8, to: []const u8, output: []const u8) !bool {
    const owned = if (from.len > 0) try git.diffNameOnly(allocator, from, to) else &[_][]const u8{};
    return failingFilesOwnedByChangeWithOwned(output, owned);
}
```

- [ ] **Step 4: Verify build + existing tests**

Run: `cd acts-core && zig build && zig build test`
Expected: exit 0; the existing `failingFilesOwnedByChangeWithOwned` test still passes.

- [ ] **Step 5: Commit**

```bash
git add acts-core/src/main.zig
git commit -m "feat: verify freezes end_sha, runs on feature branch, range-based risk"
```

---

## Task 8: `cmdRisk` + `computeRiskForChange` v3

**Files:**
- Modify: `acts-core/src/main.zig:945` (`cmdRisk`), `:976` (`computeRiskForChange`), `:999` (`crossRepoEdgeCount`)

- [ ] **Step 1: Update `computeRiskForChange` and `crossRepoEdgeCount` to ranges**

Replace `computeRiskForChange` (signature becomes `from`/`to`):

```zig
fn computeRiskForChange(allocator: std.mem.Allocator, v: std.json.Value, id: []const u8, from: []const u8, to: []const u8) !risk.RiskTier {
    const files = if (from.len > 0) try git.diffNameOnly(allocator, from, to) else &[_][]const u8{};
    const adds = if (from.len > 0) try diffAdditionsRange(allocator, from, to) else 0;

    var cross: usize = try crossRepoEdgeCount(allocator, from, to);
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
```

Replace `crossRepoEdgeCount` (at `main.zig:999`):

```zig
fn crossRepoEdgeCount(allocator: std.mem.Allocator, from: []const u8, to: []const u8) !usize {
    const files = if (from.len > 0) try git.diffNameOnly(allocator, from, to) else &[_][]const u8{};
    var count: usize = 0;
    for (files) |f| {
        if (std.mem.startsWith(u8, f, "../")) count += 1;
    }
    return count;
}
```

- [ ] **Step 2: Add `diffAdditionsRange` helper** (near `cmdRisk`)

```zig
/// Count of added lines between two refs (range version of git.diffAdditions).
fn diffAdditionsRange(allocator: std.mem.Allocator, from: []const u8, to: []const u8) !usize {
    const res = try git.run(allocator, &.{ "git", "diff", "--numstat", from, to }, 65536);
    if (res.exit_code != 0) return 0;
    var total: usize = 0;
    var it = std.mem.tokenizeAny(u8, res.stdout, "\n");
    while (it.next()) |line| {
        var f = std.mem.tokenizeAny(u8, line, "\t ");
        if (f.next()) |add| {
            if (std.mem.eql(u8, add, "-")) continue;
            total += std.fmt.parseInt(usize, add, 10) catch 0;
        }
    }
    return total;
}
```

- [ ] **Step 3: Update `cmdRisk` to use the change's range**

Replace the body of `cmdRisk`:

```zig
fn cmdRisk(allocator: std.mem.Allocator, id: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) == null) return error.ChangeNotFound;
    const range = stack.changeDiffRange(v, id);

    const tier = try computeRiskForChange(allocator, v, id, range.from, range.to);
    _ = try stack.setRisk(v, id, tier.label());
    try stack.save(allocator, v);

    const files = if (range.from.len > 0) try git.diffNameOnly(allocator, range.from, range.to) else &[_][]const u8{};
    const adds = try diffAdditionsRange(allocator, range.from, range.to);
    const verified = stack.verifyAllPassed(v, id);

    try stdout("risk for {s}: {s}\n", .{ id, tier.label() });
    try stdout("  files: {d} | additions: {d} | verified: {s}\n", .{ files.len, adds, if (verified) "yes" else "no" });
    if (tier == .LOW) {
        try stdout("  → LOW: eligible for auto-land after all changes approved\n", .{});
    } else if (tier == .HIGH or tier == .CRITICAL) {
        try stdout("  → {s}: requires human review + escalation checklist\n", .{tier.label()});
    }
}
```

- [ ] **Step 4: Verify build**

Run: `cd acts-core && zig build && zig build test`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add acts-core/src/main.zig
git commit -m "feat: risk computed from change checkpoint range"
```

---

## Task 9: `cmdReview` v3 (one PR)

**Files:**
- Modify: `acts-core/src/main.zig:739` (`cmdReview`)

- [ ] **Step 1: Rewrite `cmdReview` (whole-stack PR create/update)**

Replace the whole function:

```zig
fn cmdReview(allocator: std.mem.Allocator, id: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    // The change id is accepted for familiarity but review covers the whole stack.
    if (stack.getChange(v, id) == null) return error.ChangeNotFound;

    const feat = stack.branchOf(v) orelse return error.ManifestInvalid;
    const integ = stack.integrationBranch(v);
    const stitle = if (v.object.get("title")) |s| if (s == .string) s.string else "" else "";

    // Every non-merged change must be verified before the PR is reviewable.
    if (!stack.allVerified(v)) return error.VerifyRequired;

    // Ensure we're on the feature branch so the PR reflects its code.
    const cur_branch = (try git.currentBranch(allocator)) orelse "";
    if (!std.mem.eql(u8, cur_branch, feat)) {
        _ = try git.checkoutBranch(allocator, feat);
    }

    // Compute risk for every change (whole-stack summary).
    const changes = v.object.get("changes") orelse return error.ManifestInvalid;
    if (changes == .array) {
        for (changes.array.items) |*c| {
            if (c.* != .object) continue;
            const cid = if (c.object.get("id")) |x| if (x == .string) x.string else "" else "";
            if (cid.len == 0) continue;
            const range = stack.changeDiffRange(v, cid);
            const tier = try computeRiskForChange(allocator, v, cid, range.from, range.to);
            _ = try stack.setRisk(v, cid, tier.label());
        }
    }

    // Push the feature branch.
    var pr_submitted = false;
    const remote = git.defaultRemote(allocator) orelse blk: {
        try stdout("note: no git remote configured — cannot submit PR. Commit and push manually.\n", .{});
        break :blk "";
    };
    if (remote.len > 0) {
        const push_res = try git.pushBranch(allocator, remote, feat);
        if (push_res.exit_code != 0) {
            try stderr("git push: {s}\n", .{std.mem.trim(u8, push_res.stderr, " \n\r")});
            return error.PushFailed;
        }
        pr_submitted = true;
    }

    // Build the whole-stack PR body.
    const body = try buildReviewBody(allocator, v);

    const tools = git.detectTools(allocator);
    var pr_url = stack.stackPrUrl(v);
    const existing = pr_url != null;

    if (pr_submitted and tools.gh) {
        if (existing) {
            const edit = try git.run(allocator, &.{ "gh", "pr", "edit", pr_url.?, "--body", body }, 16384);
            if (edit.exit_code != 0) {
                try stderr("gh pr edit: {s}\n", .{std.mem.trim(u8, edit.stderr, " \n\r")});
            }
        } else {
            const create = try git.run(allocator, &.{
                "gh", "pr", "create",
                "--head", feat,
                "--base", integ,
                "--title", stitle,
                "--body", body,
            }, 16384);
            if (create.exit_code == 0) {
                const trimmed = std.mem.trim(u8, create.stdout, " \n\r");
                if (trimmed.len > 0) {
                    pr_url = trimmed;
                    _ = try stack.setStackPrUrl(allocator, v, trimmed);
                }
            } else {
                try stderr("gh pr create: {s}\n", .{std.mem.trim(u8, create.stderr, " \n\r")});
            }
        }
    } else if (pr_submitted and !tools.gh) {
        try stdout("note: `gh` not found — branch pushed to {s}; create the PR manually.\n", .{remote});
    }

    // The whole stack is under review via the one PR.
    if (changes == .array) {
        for (changes.array.items) |*c| {
            if (c.* != .object) continue;
            const st = c.object.get("status") orelse continue;
            const s = if (st == .string) st.string else "";
            if (!std.mem.eql(u8, s, stack.status_merged)) {
                _ = try stack.setChangeString(v, if (c.object.get("id")) |x| if (x == .string) x.string else "" else "", "status", stack.status_in_review);
            }
        }
    }
    try stack.save(allocator, v);

    if (pr_url) |url| {
        try stdout("PR submitted: {s}\n", .{url});
        // Attach the whole-stack archify delta (best-effort, non-blocking).
        const cwd = std.fs.cwd().realpathAlloc(allocator, ".") catch ".";
        diagram.cmdStackDiagram(allocator, cwd, true, true) catch |err| {
            try stderr("note: archify attach skipped ({s}) — review is not blocked.\n", .{@errorName(err)});
        };
    }
}
```

- [ ] **Step 2: Add `stack.allVerified`** (in `stack.zig`, after `allApproved`)

```zig
/// True when every non-merged change has verification evidence that passed.
pub fn allVerified(v: std.json.Value) bool {
    const changes = v.object.get("changes") orelse return false;
    if (changes != .array) return false;
    var any_non_merged = false;
    for (changes.array.items) |*c| {
        if (c.* != .object) continue;
        const st = c.object.get("status") orelse continue;
        const s = if (st == .string) st.string else "";
        if (std.mem.eql(u8, s, status_merged)) continue;
        any_non_merged = true;
        if (c.object.get("id")) |idv| {
            if (idv == .string and !verifyAllPassed(v, idv.string)) return false;
        }
    }
    return any_non_merged;
}
```

- [ ] **Step 3: Remove the old auto-land block from `cmdReview`**

The old function's auto-land (LOW risk) block is gone with the rewrite; confirm no references to `autoLandLowEnabled` remain broken by checking:

Run: `cd acts-core && zig build && zig build test`
Expected: exit 0. If `autoLandLowEnabled` is now unused, keep it (referenced later by land) or remove if the compiler warns — Zig only errors on unused *parameters*, not unused functions.

- [ ] **Step 4: Commit**

```bash
git add acts-core/src/main.zig acts-core/src/stack.zig
git commit -m "feat: review — one PR per stack (create or update), whole-stack body + archify delta"
```

---

## Task 10: `cmdApprove` / `cmdRework` — drop per-change `pr.approved`

**Files:**
- Modify: `acts-core/src/main.zig:880` (`cmdApprove`), `:894` (`cmdRework`)

- [ ] **Step 1: Edit `cmdApprove`**

Replace the `setPrApproved` line:

```zig
    if (stack.getChange(v, id) == null) return error.ChangeNotFound;
    const tier = stack.getRisk(v, id) orelse "UNKNOWN";
    _ = try stack.appendApproval(allocator, v, id, "approve", "developer", tier, "human PR approval");
    _ = try stack.setChangeString(v, id, "status", stack.status_approved);
    try stack.save(allocator, v);
    try stdout("change {s} approved (risk: {s})\n", .{ id, tier });
```
(Remove `_ = try stack.setPrApproved(allocator, v, id, true);`.)

- [ ] **Step 2: Edit `cmdRework`**

Replace the `setPrApproved` line:

```zig
    if (stack.getChange(v, id) == null) return error.ChangeNotFound;
    const tier = stack.getRisk(v, id) orelse "UNKNOWN";
    _ = try stack.appendApproval(allocator, v, id, "rework", "developer", tier, "reopened for rework");
    _ = try stack.setChangeString(v, id, "status", stack.status_in_progress);
    try stack.save(allocator, v);
    try stdout("change {s} reopened for rework\n", .{id});
```
(Remove `_ = try stack.setPrApproved(allocator, v, id, false);`.)

- [ ] **Step 3: Verify build**

Run: `cd acts-core && zig build && zig build test`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add acts-core/src/main.zig
git commit -m "feat: approve/rework — approvals audit log only (no per-change pr.approved)"
```

---

## Task 11: `cmdStackLand` v3 (whole-branch, all-approved, close PR)

**Files:**
- Modify: `acts-core/src/main.zig:410` (`cmdStackLand`)

- [ ] **Step 1: Rewrite `cmdStackLand`**

Replace the whole function:

```zig
fn cmdStackLand(allocator: std.mem.Allocator) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;
    const root = &v.object;
    const sid = if (root.get("id")) |s| if (s == .string) s.string else "" else "";

    const feat = stack.branchOf(v) orelse return error.ManifestInvalid;
    const integ = stack.integrationBranch(v);
    if (integ.len == 0) return error.ManifestInvalid;

    // Whole-branch landing: every non-merged change must be APPROVED.
    const unappr = try stack.unapprovedChanges(allocator, v);
    if (unappr.len > 0) {
        try stdout("cannot land: {d} change(s) not APPROVED:\n", .{unappr.len});
        for (unappr) |cid| try stdout("  - {s}\n", .{cid});
        return error.NotApproved;
    }

    // Stale-verification guard: if the integration branch moved since a change
    // was verified, require re-verification before landing.
    const cur_integ_sha = try git.refSha(allocator, integ);
    const changes = root.get("changes") orelse return error.ManifestInvalid;
    if (changes == .array) {
        for (changes.array.items) |*c| {
            if (c.* != .object) continue;
            const cid = if (c.object.get("id")) |x| if (x == .string) x.string else "" else "";
            if (cid.len == 0) continue;
            const verified_sha = stack.getVerifyBaseSha(v, cid);
            if (verified_sha != null and cur_integ_sha.len > 0 and !std.mem.eql(u8, verified_sha.?, cur_integ_sha)) {
                try stdout("skip {s}: integration branch moved since verify — run `acts verify {s}` before landing\n", .{ cid, cid });
                return error.StaleVerification;
            }
        }
    }

    // Commit any pending manifest/note changes on the feature branch first, so
    // switching to the integration branch isn't blocked by a dirty tracked `.acts/`.
    const cur = (try git.currentBranch(allocator)) orelse "";
    if (!std.mem.eql(u8, cur, feat)) {
        _ = try git.checkoutBranch(allocator, feat);
    }
    const status_res = try git.run(allocator, &.{ "git", "status", "--porcelain", "--", ".acts" }, 8192);
    if (status_res.exit_code == 0 and std.mem.trim(u8, status_res.stdout, " \n\r").len > 0) {
        _ = try git.run(allocator, &.{ "git", "add", ".acts" }, 8192);
        _ = try git.gitCommit(allocator, try std.fmt.allocPrint(allocator, "chore(acts): record {s} state", .{sid}));
    }

    // Merge the whole feature branch into the integration branch.
    const co = try git.checkoutBranch(allocator, integ);
    if (co.exit_code != 0) {
        try stderr("checkout {s} failed: {s}\n", .{ integ, std.mem.trim(u8, co.stderr, " \n\r") });
        return error.CheckoutFailed;
    }
    const mr = try git.mergeNoFf(allocator, feat, try std.fmt.allocPrint(allocator, "acts: land {s}", .{sid}));
    if (mr.exit_code != 0) {
        try stderr("merge failed: {s}\n", .{std.mem.trim(u8, mr.stderr, " \n\r")});
        return error.MergeFailed;
    }
    try stdout("landed stack {s} onto {s}\n", .{ sid, integ });

    // Mark all changes MERGED, save the manifest on the integration branch.
    if (changes == .array) {
        for (changes.array.items) |*c| {
            if (c.* != .object) continue;
            const cid = if (c.object.get("id")) |x| if (x == .string) x.string else "" else "";
            if (cid.len == 0) continue;
            if (!std.mem.eql(u8, (if (c.object.get("status")) |s| if (s == .string) s.string else "" else ""), stack.status_merged)) {
                _ = try stack.setChangeString(v, cid, "status", stack.status_merged);
            }
        }
    }
    try stack.save(allocator, v);
    const st2 = try git.run(allocator, &.{ "git", "status", "--porcelain", "--", ".acts" }, 8192);
    if (st2.exit_code == 0 and std.mem.trim(u8, st2.stdout, " \n\r").len > 0) {
        _ = try git.run(allocator, &.{ "git", "add", ".acts" }, 8192);
        _ = try git.gitCommit(allocator, "chore(acts): mark landed changes MERGED");
    }

    // Close the stack PR (one PR per stack).
    if (stack.stackPrUrl(v)) |url| {
        if (git.hasTool(allocator, "gh")) {
            const close = try git.run(allocator, &.{ "gh", "pr", "close", url, "--comment", "Merged into " ++ integ ++ " via acts stack land." }, 8192);
            if (close.exit_code == 0) {
                try stdout("closed PR: {s}\n", .{url});
            } else {
                try stderr("note: gh pr close failed: {s}\n", .{std.mem.trim(u8, close.stderr, " \n\r")});
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `cd acts-core && zig build && zig build test`
Expected: exit 0. If `autoLandLowEnabled` is now unused, remove it (and the `hilt.auto_land_low` doc note stays as a future knob) — check: `grep -n autoLandLowEnabled acts-core/src/main.zig`.

- [ ] **Step 3: Manual smoke (temp repo)**

```bash
T=$(mktemp -d) && cd "$T" && git init -q && git commit -q --allow-empty -m init
B=/home/tommasop/code/ai/acts-spec/acts-core/zig-out/bin/acts
$B stack create auth -t "Add auth" >/dev/null
$B change add c1 -t "JWT" --accept "works" >/dev/null
echo "change" > f.txt && git add f.txt && git commit -q -m "work"
$B verify c1 >/dev/null   # quality gates run (no package.json -> Makefile check; may be empty/skipped)
$B approve c1 >/dev/null
$B stack land
git log --oneline -3
```
Expected: `landed stack auth onto master`; `f.txt` on master; `git branch --show-current` = `master`; `.acts/stack.json` changes all MERGED. Clean up: `rm -rf "$T"`.

- [ ] **Step 4: Commit**

```bash
git add acts-core/src/main.zig
git commit -m "feat: stack land — whole-branch merge, all-approved gate, close PR"
```

---

## Task 12: `cmdScope`, `cmdValidate`, `resolveCurrentChange` v3

**Files:**
- Modify: `acts-core/src/main.zig:1190` (`cmdScope`), `:1215` (`cmdValidate`)

- [ ] **Step 1: Rewrite `cmdScope` (range-based, no checkout)**

Replace the body:

```zig
fn cmdScope(allocator: std.mem.Allocator, id: []const u8, file: []const u8) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;

    if (stack.getChange(v, id) == null) return error.ChangeNotFound;
    const range = stack.changeDiffRange(v, id);
    if (range.from.len == 0) {
        try stdout("{{\n  \"file_path\": \"{s}\",\n  \"action\": \"warn\",\n  \"message\": \"No commit range recorded for change {s} — verify it belongs to this task before editing\"\n}}\n", .{ file, id });
        return;
    }

    const files = try git.changedFilesSince(allocator, range.from);
    for (files) |f| {
        if (std.mem.eql(u8, f, file)) {
            try stdout("{{\n  \"file_path\": \"{s}\",\n  \"action\": \"ok\",\n  \"message\": \"File is part of change {s}'s range\"\n}}\n", .{ file, id });
            return;
        }
    }
    try stdout("{{\n  \"file_path\": \"{s}\",\n  \"action\": \"warn\",\n  \"message\": \"File not in change {s}'s range — verify it belongs to this task before editing\"\n}}\n", .{ file, id });
}
```

- [ ] **Step 2: Rewrite `cmdValidate` (v3 branch/PR/range consistency)**

Replace the branch-consistency block (after the `manifest problems` print):

```zig
    // Branch consistency
    const root = &v.object;
    const feat = stack.branchOf(v) orelse "";
    if (feat.len > 0 and !git.branchExists(allocator, feat)) {
        try stdout("warn: feature branch {s} does not exist\n", .{feat});
    }
    if (root.get("changes")) |changes| {
        if (changes == .array) {
            for (changes.array.items) |*c| {
                if (c.* != .object) continue;
                const m = &c.*.object;
                const cid = if (m.get("id")) |x| if (x == .string) x.string else "" else "";
                if (stack.changeStartSha(v, cid)) |sha| {
                    const rs = git.refSha(allocator, sha) catch "";
                    if (rs.len == 0) {
                        try stdout("warn: change {s} start_sha {s} is not a valid git ref\n", .{ cid, sha });
                    }
                }
                if (stack.legacyChangeBranch(v, cid)) |cb| {
                    if (!git.branchExists(allocator, cb)) {
                        try stdout("warn: change {s} branch {s} does not exist\n", .{ cid, cb });
                    }
                }
            }
        }
    }
```

- [ ] **Step 3: Verify build**

Run: `cd acts-core && zig build && zig build test`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add acts-core/src/main.zig
git commit -m "feat: scope + validate — checkpoint ranges and v3 consistency"
```

---

## Task 13: `cmdMigrate` → v3 output

**Files:**
- Modify: `acts-core/src/main.zig:1284` (`cmdMigrate`)

- [ ] **Step 1: Change the stack branch + manifest to v3**

In `cmdMigrate`, replace:

```zig
    const base_branch = try std.fmt.allocPrint(allocator, "acts/{s}/base", .{sid});
    const res = try git.createBranch(allocator, base_branch, "");
```
with:
```zig
    const feat = try std.fmt.allocPrint(allocator, "acts/{s}/feature", .{sid});
    const integ = (try git.currentBranch(allocator)) orelse "master";
    const res = try git.createBranch(allocator, feat, "");
```
and replace:
```zig
    try root_map.put("version", .{ .integer = 2 });
    try root_map.put("id", .{ .string = sid });
    try root_map.put("title", .{ .string = stitle });
    try root_map.put("base_branch", .{ .string = base_branch });
```
with:
```zig
    try root_map.put("version", .{ .integer = 3 });
    try root_map.put("id", .{ .string = sid });
    try root_map.put("title", .{ .string = stitle });
    try root_map.put("branch", .{ .string = feat });
    try root_map.put("base_branch", .{ .string = integ });
    var pr0 = std.json.ObjectMap.init(allocator);
    try pr0.put("url", .null);
    try root_map.put("pr", .{ .object = pr0 });
```

- [ ] **Step 2: Emit changes as checkpoints (no per-change branch/pr)**

In the task loop, replace:
```zig
        const branch = try std.fmt.allocPrint(allocator, "acts/{s}/c{d}-{s}", .{ sid, idx, slug });
```
with:
```zig
        _ = slug;
```
and replace the entry building (drop `branch`, `parent`, `pr`; add `start_sha`/`end_sha` null):
```zig
        var entry = std.json.ObjectMap.init(allocator);
        try entry.put("id", .{ .string = tid });
        try entry.put("title", .{ .string = ttitle });
        try entry.put("status", .{ .string = statusFromV1(tstatus, treview) });
        try entry.put("start_sha", .null);
        try entry.put("end_sha", .null);
        try entry.put("acceptance", .{ .array = std.json.Array.init(allocator) });
        try entry.put("verify", .{ .object = std.json.ObjectMap.init(allocator) });
        try entry.put("notes", .{ .array = std.json.Array.init(allocator) });
        try entry.put("checkpoint", .null);
```
(Remove the `prev_tid`/`parent` and the per-change `pr` block.)

- [ ] **Step 3: Update the final print**

Replace the final `stdout` line:
```zig
    try stdout("migrated v1 story {s} → v3 stack (feature branch {s}, {d} changes)\n", .{ sid, feat, idx });
```

- [ ] **Step 4: Verify build**

Run: `cd acts-core && zig build && zig build test`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add acts-core/src/main.zig
git commit -m "feat: migrate — v3 checkpoint output"
```

---

## Task 14: `context.zig` v3 context pack

**Files:**
- Modify: `acts-core/src/context.zig`

- [ ] **Step 1: Rewrite the header + parent chain + changed-files sections**

Replace the header print (lines 16–38) with:

```zig
    const root = &v.object;
    const stack_id = if (root.get("id")) |s| if (s == .string) s.string else "" else "";
    const title = if (root.get("title")) |s| if (s == .string) s.string else "" else "";
    const feat = stack.branchOf(v) orelse "";
    const integ = stack.integrationBranch(v);

    const m = stack.getChange(v, change_id) orelse return error.ChangeNotFound;
    const change_title = if (m.get("title")) |s| if (s == .string) s.string else "" else "";
    const status = if (m.get("status")) |s| if (s == .string) s.string else "" else "";
    const range = stack.changeDiffRange(v, change_id);

    try out.writer().print(
        \\# ACTS Context Pack
        \\
        \\## Stack
        \\- id: {s}
        \\- title: {s}
        \\- feature branch: {s} (off {s})
        \\
        \\## Change: {s}
        \\- title: {s}
        \\- status: {s}
        \\- range: {s}..{s}
        \\
    , .{ stack_id, title, feat, integ, change_id, change_title, status, range.from, range.to });
```

- [ ] **Step 2: Replace the Parent Chain section with preceding changes**

Replace the parent-chain block (lines 59–72) with:

```zig
    // Preceding changes (context continuity: what came before this checkpoint)
    try out.appendSlice("\n## Preceding Changes\n");
    var prev_found = false;
    if (root.get("changes")) |changes| {
        if (changes == .array) {
            for (changes.array.items) |*c| {
                if (c.* != .object) continue;
                const pm = &c.*.object;
                const pcid = if (pm.get("id")) |x| if (x == .string) x.string else "" else "";
                if (std.mem.eql(u8, pcid, change_id)) break;
                const pt = if (pm.get("title")) |x| if (x == .string) x.string else "" else "";
                const ps = if (pm.get("status")) |x| if (x == .string) x.string else "" else "";
                try out.writer().print("- {s}: {s} ({s})\n", .{ pcid, pt, ps });
                prev_found = true;
            }
        }
    }
    if (!prev_found) try out.appendSlice("- (first change in stack)\n");
```

- [ ] **Step 3: Replace changed-files + commit-history sections to use the range**

Replace the two `if (branch.len > 0) { ... }` blocks (lines 120–139) with:

```zig
    // Changed files (blast radius from the checkpoint range)
    if (range.from.len > 0) {
        const files = git.changedFilesSince(allocator, range.from) catch &[_][]const u8{};
        try out.appendSlice("\n## Changed Files\n");
        if (files.len == 0) {
            try out.appendSlice("- (no changes yet)\n");
        } else {
            for (files) |f| {
                try out.writer().print("- {s}\n", .{f});
            }
        }
    }

    // Commit history since the checkpoint start
    if (range.from.len > 0) {
        const log = git.gitLogOneline(allocator, range.from, 10) catch "";
        if (log.len > 0) {
            try out.writer().print("\n## Commits (since {s})\n{s}\n", .{ range.from, log });
        }
    }
```

- [ ] **Step 4: Remove the now-unused `branch`/`base_branch` locals**

Delete the lines:
```zig
    const branch = if (m.get("branch")) |s| if (s == .string) s.string else "" else "";
    const base_branch = if (root.get("base_branch")) |s| if (s == .string) s.string else "" else "";
```

- [ ] **Step 5: Verify build**

Run: `cd acts-core && zig build && zig build test`
Expected: exit 0.

- [ ] **Step 6: Commit**

```bash
git add acts-core/src/context.zig
git commit -m "feat: context pack — feature branch + checkpoint range + preceding changes"
```

---

## Task 15: `diagram.zig` v3 (per-change ranges + whole-stack)

**Files:**
- Modify: `acts-core/src/diagram.zig`

- [ ] **Step 1: Replace `loadChange` to return the checkpoint range**

Replace `loadChange`:

```zig
fn loadChange(allocator: std.mem.Allocator, id: []const u8) !struct { parsed: std.json.Parsed(std.json.Value), range: stack.DiffRange, ctitle: []const u8 } {
    var parsed = try stack.load(allocator);
    errdefer parsed.deinit();
    const v = parsed.value;
    const change = stack.getChange(v, id) orelse return error.ChangeNotFound;
    const ctitle = if (change.get("title")) |s| if (s == .string) s.string else "" else "";
    const range = stack.changeDiffRange(v, id);
    return .{ .parsed = parsed, .range = range, .ctitle = ctitle };
}
```

- [ ] **Step 2: Update `cmdDiagram` to use the range**

Replace the start of `cmdDiagram` (the `branch`/`base` resolution + diff):

```zig
pub fn cmdDiagram(allocator: std.mem.Allocator, cwd: []const u8, id: []const u8, delta: bool) !?[]const u8 {
    const loaded = try loadChange(allocator, id);
    defer loaded.parsed.deinit();
    const range = loaded.range;
    const ctitle = loaded.ctitle;
    if (range.from.len == 0) {
        print("change {s}: no commit range recorded — nothing to diagram.\n", .{id});
        return null;
    }
    return renderRange(allocator, cwd, id, ctitle, range.from, range.to, delta);
}
```

- [ ] **Step 3: Extract `renderRange` from the old `cmdDiagram` body**

Add `renderRange` (move the component/partition/render logic; `out_dir` becomes `<out_root>/<id>/archify`):

```zig
fn renderRange(
    allocator: std.mem.Allocator,
    cwd: []const u8,
    id: []const u8,
    ctitle: []const u8,
    from: []const u8,
    to: []const u8,
    delta: bool,
) !?[]const u8 {
    const entries = try git.diffNameStatus(allocator, from, to);
    if (entries.len == 0) {
        print("change {s}: no committed diff in range {s}..{s} — nothing to diagram.\n", .{ id, from, to });
        return null;
    }

    const aliases = graph.referenceAliases(allocator, cwd);
    const components = try buildComponents(allocator, entries, aliases);
    const sides = try partitionComponents(allocator, aliases, entries);

    const renderer = archify.findRenderer(allocator, cwd);
    if (renderer == null) {
        const summary = try buildDeltaSummary(allocator, id, components, sides.before, sides.after);
        print("archify renderer not installed — degraded to a textual delta.\n", .{});
        print("{s}\n", .{summary});
        print("hint: run `acts archify install` (or `acts setup --with-archify`) to render HTML diagrams.\n", .{});
        return null;
    }

    const out_dir = try std.fs.path.join(allocator, &.{ out_root, id, "archify" });
    std.fs.cwd().makePath(out_dir) catch {};

    if (delta) {
        const before_comps = try filterComponents(allocator, components, sides.before);
        const after_comps = try filterComponents(allocator, components, sides.after);
        const base_title = try std.fmt.allocPrint(allocator, "{s} (before)", .{ctitle});
        const head_title = try std.fmt.allocPrint(allocator, "{s} (after)", .{ctitle});
        const base_ir = try archify.buildArchitectureIR(allocator, base_title, "base.html", before_comps, &.{});
        const head_ir = try archify.buildArchitectureIR(allocator, head_title, "head.html", after_comps, &.{});
        const base_path = try std.fs.path.join(allocator, &.{ out_dir, "base.json" });
        const head_path = try std.fs.path.join(allocator, &.{ out_dir, "head.json" });
        try writeFile(base_path, base_ir);
        try writeFile(head_path, head_ir);
        const html_path = try std.fmt.allocPrint(allocator, "{s}/delta-{s}.html", .{ out_dir, id });
        if (!try renderCompare(allocator, renderer.?, base_path, head_path, html_path)) return null;
        print("delta HTML: {s}\n", .{html_path});
        return html_path;
    }

    const after_comps = try filterComponents(allocator, components, sides.after);
    const comps = if (after_comps.len > 0) after_comps else components;
    const ir = try archify.buildArchitectureIR(allocator, ctitle, "architecture.html", comps, &.{});
    const ir_path = try std.fs.path.join(allocator, &.{ out_dir, "architecture.json" });
    try writeFile(ir_path, ir);
    const html_path = try std.fmt.allocPrint(allocator, "{s}/architecture-{s}.html", .{ out_dir, id });
    if (!try renderDeliver(allocator, renderer.?, ir_path, html_path)) return null;
    print("architecture HTML: {s}\n", .{html_path});
    return html_path;
}
```

- [ ] **Step 4: Add `cmdStackDiagram` (whole-stack delta)**

Add after `cmdDiagram`:

```zig
/// Whole-stack diagram: integration branch (before) vs feature branch (after).
/// Used by `acts review` to attach a single architecture delta to the one PR.
pub fn cmdStackDiagram(allocator: std.mem.Allocator, cwd: []const u8, delta: bool, attach: bool) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;
    const sid = if (v.object.get("id")) |s| if (s == .string) s.string else "" else "";
    const stitle = if (v.object.get("title")) |s| if (s == .string) s.string else "" else "";
    const integ = stack.integrationBranch(v);
    const feat = stack.branchOf(v) orelse return error.ManifestInvalid;
    if (integ.len == 0) return;

    const id = try std.fmt.allocPrint(allocator, "stack-{s}", .{sid});
    _ = try renderRange(allocator, cwd, id, stitle, integ, feat, delta);
    if (attach) {
        try attachToPrRange(allocator, cwd, id, integ, feat);
    }
}
```

- [ ] **Step 5: Refactor `attachToPr` → `attachToPrRange`**

Replace `attachToPr` with a range-based version:

```zig
/// Post the architecture-delta comment to the change's (or stack's) PR.
pub fn attachToPr(allocator: std.mem.Allocator, cwd: []const u8, id: []const u8, delta: bool) !void {
    var parsed = try stack.load(allocator);
    defer parsed.deinit();
    const v = parsed.value;
    const range = stack.changeDiffRange(v, id);
    if (range.from.len == 0) return;
    try attachToPrRange(allocator, cwd, id, range.from, range.to);
}

fn attachToPrRange(allocator: std.mem.Allocator, cwd: []const u8, id: []const u8, from: []const u8, to: []const u8) !void {
    const pr_url = stackPrUrl(allocator) orelse {
        print("attach: no stack PR recorded — run `acts review` first.\n", .{});
        return;
    };
    const tools = git.detectTools(allocator);
    if (!tools.gh) {
        print("attach: `gh` not available — cannot comment on the PR.\n", .{});
        return;
    }

    const html_path = try renderRange(allocator, cwd, id, "", from, to, true);
    if (html_path == null) return;

    var body = std.ArrayList(u8).init(allocator);
    const w = body.writer();

    if (archify.findRenderer(allocator, cwd)) |renderer| {
        const vc = try runNode(allocator, renderer, &.{ "visual-check", html_path.?, "--json" });
        if (vc.exit_code == 0) {
            if (extractPngPath(vc.stdout)) |png| {
                const gist = try git.run(allocator, &.{ "gh", "gist", "create", png, "--public" }, 65536);
                if (gist.exit_code == 0) {
                    const gist_url = std.mem.trim(u8, gist.stdout, " \n\r");
                    if (rawUrlFromGist(allocator, gist_url, png)) |raw| {
                        try w.print("![architecture delta]({s})\n\n", .{raw});
                    }
                }
            }
        }
    }

    const entries = try git.diffNameStatus(allocator, from, to);
    const aliases = graph.referenceAliases(allocator, cwd);
    const components = try buildComponents(allocator, entries, aliases);
    const sides = try partitionComponents(allocator, aliases, entries);
    const summary = try buildDeltaSummary(allocator, id, components, sides.before, sides.after);
    try w.writeAll(summary);
    try w.print("\n\nSelf-contained HTML: `{s}`\n", .{html_path.?});

    const comment_path = try std.fs.path.join(allocator, &.{ out_root, id, "archify", "pr-comment.md" });
    try writeFile(comment_path, body.items);
    const res = try git.run(allocator, &.{ "gh", "pr", "comment", pr_url, "--body-file", comment_path }, 65536);
    if (res.exit_code == 0) {
        print("attached architecture delta to {s}\n", .{pr_url});
    } else {
        print("attach: gh pr comment failed: {s}\n", .{std.mem.trim(u8, res.stderr, " \n\r")});
    }
}

/// Stack-level PR URL from the manifest (one PR per stack).
fn stackPrUrl(allocator: std.mem.Allocator) ?[]const u8 {
    var parsed = stack.load(allocator) catch return null;
    defer parsed.deinit();
    return stack.stackPrUrl(parsed.value);
}
```

- [ ] **Step 6: Verify build**

Run: `cd acts-core && zig build && zig build test`
Expected: exit 0.

- [ ] **Step 7: Commit**

```bash
git add acts-core/src/diagram.zig
git commit -m "feat: diagram — checkpoint ranges + whole-stack delta for the one PR"
```

---

## Task 16: Plugin `acts.js` v3

**Files:**
- Modify: `.opencode/plugins/acts.js`

- [ ] **Step 1: Update `resolveActiveChange` (feature-branch + top change)**

Replace the function body:

```js
  const resolveActiveChange = () => {
    const status = refreshStackStatus();
    if (!status || !Array.isArray(status.changes)) return null;
    let branch = null;
    try {
      branch = execSync('git rev-parse --abbrev-ref HEAD', { encoding: 'utf8', cwd: directory, stdio: ['pipe', 'pipe', 'ignore'] }).trim();
    } catch { /* not a git repo or no HEAD */ }
    if (!branch) {
      // Fall back to the last non-terminal change.
      return [...status.changes].reverse().find(c => !['MERGED', 'APPROVED'].includes(c.status || ''))?.id || null;
    }
    if (branch === status.branch) {
      // On the feature branch → top (last) non-merged change.
      const open = status.changes.filter(c => (c.status || '') !== 'MERGED');
      return open.length ? open[open.length - 1].id : null;
    }
    const match = status.changes.find(c => c.branch === branch);
    return match ? match.id : null;
  };
```

- [ ] **Step 2: Update `computeBlastRadius` (checkpoint range)**

Replace lines 192–203:

```js
  const computeBlastRadius = async (changeId) => {
    const manifest = readStackManifest();
    if (!manifest) return null;
    const change = (manifest.changes || []).find(c => c.id === changeId);
    if (!change) return null;
    let files = [];
    try {
      const from = change.start_sha || manifest.base_branch || '';
      const to = change.end_sha || 'HEAD';
      files = execFileSync('git', ['diff', '--name-only', from, to], {
        encoding: 'utf8', cwd: directory, stdio: ['pipe', 'pipe', 'pipe']
      }).split('\n').map(s => s.trim()).filter(Boolean);
    } catch { /* fall through */ }
    if (files.length === 0) return null;
```

- [ ] **Step 3: Update the system-context stack block (lines ~317–324)**

Replace:
```js
    lines.push(`- Base branch: ${status.base_branch}`);
```
with:
```js
    lines.push(`- Feature branch: ${status.branch} (off ${status.base_branch})`);
```
and replace:
```js
        lines.push(`- ${c.id}: ${c.title} [${st}] branch=${c.branch}`);
```
with:
```js
        const range = c.start_sha ? `${(c.start_sha || '').slice(0, 7)}..${(c.end_sha || '…').slice(0, 7)}` : '';
        lines.push(`- ${c.id}: ${c.title} [${st}] ${range}`);
```

- [ ] **Step 4: Verify plugin syntax**

Run: `node --check .opencode/plugins/acts.js`
Expected: exit 0.

- [ ] **Step 5: Commit**

```bash
git add .opencode/plugins/acts.js
git commit -m "feat: plugin — v3 active change resolution + feature-branch context"
```

---

## Task 17: Plugin tests → v3 fixture

**Files:**
- Modify: `tests/acts-plugin.test.mjs`

- [ ] **Step 1: Update the manifest fixture to v3**

Replace the `.acts/stack.json` write (lines 24–33):

```js
fs.writeFileSync(path.join(tmp, '.acts', 'stack.json'), JSON.stringify({
  version: 3,
  id: 'auth',
  title: 'User auth',
  branch: 'acts/auth/feature',
  base_branch: 'master',
  pr: { url: null },
  changes: [
    { id: 'c1', title: 'JWT middleware', status: 'IN_PROGRESS', start_sha: 'abc', end_sha: null },
    { id: 'c2', title: 'Login endpoint', status: 'TODO', start_sha: 'def', end_sha: null },
  ],
}, null, 2));
```

- [ ] **Step 2: Update the dummy `acts` binary `stack status --json` output**

Replace the echoed JSON (line 45) with the same v3 object.

- [ ] **Step 3: Update assertions to cover v3 context**

After the existing system-transform assertions (line ~95), add:

```js
  assert.ok(sys.includes('Feature branch'), 'system context shows the feature branch');
  assert.ok(sys.includes('acts/auth/feature'), 'system context names the feature branch');
```

- [ ] **Step 4: Run the plugin tests**

Run: `npm test`
Expected: all checks pass (existing assertions still hold: `auth`, `JWT middleware`, `Active Change`).

- [ ] **Step 5: Commit**

```bash
git add tests/acts-plugin.test.mjs
git commit -m "test: plugin tests — v3 manifest fixture"
```

---

## Task 18: Usage text + setup `agents_section`

**Files:**
- Modify: `acts-core/src/main.zig` (usage_text), `acts-core/src/setup.zig` (`agents_section`)

- [ ] **Step 1: Update usage text**

Replace in the usage_text (lines ~29–40):
```zig
    \\  stack create <id> [-t <title>]          Start a new stack (base branch + manifest)
```
with:
```zig
    \\  stack create <id> [-t <title>]          Start a new stack (feature branch + manifest)
```
and replace:
```zig
    \\  change add <id> -t <title> [--accept <criteria>]  Add a change on top of the stack
```
with:
```zig
    \\  change add <id> -t <title> [--accept <criteria>]  Add a change (checkpoint on the feature branch)
```
and replace:
```zig
    \\  stack land                            Merge APPROVED changes bottom-up
```
with:
```zig
    \\  stack land                            Merge the whole feature branch (all changes APPROVED)
```
and replace:
```zig
    \\  review <id>                             Submit stacked PR (requires verify to pass)
```
with:
```zig
    \\  review <id>                             Submit/update the stack's ONE PR (feature vs base)
```

- [ ] **Step 2: Update `setup.zig` `agents_section`**

Replace these two lines in `agents_section`:
```zig
    \\- `acts stack create <id> [-t <title>]` — Start a new stack (base branch + manifest)
    \\- `acts stack land` — Merge APPROVED changes bottom-up
    \\- `acts change add <id> -t <title> [--accept <criteria>]` — Add a change on top of the stack
    \\- `acts review <id>` — Submit stacked PR (requires verify to pass)
```
with:
```zig
    \\- `acts stack create <id> [-t <title>]` — Start a new stack (feature branch + manifest)
    \\- `acts stack land` — Merge the whole feature branch once all changes are APPROVED
    \\- `acts change add <id> -t <title> [--accept <criteria>]` — Add a change (checkpoint on the feature branch)
    \\- `acts review <id>` — Submit/update the stack's ONE PR (feature vs base; requires verify to pass)
```

- [ ] **Step 3: Verify build + the `agents_section` test**

Run: `cd acts-core && zig build test && zig build`
Expected: PASS (the existing `agents_section` test checks `acts verify`/`acts context`/`acts risk`, still present).

- [ ] **Step 4: Commit**

```bash
git add acts-core/src/main.zig acts-core/src/setup.zig
git commit -m "docs: usage + agents section — single-branch wording"
```

---

## Task 19: Docs

**Files:**
- Modify: `README.md`, `docs/INTEGRATION.md`, `docs/faq.md`, `docs/MIGRATION.md`, `docs/minimal-viable-acts.md`, `docs/example-new-project.md`, `docs/example-existing-project.md`, `AGENTS.md`, `.opencode/skills/acts/SKILL.md`

- [ ] **Step 1: Rewrite the core model sections in `README.md`**

- Replace "What is ACTS?" bullet list items about stacks/branches: "a *stack* is a feature (a **feature branch** off `master`); a *change* is one unit of agent work (**a checkpoint on that branch**)".
- In "Data Model": show the v3 manifest (`branch`, `base_branch`, stack-level `pr`, changes with `start_sha`/`end_sha`).
- In "Start a Stack": `acts stack create auth` → "stack auth created on feature branch acts/auth/feature".
- In "Review (stacked PR)": `acts review c1` → "one PR for the whole stack (feature → master)"; `acts stack land` → "merges the whole branch once all changes approved, closes the PR".
- In "Status Values": unchanged.
- Version History: add `2.3.0 | 2026-08 | Single-branch stacks: ...`.

- [ ] **Step 2: Update `docs/INTEGRATION.md`, `docs/faq.md`, `docs/MIGRATION.md`**

- INTEGRATION: workflow examples change "start a stack → base branch" wording; `acts review` submits the ONE PR; `acts stack land` whole-branch.
- faq: the "minimum to try ACTS" commands stay the same; add a Q explaining the single-branch model ("one feature = one branch = one PR").
- MIGRATION: v1 → v3 (feature branch + checkpoint changes); note legacy v2 manifests still validate.

- [ ] **Step 3: Update `docs/minimal-viable-acts.md` and `docs/example-*.md`**

Replace any "base branch" / "stacked branch" / "parent" language with the feature-branch + checkpoint model and the linear status output.

- [ ] **Step 4: Update `AGENTS.md` and `.opencode/skills/acts/SKILL.md`**

- AGENTS.md "Data Storage": `.acts/stack.json` line stays; add "a change = a checkpoint (commit range) on the stack's feature branch".
- SKILL.md Commands table + Workflow: `change add` = checkpoint (no branch switch); `review` = one PR; `land` = whole-branch once all approved.

- [ ] **Step 5: Verify nothing references removed terms**

Run: `cd /home/tommasop/code/ai/acts-spec && rg -n "stacked branch|bottom-up|base branch|acts/<id>/base|/base\b" README.md docs .opencode AGENTS.md | head -40`
Review each hit and fix wording where it describes the OLD model.

- [ ] **Step 6: Commit**

```bash
git add README.md docs AGENTS.md .opencode/skills/acts/SKILL.md
git commit -m "docs: single-branch stack model throughout"
```

---

## Task 20: End-to-end verification

**Files:**
- No source changes; manual verification in a throwaway repo + this repo's gate.

- [ ] **Step 1: Full lifecycle in a throwaway repo**

```bash
cd /home/tommasop/code/ai/acts-spec/acts-core && zig build && B=$PWD/zig-out/bin/acts
T=$(mktemp -d) && cd "$T"
git init -q && git commit -q --allow-empty -m init
$B stack create auth -t "Add auth"
$B change add c1 -t "JWT" --accept "token validated" 
echo x > a.ts && git add a.ts && git commit -q -m "c1 work"
$B verify c1
$B change add c2 -t "Sessions" --accept "sessions work"
echo y > b.ts && git add b.ts && git commit -q -m "c2 work"
$B verify c2
$B stack status          # linear, SHAs, no PR
$B approve c1 && $B approve c2
$B stack land            # refuses unless all approved? (they are) → merges
git branch --show-current   # master
$B stack status          # all MERGED
rm -rf "$T"
```
Expected: `stack land` merges feature → master once; status linear; all changes MERGED.

- [ ] **Step 2: Verify land refuses when not all approved**

```bash
T=$(mktemp -d) && cd "$T" && git init -q && git commit -q --allow-empty -m init
B=/home/tommasop/code/ai/acts-spec/acts-core/zig-out/bin/acts
$B stack create s2 -t "S2" >/dev/null
$B change add c1 -t "one" >/dev/null
echo a > a.ts && git add a.ts && git commit -q -m a
$B verify c1 >/dev/null
$B change add c2 -t "two" >/dev/null
echo b > b.ts && git add b.ts && git commit -q -m b
$B verify c2 >/dev/null
$B approve c1 >/dev/null   # c2 unapproved
$B stack land
```
Expected: exit nonzero, message `cannot land: 1 change(s) not APPROVED:` listing c2. Clean up.

- [ ] **Step 3: Legacy v2 manifest still validates**

```bash
cd /home/tommasop/code/ai/acts-spec
git stash list >/dev/null 2>&1
# Build a legacy v2 manifest in a temp dir
T=$(mktemp -d) && cd "$T" && git init -q && git commit -q --allow-empty -m init
mkdir -p .acts
cat > .acts/stack.json <<'EOF'
{"version":2,"id":"legacy","title":"Legacy","base_branch":"acts/legacy/base","changes":[{"id":"c1","title":"JWT","status":"MERGED","branch":"acts/legacy/c1-jwt"}]}
EOF
B=/home/tommasop/code/ai/acts-spec/acts-core/zig-out/bin/acts
$B validate
rm -rf "$T"
```
Expected: `manifest OK` (legacy v2 tolerated).

- [ ] **Step 4: Full gate on acts-spec**

Run from `/home/tommasop/code/ai/acts-spec`:
```bash
cd acts-core && zig build test && zig build
cd .. && npm test
node --check .opencode/plugins/acts.js
```
Expected: all pass.

- [ ] **Step 5: Run `acts verify <id>` for this plan's change (in acts-spec)**

```bash
cd /home/tommasop/code/ai/acts-spec && ./acts-core/zig-out/bin/acts verify <this-change-id>
```
Expected: gates PASS.

- [ ] **Step 6: Commit any final tweaks**

```bash
git add -A && git commit -m "chore: single-branch stacks — verified end-to-end"
```

---

## Self-review notes

- **Spec coverage:** checkpoints (Tasks 2,5,7), one PR (Tasks 9,16,17), whole-branch landing (Task 11), legacy validation (Task 2), tests (Tasks 2,3,17,20), docs (Tasks 18,19). All spec sections map to tasks.
- **Type consistency:** `stack.DiffRange` is defined once (Task 2) and used by `context.zig` (14), `diagram.zig` (15), `main.zig` (3,7,8,12). `buildReviewBody(allocator, v)` (Task 3) matches `cmdReview` (Task 9). `stackPrUrl`/`setStackPrUrl` names consistent across Tasks 2, 9, 15.
- **Known simplification:** `verify --all` iterates changes and freezes `end_sha = HEAD` per change — with one shared branch, later changes' verifies naturally capture later HEADs; acceptable and documented in the spec's edge cases.