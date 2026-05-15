# ACTS Core v1.1.2

**Agent Collaborative Tracking Standard** — A standalone binary for multi-developer coordination using SQLite-backed state and protocol enforcement.

[![CI](https://github.com/tommasop/acts-spec/actions/workflows/ci.yml/badge.svg)](https://github.com/tommasop/acts-spec/actions/workflows/ci.yml)
[![Release](https://github.com/tommasop/acts-spec/actions/workflows/release.yml/badge.svg)](https://github.com/tommasop/acts-spec/releases)

## What is ACTS?

ACTS is a protocol for coordinating AI-assisted software development across multiple sessions, developers, and tools. It prevents context loss, enforces code review gates, tracks file ownership, and maintains an audit trail of decisions.

**Key features:**

- **SQLite-backed state** — Structured data (stories, tasks, gates, decisions) in `.acts/acts.db`
- **Gate enforcement at database level** — SQLite triggers prevent invalid state transitions
- **WAL mode** — Concurrent multi-story access with queued writes
- **Multi-story development** — Git worktrees with cross-story ownership enforcement
- **Human Review Experience (HRE)** — Vim-navigable terminal review with quality gates, agent rationale, risk assessment, and multi-file diff navigation
- **File override system** — Human-only approval to modify files owned by DONE tasks in other stories
- **Maintenance mode** — Quick bug fixes without story ceremony
- **Standalone binary** — Single Zig executable, no runtime dependencies (except libc)
- **Cross-platform** — Linux (x86_64, aarch64), macOS (x86_64, aarch64)

## Installation

### One-Line Installer (Recommended)

```bash
# System-wide install
bash <(curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/main/install.sh)

# Project-local install (to ./.acts/bin/)
bash <(curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/main/install.sh) --local

# Update to latest (auto-migrates existing projects)
bash <(curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/main/install.sh) --update
```

Or using Make:
```bash
make install        # System-wide
make install-local  # Project-local
make update         # Update existing
```

### Manual Install (Pre-built Binaries)

Download from [GitHub Releases](https://github.com/tommasop/acts-spec/releases):

```bash
# Linux x86_64
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.1.2/acts-linux-x86_64.tar.gz | tar xz
sudo mv acts/bin/acts /usr/local/bin/acts

# macOS Apple Silicon
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.1.2/acts-macos-aarch64.tar.gz | tar xz
sudo mv acts/bin/acts /usr/local/bin/acts
```

### Build from Source

Requires [Zig 0.13.0](https://ziglang.org/download/):

```bash
cd acts-core
zig build release -Dversion=1.1.2
# Binary: zig-out/bin/acts
```

### Project Setup

```bash
# Option 1: Use installer
make install-local

# Option 2: Manual copy
cp acts-core/zig-out/bin/acts .acts/bin/acts

# Option 3: Install globally
zig build release && sudo cp zig-out/bin/acts /usr/local/bin/
```

## Quick Start

### Initialize a Story

```bash
acts init PROJ-42 --title "Add user authentication"
# Creates:
#   .acts/acts.db      (SQLite database, WAL mode)
#   .story/plan.md     (plan template)
#   .story/spec.md     (spec template)
#   .story/sessions/   (session directory)
```

### Read State

```bash
acts state read
# Outputs JSON:
# {
#   "story_id": "PROJ-42",
#   "status": "ANALYSIS",
#   "type": "feature",
#   "tasks": [...]
# }
```

### Update State

```bash
echo '{"status": "APPROVED", "spec_approved": true}' | acts state write --story PROJ-42
```

### Manage Tasks

```bash
# Create task (auto-assigned to __maintenance__ story)
acts task create BUG-1 --title "Fix null pointer" --labels '["bug","fix"]'

# Create task in a specific story
acts task create T1 --title "Add login endpoint" --story PROJ-42

# Start task (requires preflight gate)
acts gate add --task T1 --type approve --status approved --by developer
acts task update T1 --status IN_PROGRESS --assigned-to alice

# Code review (enhanced HRE with vim navigation)
acts review T1
# → Auto-detects project type and runs quality gates (test, lint, typecheck, build)
# → Shows agent rationale, risk assessment, previous rejections
# → Multi-file diff with hunk navigation (]c/[c, ]f/[f, j/k, gg/G)
# → Approve with 'a', reject with 'r', quit with 'q'

# Approve or request changes:
acts approve T1
acts reject T1

# Complete task
acts task update T1 --status DONE
```

### Multi-Story Development

```bash
# Create a new story with git worktree
acts story create PROJ-43 --title "JWT refresh" --from main

# List all stories
acts story list

# Switch active story
acts story switch PROJ-43

# Archive completed story
acts story archive PROJ-42

# Merge story (enforces all tasks DONE + reviews approved)
acts story merge PROJ-43 --into main
```

### Check File Ownership

```bash
acts ownership map
# Shows which DONE tasks own which files

acts scope check --task T2 --file src/auth.ts
# {
#   "file_path": "src/auth.ts",
#   "action": "error",
#   "message": "File is owned by DONE task T1. Modifications require explicit approval."
# }
```

### File Overrides (Human-Only)

When a task needs to modify a file owned by a DONE task in another story:

```bash
# Agent requests override
acts override request --file src/auth.ts --task T2 --reason "bugfix: null pointer in auth flow"

# Human approves (AI agents CANNOT approve overrides)
acts override approve 1 --by "alice"

# Override expires after 24 hours automatically
acts override list --pending
```

### Generate Changelog

```bash
acts changelog --story PROJ-42
# Derives changelog from task labels, decisions, rejected approaches
```

### Validate Project

```bash
acts validate
# Checks schema version, required files, session validity
```

## Workflow Guide

### Full Developer Workflow

```bash
# 1. Initialize story
acts init PROJ-42 --title "Add user authentication"

# 2. Create tasks
acts task create T1 --title "Add login endpoint" --story PROJ-42
acts task create T2 --title "Add JWT middleware" --story PROJ-42

# 3. Start work (requires preflight gate)
acts gate add --task T1 --type approve --status approved --by alice
acts task update T1 --status IN_PROGRESS --assigned-to alice

# 4. Implement code
# ... write code ...

# 5. Code review (Human Review Experience)
acts review T1
#   → Auto-detects project type (npm, cargo, go, make, etc.)
#   → Runs quality gates: test, lint, typecheck, build
#   → Shows quality gate results with timing
#   → Shows agent rationale (why the change was made)
#   → Shows previous rejections (if any)
#   → Shows file list with risk assessment (HIGH/MEDIUM/LOW)
#   → Interactive vim-style navigation:
#     j/k scroll, ]c/[c next/prev hunk, ]f/[f next/prev file
#     gg/G go to top/bottom, a approve, r reject, q quit
#     :qa/:cq ex-mode approve/reject, Ctrl-g show position
#
#   If approved:
#     Task-review gate added by <user>
#   If rejected:
#     Gate marked as 'changes_requested'

# 6. Complete task
acts task update T1 --status DONE
```

### Quick Bug Fix (Maintenance Story)

```bash
# Create bug task (auto-assigned to __maintenance__)
acts task create BUG-1 --title "Fix crash on startup" --labels '["bug","urgent"]'

# No preflight gate needed for maintenance tasks
acts task update BUG-1 --status IN_PROGRESS

# ... fix the bug ...

# Review and approve
acts review BUG-1
acts approve BUG-1
acts task update BUG-1 --status DONE
```

### Updating ACTS

```bash
# Update system-wide installation (auto-migrates projects)
bash <(curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/main/install.sh) --update

# Or using Make
make update

# Verify version
acts version
```

### Uninstalling

```bash
make uninstall
# Or manually:
rm -f /usr/local/bin/acts ~/.local/bin/acts ./.acts/bin/acts
```

## Command Reference

### Story Management

| Command | Description | Example |
|---------|-------------|---------|
| `init <story-id>` | Initialize new story | `acts init PROJ-42` |
| `story create <id>` | Create story with worktree | `acts story create PROJ-43 --title "..."` |
| `story list` | List all stories | `acts story list --include-maintenance` |
| `story switch <id>` | Switch active story | `acts story switch PROJ-43` |
| `story archive <id>` | Archive completed story | `acts story archive PROJ-42` |
| `story merge <id>` | Merge story into branch | `acts story merge PROJ-43 --into main` |
| `story graph` | Show dependency graph | `acts story graph --format dot` |

### State

| Command | Description | Example |
|---------|-------------|---------|
| `state read` | Read story state as JSON | `acts state read` |
| `state write` | Write story state from JSON | `echo '{...}' \| acts state write --story PROJ-42` |

### Tasks

| Command | Description | Example |
|---------|-------------|---------|
| `task create <id>` | Create a new task | `acts task create T1 --title "..." --story PROJ-42` |
| `task get <id>` | Get task details | `acts task get T1` |
| `task list` | List tasks | `acts task list --maintenance` |
| `task update <id>` | Update task status | `acts task update T1 --status DONE` |
| `task move <id>` | Move task to another story | `acts task move BUG-1 --to PROJ-42` |

### Review

| Command | Description | Example |
|---------|-------------|---------|
| `review <id>` | Enhanced HRE review with vim navigation | `acts review T1` |
| `approve <id>` | Approve task-review gate | `acts approve T1` |
| `reject <id>` | Request changes | `acts reject T1` |

### Overrides (Human-Only)

| Command | Description | Example |
|---------|-------------|---------|
| `override request` | Request file override | `acts override request --file src/x.ts --task T2 --reason "..."` |
| `override approve <id>` | Approve override (human only) | `acts override approve 1 --by "alice"` |
| `override reject <id>` | Reject override | `acts override reject 1` |
| `override list` | List overrides | `acts override list --pending` |

### Gates

| Command | Description | Example |
|---------|-------------|---------|
| `gate add` | Add gate checkpoint | `acts gate add --task T1 --type approve --status approved` |
| `gate list` | List checkpoints | `acts gate list --task T1` |
| `gate-sla` | Show gate SLA status | `acts gate-sla --breached` |

### Decisions & Learnings

| Command | Description | Example |
|---------|-------------|---------|
| `decision add` | Record decision | `echo '{...}' \| acts decision add` |
| `decision list` | List decisions | `acts decision list --task T1` |
| `approach add --rejected` | Record rejected approach | `echo '{...}' \| acts approach add --rejected` |
| `question add` | Add open question | `echo '{...}' \| acts question add` |
| `question resolve` | Resolve question | `acts question resolve 1 --resolution "..."` |

### Ownership & Scope

| Command | Description | Example |
|---------|-------------|---------|
| `ownership map` | Show file ownership | `acts ownership map` |
| `scope check` | Check file scope | `acts scope check --task T1 --file src/auth.ts` |

### Proactive Signals

| Command | Description | Example |
|---------|-------------|---------|
| `presence set` | Set agent presence | `acts presence set --agent alice --task T1` |
| `presence list` | Show active agents | `acts presence list` |
| `unblock list` | Show unblock events | `acts unblock list` |
| `unblock ack <id>` | Acknowledge unblock | `acts unblock ack 1` |
| `review-queue` | Show review queue | `acts review-queue --story PROJ-42` |

### Changelog

| Command | Description | Example |
|---------|-------------|---------|
| `changelog` | Generate changelog | `acts changelog --story PROJ-42 --format md` |

### Database

| Command | Description | Example |
|---------|-------------|---------|
| `db checkpoint` | Run WAL checkpoint | `acts db checkpoint` |
| `db status` | Show database status | `acts db status` |

### Sessions

| Command | Description | Example |
|---------|-------------|---------|
| `session parse` | Parse session markdown | `acts session parse file.md` |
| `session validate` | Validate session | `acts session validate file.md` |
| `session list` | List sessions for task | `acts session list --task T1` |

### Operations

| Command | Description | Example |
|---------|-------------|---------|
| `operation log` | Log operation | `echo '{...}' \| acts operation log --id op-1` |
| `operation list` | List operations | `acts operation list` |
| `operation show` | Show operation details | `acts operation show op-1` |

### Validation

| Command | Description | Example |
|---------|-------------|---------|
| `validate` | Full project validation | `acts validate` |
| `migrate` | Force schema migration | `acts migrate` |
| `version` | Show version | `acts version` |

## Architecture

### Data Model

**SQLite** (`.acts/acts.db`) — Source of truth for structured data:

- `stories` — Story metadata, type, branch, worktree path, semver
- `tasks` — Task definitions with status, assignments, labels
- `task_files` — Many-to-many mapping of tasks to files
- `task_dependencies` — Dependency graph
- `gate_checkpoints` — Gate approvals with timestamps
- `story_gates` — Story-level gates (story-approve, story-merge)
- `decisions` — Recorded decisions with evidence
- `rejected_approaches` — Cross-task learning
- `open_questions` — Unresolved questions
- `operation_log` — Audit trail
- `active_story` — Current active story (singleton)
- `unblock_events` — Dependency completion notifications
- `review_queue` — Pending review tasks
- `agent_presence` — Active agent tracking
- `gate_sla` — Review deadline tracking
- `file_conflicts` — Cross-story file conflict detection
- `file_overrides` — Human-approved file override requests (24h expiry)

**Markdown files** — Human-readable narratives:

- `.story/plan.md` — Implementation plan
- `.story/spec.md` — Specification and acceptance criteria
- `.story/sessions/*.md` — Session summaries
- `.story/tasks/<id>/notes.md` — Per-task notes

### Gate Enforcement

SQLite triggers enforce protocol gates at the database level:

```sql
-- Cannot start task without preflight gate
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

-- Cannot mark task DONE without task-review gate
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

-- Maintenance tasks auto-approve preflight gate
CREATE TRIGGER auto_approve_maintenance_preflight
BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'IN_PROGRESS' AND OLD.status = 'TODO'
BEGIN
  INSERT OR IGNORE INTO gate_checkpoints (task_id, gate_type, status, approved_by)
  SELECT NEW.id, 'approve', 'approved', '__system__'
  FROM tasks t WHERE t.id = NEW.id AND t.story_id = '__maintenance__';
END;

-- Cannot merge story with open tasks or unreviewed tasks
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

This means:

- An agent **cannot** bypass gates by editing files directly
- Enforcement happens in SQLite, not in application code
- Even if the binary is bypassed, the triggers still fire

### Proactive Triggers

In addition to enforcement triggers, ACTS uses proactive triggers that create useful state:

- `notify_dependency_unblock` — Auto-creates unblock event when dependency completes
- `auto_enqueue_review` — Auto-adds task to review queue when review gate is created
- `cleanup_stale_presence` — Auto-removes agent presence entries older than 5 minutes
- `set_review_sla` — Auto-sets 24-hour deadline for review gates
- `detect_file_conflict` — Auto-detects when two stories claim the same file

## Integration Guides

### OpenCode (Plugin)

The OpenCode plugin provides seamless integration with automatic context injection and a native `acts` tool.

**Installation:**

```bash
# In your project's opencode.json
{
  "plugin": [
    "superpowers@git+https://github.com/obra/superpowers.git",
    "acts-spec@git+https://github.com/tommasop/acts-spec.git"
  ]
}
```

**What the plugin does:**

1. Injects ACTS bootstrap context into the first user message of every session
2. Registers an `acts` tool that the agent can call directly
3. Auto-discovers the binary at `.acts/bin/acts`

**Agent usage:**

```
# The agent automatically knows to:
acts state read                           # Before writing code
acts scope check --task T1 --file src/x   # Before modifying files
acts gate add --task T1 --type task-review --status approved  # After review
```

See [docs/INTEGRATION.md](docs/INTEGRATION.md) for details.

### Claude / Cursor / Other Editors (Manual)

For editors without plugin support, agents use the binary via CLI commands.

**Setup:**

1. Install the binary (pre-built or from source)
2. Add to project `AGENTS.md`:

   ```markdown
   ## ACTS Commands
   - Read state: `acts state read`
   - Check ownership: `acts scope check --task <id> --file <path>`
   - Add gate: `acts gate add --task <id> --type <type> --status approved`
   ```

**Agent workflow:**

```bash
# 1. Preflight
acts state read
acts gate add --task T1 --type approve --status approved --by developer
acts task update T1 --status IN_PROGRESS

# 2. Implementation
# ... agent writes code ...

# 3. Review
acts review T1
acts approve T1
acts task update T1 --status DONE

# 4. Session summary
acts session validate .story/sessions/20260105-143022-alice.md
```

See [docs/INTEGRATION.md](docs/INTEGRATION.md) for platform-specific setup.

## Development

### Project Structure

```
acts-core/
├── build.zig          # Build configuration
├── build.zig.zon      # Package manifest
├── src/
│   ├── main.zig       # CLI entrypoint and command dispatch
│   ├── db.zig         # SQLite wrapper, CRUD, migrations
│   ├── cli.zig        # Argument parsing
│   ├── sessions.zig   # Markdown parser and validator
│   └── schema.sql     # Embedded SQLite schema + triggers
├── vendor/
│   ├── sqlite3.c      # Vendored SQLite3 (amalgamation)
│   └── sqlite3.h
└── tests/             # Unit tests
```

### Build Commands

```bash
cd acts-core

# Debug build
zig build

# Run tests
zig build test

# Release build (optimized)
zig build release -Dversion=1.1.2

# Cross-compile for all platforms
zig build cross -Dversion=1.1.2
```

### Adding a New Command

1. Add command parser in `src/main.zig` (`handleXxx` function)
2. Add database method in `src/db.zig`
3. Update `printUsage()` with new command
4. Register in command dispatch in `main()`

## Migration from v1.0.0

The installer automatically migrates existing projects when updating. Manual migration:

```bash
acts migrate
```

This adds:
- WAL mode for concurrent access
- Story type and labels columns
- Maintenance story (`__maintenance__`)
- Multi-story tables (story_gates, active_story, file_conflicts)
- Proactive signal tables (unblock_events, review_queue, agent_presence, gate_sla)
- New enforcement triggers (cross-story ownership, story merge)
- New proactive triggers (unblock notifications, review queue, presence cleanup, SLA)
- File override system (file_overrides table, human-only approval, 24h expiry)
- Human Review Experience (quality gate auto-detection, vim navigation, risk assessment)

## License

MIT License — See [LICENSE](LICENSE)

## Contributing

1. Run `acts validate` before committing
2. Follow the ACTS protocol for your own contributions
3. Ensure cross-compilation passes: `zig build cross`

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| 1.1.2 | 2026-05 | Human Review Experience (HRE), file override system, vim navigation, quality gates |
| 1.1.0 | 2026-05 | Multi-story, WAL mode, maintenance tasks, proactive triggers, changelog, git-based review |
| 1.0.0 | 2026-01 | SQLite backend, Zig binary, gate triggers |
| 0.6.2 | 2026-04 | Code review gates, GitHuman integration |
| 0.6.1 | 2026-03 | Session summaries, agent compliance |
| 0.6.0 | 2026-03 | Operations framework, preflight |
