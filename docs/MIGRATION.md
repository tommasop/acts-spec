# Migration Guide

## Upgrading from v1.x to v2.0

ACTS v2.0.0 replaced the SQLite-backed coordination model (stories, tasks, gates) with a **git-native** model (stacks, changes). This guide covers migrating an existing v1 project.

### What Changed

| v1.x | v2.0 |
|------|------|
| `.acts/acts.db` (SQLite) — stories, tasks, gates | `.acts/stack.json` (manifest) — stacks, changes |
| `acts init <story>` — create story | `acts stack create <id>` — create stack (base branch) |
| `acts state read` / `acts state write` | `acts stack status` / `acts change status` |
| `acts task create/update` | `acts change add/status` |
| `acts gate add` (preflight, task-review) | `acts verify` (quality gates; evidence is the gate) |
| `acts review` (terminal HRE) | `acts review` (stacked PR via `gh`/git-spice) |
| `acts scope check --task T1 --file X` | `acts scope c1 src/x.ts` |
| `acts override request/approve` | Removed — ownership derived from git diffs |
| Story worktrees | Stacked branches |
| `acts story merge --into master` | `acts stack land` |

### Migration Steps

#### 1. Backup

```bash
cp -r .acts/ .acts.backup/
```

#### 2. Install the v2 Binary

```bash
cd acts-core
zig build release -Dversion=2.0.0
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

- Creates a v2 stack whose base branch is `acts/<story-id>/base`
- Maps each v1 task → a v2 change (preserving parent chains and ordering)
- Maps statuses:
  - v1 `DONE` + `approved` review → v2 `APPROVED`
  - v1 `DONE` + no approval → v2 `VERIFIED`
  - v1 `IN_PROGRESS` / `BLOCKED` → v2 `IN_PROGRESS`
  - v1 `TODO` → v2 `TODO`
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

Replace the v1 ACTS section with the v2 rules + commands (see [docs/templates/agents-minimal.md](templates/agents-minimal.md)).

---

## Upgrading Between v2.x Versions

Minor version upgrades within v2.x only require replacing the binary:

```bash
# Replace binary
cp acts-core/zig-out/bin/acts /usr/local/bin/acts

# Verify
acts validate
```

---

## FAQ on Migration

### Do I have to migrate?

No. You can start fresh with `acts stack create`. Migration is only needed if you want to preserve v1 story/task history.

### What happens to my v1 decisions and rejected approaches?

They are not imported into v2. The v2 model keeps coordination state minimal (in `.acts/stack.json`) and durable narrative in session notes. If you need the history, keep the `.acts.backup/` copy.

### Why was SQLite removed?

The v1 sidecar database could drift from the repo and be bypassed. In v2, git branches/PRs are the system of record — a stack is just branches, and the manifest is a diffable file committed to the base branch.
