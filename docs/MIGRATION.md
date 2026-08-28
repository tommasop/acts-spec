# Migration Guide

## Upgrading from v1.x to v3.0

ACTS v3 replaced the SQLite-backed coordination model (stories, tasks, gates) with a **git-native** model (stacks, changes). This guide covers migrating an existing v1 project.

### What Changed

| v1.x | v3 |
|------|------|
| `.acts/acts.db` (SQLite) — stories, tasks, gates | `.acts/stack.json` (manifest) — stacks, changes |
| `acts init <story>` — create story | `acts stack create <id>` — create stack (feature branch) |
| `acts state read` / `acts state write` | `acts stack status` / `acts change status` |
| `acts task create/update` | `acts change add/status` (a change = a checkpoint, `start_sha`/`end_sha`) |
| `acts gate add` (preflight, task-review) | `acts verify` (quality gates; evidence is the gate) |
| `acts review` (terminal HRE) | `acts review` (the stack's ONE PR via `gh`) |
| `acts scope check --task T1 --file X` | `acts scope c1 src/x.ts` |
| `acts override request/approve` | Removed — ownership derived from git diffs |
| Story worktrees | One feature branch (changes = checkpoints on it) |
| `acts story merge --into master` | `acts stack land` (merges the whole feature branch) |

### Migration Steps

#### 1. Backup

```bash
cp -r .acts/ .acts.backup/
```

#### 2. Install the v3 Binary

```bash
cd acts-core
zig build release -Dversion=3.0.0
sudo cp zig-out/bin/acts /usr/local/bin/
```

#### 3. Import a v1 Story

Requires the `sqlite3` CLI:

```bash
# Import the first migratable story
acts migrate

# Or import a specific story
acts migrate LEGACY-42
```

`acts migrate` reads `.acts/acts.db` and:

- Creates a v3 stack whose feature branch is `acts/<story-id>/feature` (off `master`)
- Maps each v1 task → a change: a checkpoint (`start_sha`/`end_sha`) on the feature branch, preserving ordering
- Maps statuses:
  - v1 `DONE` + `approved` review → `APPROVED`
  - v1 `DONE` + no approval → `VERIFIED`
  - v1 `IN_PROGRESS` / `BLOCKED` → `IN_PROGRESS`
  - v1 `TODO` → `TODO`
- Preserves v1 file ownership as a session note (`.acts/changes/<id>/notes/v1-files.md`)

Verify:

```bash
acts stack status
acts validate
```

> Only one v1 story is imported per invocation (the `__maintenance__` story is skipped). Run `acts migrate <story-id>` for each story you want to move.

#### 4. Remove v1 State (optional)

After confirming the migration, you can delete the v1 database:

```bash
rm .acts/acts.db
```

#### 5. Update AGENTS.md

Replace the v1 ACTS section with the v3 rules + commands (see [docs/templates/agents-minimal.md](templates/agents-minimal.md)).

---

## Upgrading Between v2.x Versions

Minor version upgrades within v2.x only require replacing the binary:

```bash
# Replace binary
cp acts-core/zig-out/bin/acts /usr/local/bin/acts

# Verify
acts validate
```

### Legacy v2 manifests still work

Manifests written by v2 (a stack whose `base_branch` is the stack's own branch, each change living on its own `branch`) still parse and validate — `acts validate` accepts both v2 and v3 shapes. You can keep working with a v2 manifest, or migrate it to the single-branch v3 shape (`branch` = the feature branch, `base_branch` = the integration target such as `master`, per-change `start_sha`/`end_sha` checkpoints).

---

## FAQ on Migration

### Do I have to migrate?

No. You can start fresh with `acts stack create`. Migration is only needed if you want to preserve v1 story/task history.

### What happens to my v1 decisions and rejected approaches?

They are not imported. The git-native model keeps coordination state minimal (in `.acts/stack.json`) and durable narrative in session notes. If you need the history, keep the `.acts.backup/` copy.

### Why was SQLite removed?

The v1 sidecar database could drift from the repo and be bypassed. In v3, git branches/PRs are the system of record — a stack is one feature branch, and the manifest is a diffable file committed to it.
