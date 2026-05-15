# ACTS Specification v1.1.0

**Agent Collaborative Tracking Standard**

A protocol for coordinating AI-assisted software development through SQLite-backed state, gate enforcement, multi-story development, and proactive coordination signals.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Data Model](#data-model)
4. [Commands](#commands)
5. [Gate Enforcement](#gate-enforcement)
6. [Proactive Triggers](#proactive-triggers)
7. [Workflows](#workflows)
8. [Integration](#integration)
9. [Migration](#migration)

---

## Overview

ACTS v1.1.0 builds on v1.0.0 with multi-story development, WAL mode for concurrent access, maintenance tasks for quick bug fixes, proactive coordination triggers, and a simplified git-based review flow.

Key additions:
- **Multi-story development** — Git worktrees with cross-story ownership enforcement
- **WAL mode** — Concurrent readers with queued writes (`BEGIN IMMEDIATE`)
- **Maintenance story** — `__maintenance__` auto-created for bug fixes without ceremony
- **Proactive triggers** — Auto-create useful state (unblock events, review queue, agent presence)
- **Git-based review** — `acts review` stages files, shows diff, asks for approval
- **Changelog generation** — Derive changelog from task labels and decisions
- **Story-level gates** — Story merge enforcement with trigger-based validation

---

## Architecture

```
Project Root
├── .acts/
│   ├── acts.db              # SQLite database (WAL mode, multi-story)
│   ├── acts.json            # Configuration manifest
│   ├── bin/
│   │   └── acts             # Zig binary (CLI)
│   └── current -> worktrees/PROJ-42  # Symlink to active story
│   └── worktrees/
│       ├── PROJ-42/         # Git worktree, branch story/PROJ-42
│       │   └── .story/      # plan.md, spec.md, sessions/, tasks/
│       └── PROJ-43/
│           └── .story/
├── .story/                  # Default story (if no worktrees)
│   ├── plan.md
│   ├── spec.md
│   ├── sessions/
│   └── tasks/
└── AGENTS.md                # Project constitution
```

### Source of Truth

| Data | Storage | Access |
|------|---------|--------|
| Stories, tasks, gates | `.acts/acts.db` | `acts` binary |
| Decisions, approaches | `.acts/acts.db` | `acts` binary |
| Plan, spec | `.story/plan.md` (per worktree) | Direct file read |
| Session summaries | `.story/sessions/*.md` | `acts session` commands |
| Task notes | `.story/tasks/<id>/notes.md` | Direct file read |

---

## Data Model

### Core Tables

#### Stories

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Story identifier (e.g., PROJ-42) |
| acts_version | TEXT | ACTS version |
| title | TEXT | Human-readable title |
| status | TEXT | ANALYSIS, APPROVED, IN_PROGRESS, REVIEW, DONE, MERGED, ARCHIVED |
| spec_approved | INTEGER | Boolean |
| type | TEXT | feature, maintenance, epic, spike |
| branch | TEXT | Git branch backing this story |
| worktree_path | TEXT | Path to git worktree |
| parent_story | TEXT FK | Optional parent story |
| semver | TEXT | Story version (e.g., "1.4.0") |
| released_at | INTEGER | Release timestamp |
| archived_at | INTEGER | Archive timestamp |

#### Tasks

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Task identifier (T1, T2, BUG-1, ...) |
| story_id | TEXT FK | Parent story |
| title | TEXT | Task title |
| description | TEXT | Task description |
| status | TEXT | TODO, IN_PROGRESS, BLOCKED, DONE |
| assigned_to | TEXT | Developer name |
| context_priority | INTEGER | 1-5 (1=critical) |
| review_status | TEXT | pending, approved, changes_requested, skipped |
| labels | TEXT | JSON array (e.g., `["bug","fix"]`) |

#### Task Files

| Column | Type | Description |
|--------|------|-------------|
| task_id | TEXT FK | Task |
| file_path | TEXT | File path |

#### Gate Checkpoints

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| task_id | TEXT FK | Associated task |
| gate_type | TEXT | approve, task-review, commit-review, architecture-discuss |
| status | TEXT | pending, approved, changes_requested |
| approved_by | TEXT | Who approved |

#### Story Gates

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| story_id | TEXT FK | Associated story |
| gate_type | TEXT | story-approve, story-merge, architecture-discuss |
| status | TEXT | pending, approved, changes_requested |
| approved_by | TEXT | Who approved |

### Proactive Signal Tables

| Table | Purpose |
|-------|---------|
| `active_story` | Current active story (singleton) |
| `unblock_events` | Dependency completion notifications |
| `review_queue` | Pending review tasks |
| `agent_presence` | Active agent tracking (5-min TTL) |
| `gate_sla` | Review deadline tracking (24h default) |
| `file_conflicts` | Cross-story file conflict detection |

---

## Commands

### Story Management

```bash
acts init <story-id> [--title "..."]
acts story create <id> --title "..." [--from <branch>] [--parent <story-id>]
acts story list [--include-archived] [--include-maintenance]
acts story switch <id>
acts story archive <id>
acts story merge <id> --into <branch> [--semver <version>]
acts story graph [--format json|dot]
```

### Task Management

```bash
acts task create <id> --title "..." [--story <id>] [--labels "a,b"]
acts task get <id>
acts task list [--story <id>] [--maintenance] [--status <status>]
acts task update <id> [--status <status>] [--assigned-to <name>]
acts task move <id> --to <story-id>
```

### Review

```bash
acts review <task-id>     # Stages files, shows diff, asks approve/reject
acts approve <task-id>    # Approve task-review gate
acts reject <task-id>     # Request changes
```

### Gates

```bash
acts gate add --task <id> --type <type> --status <status> [--by <name>]
acts gate list --task <id>
acts gate-sla [--breached]
```

### Proactive Signals

```bash
acts presence set --agent <id> --task <id> --action "..."
acts presence list [--story <id>]
acts unblock list [--acknowledged]
acts unblock ack <id>
acts review-queue [--story <id>]
```

### Changelog

```bash
acts changelog --story <id> [--format md|json]
```

### Database

```bash
acts db checkpoint
acts db status
```

### Validation

```bash
acts validate
acts migrate
acts version
```

---

## Gate Enforcement

### SQLite Triggers

**Preflight Gate** (required before IN_PROGRESS):
```sql
CREATE TRIGGER enforce_preflight_gate
BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'IN_PROGRESS' AND OLD.status = 'TODO'
BEGIN
  SELECT CASE WHEN (
    SELECT COUNT(*) FROM gate_checkpoints
    WHERE task_id = NEW.id AND gate_type = 'approve' AND status = 'approved'
  ) = 0
  THEN RAISE(ABORT, 'Cannot start task: preflight gate not approved')
  END;
END;
```

**Maintenance Auto-Approve** (skips preflight for maintenance tasks):
```sql
CREATE TRIGGER auto_approve_maintenance_preflight
BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'IN_PROGRESS' AND OLD.status = 'TODO'
BEGIN
  INSERT OR IGNORE INTO gate_checkpoints (task_id, gate_type, status, approved_by)
  SELECT NEW.id, 'approve', 'approved', '__system__'
  FROM tasks t WHERE t.id = NEW.id AND t.story_id = '__maintenance__';
END;
```

**Task Review Gate** (required before DONE):
```sql
CREATE TRIGGER enforce_task_review_gate
BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'DONE' AND OLD.status != 'DONE'
BEGIN
  SELECT CASE WHEN (
    SELECT COUNT(*) FROM gate_checkpoints
    WHERE task_id = NEW.id AND gate_type = 'task-review' AND status = 'approved'
  ) = 0
  THEN RAISE(ABORT, 'Cannot mark task DONE: task-review gate not approved')
  END;
END;
```

**Cross-Story Ownership** (prevents file conflicts):
```sql
CREATE TRIGGER enforce_cross_story_ownership
BEFORE INSERT ON task_files
BEGIN
  SELECT CASE WHEN EXISTS(
    SELECT 1 FROM task_files tf JOIN tasks t ON t.id = tf.task_id
    WHERE tf.file_path = NEW.file_path
    AND t.story_id != (SELECT story_id FROM tasks WHERE id = NEW.task_id)
    AND t.status = 'DONE'
  ) THEN RAISE(ABORT, 'File already owned by a DONE task in another story')
  END;
END;
```

**Story Merge** (all tasks DONE + all reviews approved):
```sql
CREATE TRIGGER enforce_story_merge
BEFORE UPDATE OF status ON stories
WHEN NEW.status = 'MERGED' AND OLD.status != 'MERGED'
BEGIN
  SELECT CASE WHEN EXISTS(
    SELECT 1 FROM tasks WHERE story_id = NEW.id AND status != 'DONE'
  ) THEN RAISE(ABORT, 'Cannot merge story: open tasks remain')
  END;
  SELECT CASE WHEN EXISTS(
    SELECT 1 FROM tasks t WHERE t.story_id = NEW.id AND t.status = 'DONE'
    AND NOT EXISTS (
      SELECT 1 FROM gate_checkpoints gc WHERE gc.task_id = t.id
      AND gc.gate_type = 'task-review' AND gc.status = 'approved'
    )
  ) THEN RAISE(ABORT, 'Cannot merge story: tasks without approved review')
  END;
END;
```

---

## Proactive Triggers

These triggers create useful state automatically:

**Dependency Unblock** — Notifies when a dependency completes:
```sql
CREATE TRIGGER notify_dependency_unblock
AFTER UPDATE OF status ON tasks
WHEN NEW.status = 'DONE' AND OLD.status != 'DONE'
BEGIN
  INSERT INTO unblock_events (unblocked_task_id, unblocked_by)
  SELECT td.task_id, NEW.id FROM task_dependencies td WHERE td.depends_on = NEW.id;
END;
```

**Review Queue** — Auto-enqueues tasks for review:
```sql
CREATE TRIGGER auto_enqueue_review
AFTER INSERT ON gate_checkpoints
WHEN NEW.gate_type = 'task-review' AND NEW.status = 'pending'
BEGIN
  INSERT INTO review_queue (task_id, requested_by)
  SELECT NEW.task_id, t.assigned_to FROM tasks t WHERE t.id = NEW.task_id;
END;
```

**Review SLA** — Sets 24-hour deadline for reviews:
```sql
CREATE TRIGGER set_review_sla
AFTER INSERT ON gate_checkpoints
WHEN NEW.gate_type = 'task-review' AND NEW.status = 'pending'
BEGIN
  INSERT INTO gate_sla (gate_id, deadline)
  VALUES (NEW.id, datetime('now', '+24 hours'));
END;
```

**Presence Cleanup** — Removes stale agent entries (>5 min):
```sql
CREATE TRIGGER cleanup_stale_presence
AFTER INSERT ON agent_presence
BEGIN
  DELETE FROM agent_presence WHERE heartbeat < (strftime('%s','now') - 300);
END;
```

---

## Workflows

### New Story

```bash
acts init PROJ-42 --title "Add user authentication"
acts task create T1 --title "Setup auth middleware" --story PROJ-42
```

### Task Lifecycle

```bash
# 1. Preflight
acts gate add --task T1 --type approve --status approved --by developer
acts task update T1 --status IN_PROGRESS --assigned-to alice

# 2. Implementation
# ... agent writes code ...

# 3. Review
acts review T1
acts approve T1
acts task update T1 --status DONE
```

### Quick Bug Fix

```bash
acts task create BUG-1 --title "Fix null pointer" --labels '["bug"]'
acts task update BUG-1 --status IN_PROGRESS  # No preflight needed
# ... fix ...
acts review BUG-1
acts approve BUG-1
acts task update BUG-1 --status DONE
```

### Multi-Story

```bash
acts story create PROJ-43 --title "JWT refresh" --from main
acts story switch PROJ-43
# ... work in worktree ...
acts story merge PROJ-43 --into main
```

---

## Integration

### OpenCode Plugin

Add to `opencode.json`:
```json
{
  "plugin": ["./.opencode/plugins/acts.js"]
}
```

### Manual CLI (Claude, Cursor, etc.)

Add ACTS commands to `AGENTS.md`.

See [docs/INTEGRATION.md](docs/INTEGRATION.md) for detailed setup.

---

## Migration from v1.0.0

The installer (`install.sh --update`) automatically migrates existing projects. Manual migration:

```bash
acts migrate
```

This adds:
- WAL mode for concurrent access
- Story type and labels columns
- Maintenance story (`__maintenance__`)
- Multi-story tables (story_gates, active_story, file_conflicts)
- Proactive signal tables (unblock_events, review_queue, agent_presence, gate_sla)
- New enforcement and proactive triggers

---

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| 1.1.0 | 2026-05 | Multi-story, WAL mode, maintenance tasks, proactive triggers, changelog, git-based review |
| 1.0.0 | 2026-01 | SQLite backend, Zig binary, gate triggers |
| 0.6.2 | 2026-04 | Code review gates, GitHuman integration |
| 0.6.1 | 2026-03 | Session summaries, agent compliance |
| 0.6.0 | 2026-03 | Operations framework, preflight |

---

## License

MIT License
