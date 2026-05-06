# ACTS Specification v1.0.0

**Agent Collaborative Tracking Standard**

A protocol for coordinating AI-assisted software development through SQLite-backed state, gate enforcement, and session tracking.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Data Model](#data-model)
4. [Commands](#commands)
5. [Gate Enforcement](#gate-enforcement)
6. [Workflows](#workflows)
7. [Integration](#integration)
8. [Migration](#migration)

---

## Overview

ACTS v1.0.0 replaces the JSON-file-based state management of v0.6.x with a SQLite database and standalone Zig binary. This provides:

- **Atomic transactions** — No corrupted state from partial writes
- **Database-level enforcement** — SQLite triggers prevent invalid state transitions
- **Single binary** — No Python/TypeScript runtime dependencies
- **Cross-platform** — Linux, macOS (x86_64, aarch64)

---

## Architecture

```
Project Root
├── .acts/
│   ├── acts.db          # SQLite database (structured state)
│   ├── acts.json        # Configuration manifest
│   ├── bin/
│   │   └── acts         # Zig binary (CLI)
│   └── review-providers/# Review tool configs
├── .story/
│   ├── plan.md          # Implementation plan
│   ├── spec.md          # Specification
│   ├── sessions/        # Session summaries (*.md)
│   └── tasks/           # Per-task notes
└── AGENTS.md            # Project constitution
```

### Source of Truth

| Data | Storage | Access |
|------|---------|--------|
| Stories, tasks, gates | `.acts/acts.db` | `acts` binary |
| Decisions, approaches | `.acts/acts.db` | `acts` binary |
| Plan, spec | `.story/plan.md` | Direct file read |
| Session summaries | `.story/sessions/*.md` | `acts session` commands |
| Task notes | `.story/tasks/<id>/notes.md` | Direct file read |

---

## Data Model

### SQLite Schema

#### Stories

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Story identifier |
| acts_version | TEXT | ACTS version (e.g., "1.0.0") |
| title | TEXT | Human-readable title |
| status | TEXT | ANALYSIS, APPROVED, IN_PROGRESS, REVIEW, DONE |
| spec_approved | INTEGER | Boolean |
| created_at | TEXT | ISO 8601 timestamp |
| updated_at | TEXT | ISO 8601 timestamp |
| context_budget | INTEGER | Token budget |
| session_count | INTEGER | Number of sessions |
| compressed | INTEGER | Boolean |
| strict_mode | INTEGER | Boolean |
| metadata | TEXT | JSON blob |

#### Tasks

| Column | Type | Description |
|--------|------|-------------|
| id | TEXT PK | Task identifier (T1, T2, ...) |
| story_id | TEXT FK | Parent story |
| title | TEXT | Task title |
| description | TEXT | Task description |
| status | TEXT | TODO, IN_PROGRESS, BLOCKED, DONE |
| assigned_to | TEXT | Developer name |
| context_priority | INTEGER | 1-5 (1=critical) |
| review_status | TEXT | pending, approved, changes_requested, skipped |
| reviewed_at | TEXT | ISO 8601 timestamp |
| reviewed_by | TEXT | Reviewer name |

#### Task Files

Many-to-many mapping of tasks to files they touch.

#### Task Dependencies

Many-to-many mapping of tasks to their dependencies.

#### Gate Checkpoints

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| task_id | TEXT FK | Associated task |
| gate_type | TEXT | approve, task-review, commit-review, architecture-discuss |
| status | TEXT | pending, approved, changes_requested |
| approved_by | TEXT | Who approved |
| created_at | TEXT | ISO 8601 timestamp |
| resolved_at | TEXT | ISO 8601 timestamp |

#### Decisions

Recorded decisions with evidence and authority.

#### Rejected Approaches

Cross-task learning — approaches tried and rejected.

#### Open Questions

Unresolved questions with status tracking.

#### Operation Log

Audit trail of all operations.

---

## Commands

### Story Management

```bash
acts init <story-id> [--title "..."]
  # Creates .acts/acts.db, .story/plan.md, .story/spec.md, .story/sessions/

acts state read [--story <id>]
  # Outputs JSON state

acts state write --story <id>
  # Reads JSON from stdin, updates state
```

### Task Management

```bash
acts task get <task-id>
  # Outputs task JSON

acts task update <task-id> [--status <status>] [--assigned-to <name>]
  # Updates task, triggers gate enforcement
```

### Gates

```bash
acts gate add --task <id> --type <type> --status <status> [--by <name>]
  # Types: approve, task-review, commit-review, architecture-discuss

acts gate list --task <id>
  # Lists checkpoints for task
```

### Decisions & Learnings

```bash
acts decision add
  # Reads JSON from stdin

acts decision list --task <id>

acts approach add --rejected
  # Reads JSON from stdin

acts question add
  # Reads JSON from stdin

acts question resolve <id> [--resolution "..."] [--by <name>]
```

### Ownership & Scope

```bash
acts ownership map
  # Shows files owned by DONE tasks

acts scope check --task <id> --file <path>
  # Returns: ok, warn, or error
```

### Sessions

```bash
acts session parse <file.md>
  # Parses markdown to JSON

acts session validate <file.md>
  # Validates required sections

acts session list --task <id>
  # Lists and parses sessions for task
```

### Validation

```bash
acts validate
  # Full project validation

acts migrate
  # Force schema migration
```

---

## Gate Enforcement

### SQLite Triggers

Triggers enforce gates at the database level:

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

**Dependency Gate** (dependencies must be DONE):
```sql
CREATE TRIGGER enforce_dependencies
BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'IN_PROGRESS'
BEGIN
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM task_dependencies td
    JOIN tasks dep ON td.depends_on = dep.id
    WHERE td.task_id = NEW.id AND dep.status != 'DONE'
  )
  THEN RAISE(ABORT, 'Cannot start task: dependencies not met')
  END;
END;
```

### Strict Mode

Enable in `.acts/acts.json`:
```json
{
  "conformance_level": "strict"
}
```

Additional gates in strict mode:
- `commit-review` — Approve batch of commits before continuing
- `architecture-discuss` — Approve design decisions before implementing

---

## Workflows

### New Story

```bash
# 1. Initialize
acts init PROJ-42 --title "Add user authentication"

# 2. Add tasks
echo '{"tasks": [{"id": "T1", "title": "Setup auth middleware", "status": "TODO"}]}' | acts state write --story PROJ-42

# 3. Plan and spec are in .story/plan.md and .story/spec.md
```

### Task Lifecycle

```bash
# 1. Preflight
acts state read
acts gate add --task T1 --type approve --status approved --by developer
acts task update T1 --status IN_PROGRESS --assigned-to alice

# 2. Implementation
# ... agent writes code ...

# 3. Review
acts gate add --task T1 --type task-review --status approved --by reviewer
acts task update T1 --status DONE

# 4. Session summary
# ... write .story/sessions/20260105-143022-alice.md ...
acts session validate .story/sessions/20260105-143022-alice.md
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

Plugin provides:
- Automatic ACTS context injection
- Native `acts` tool registration
- Binary auto-discovery

### Manual CLI (Claude, Cursor, etc.)

Agents use Bash tool to execute `acts` commands.
Add ACTS commands to `AGENTS.md`.

See [docs/INTEGRATION.md](docs/INTEGRATION.md) for detailed setup.

---

## Migration from 0.6.x

See [docs/MIGRATION-0.6.2-to-1.0.0.md](docs/MIGRATION-0.6.2-to-1.0.0.md) for step-by-step migration guide.

Key changes:
- `.story/state.json` → `.acts/acts.db` (SQLite)
- Python/TypeScript scripts → Zig binary
- `acts-update` / `acts-validate` bash scripts → `acts` CLI commands
- JSON schemas → Embedded in binary

---

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| 1.0.0 | 2026-01 | SQLite backend, Zig binary, gate triggers |
| 0.6.2 | 2026-04 | Code review gates, GitHuman integration |
| 0.6.1 | 2026-03 | Session summaries, agent compliance |
| 0.6.0 | 2026-03 | Operations framework, preflight |

---

## License

MIT License
