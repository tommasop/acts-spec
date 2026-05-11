# ACTS Core v1.0.0

**Agent Collaborative Tracking Standard** — A standalone binary for multi-developer coordination using SQLite-backed state and protocol enforcement.

[![CI](https://github.com/tommasop/acts-spec/actions/workflows/ci.yml/badge.svg)](https://github.com/tommasop/acts-spec/actions/workflows/ci.yml)
[![Release](https://github.com/tommasop/acts-spec/actions/workflows/release.yml/badge.svg)](https://github.com/tommasop/acts-spec/releases)

## What is ACTS?

ACTS is a protocol for coordinating AI-assisted software development across multiple sessions, developers, and tools. It prevents context loss, enforces code review gates, tracks file ownership, and maintains an audit trail of decisions.

**Key features:**

- **SQLite-backed state** — Structured data (stories, tasks, gates, decisions) in `.acts/acts.db`
- **Gate enforcement at database level** — SQLite triggers prevent invalid state transitions
- **Markdown narratives** — Session summaries, plans, and specs remain human-readable
- **Standalone binary** — Single Zig executable, no runtime dependencies (except libc)
- **Cross-platform** — Linux (x86_64, aarch64), macOS (x86_64, aarch64)

## Installation

### Prerequisites

- **hunk** — Review-first terminal diff viewer (required for `acts review`)
  ```bash
  npm install -g hunkdiff
  # or
  bun install -g hunkdiff
  ```

### Pre-built Binaries

Download from [GitHub Releases](https://github.com/tommasop/acts-spec/releases):

```bash
# Linux x86_64
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-linux-x86_64.tar.gz | tar xz
sudo mv acts-linux-x86_64 /usr/local/bin/acts

# macOS Apple Silicon
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-macos-aarch64.tar.gz | tar xz
sudo mv acts-macos-aarch64 /usr/local/bin/acts
```

### Build from Source

Requires [Zig 0.13.0](https://ziglang.org/download/):

```bash
cd acts-core
zig build release
# Binary: zig-out/bin/acts
```

### Project Setup

Add the binary to your project:

```bash
# Option 1: Copy to project
cp acts-core/zig-out/bin/acts .acts/bin/acts

# Option 2: Install globally
zig build release && sudo cp zig-out/bin/acts /usr/local/bin/
```

## Quick Start

### Initialize a Story

```bash
acts init PROJ-42 --title "Add user authentication"
# Creates:
#   .acts/acts.db      (SQLite database)
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
#   "tasks": [...]
# }
```

### Update State

```bash
echo '{"status": "APPROVED", "spec_approved": true}' | acts state write --story PROJ-42
```

### Manage Tasks

```bash
# Create task (via state write)
echo '{"tasks": [{"id": "T1", "title": "Add login endpoint", "status": "TODO"}]}' | acts state write --story PROJ-42

# Start task (requires preflight gate)
acts gate add --task T1 --type approve --status approved --by developer
acts task update T1 --status IN_PROGRESS --assigned-to alice

# Interactive code review (launches hunk diff)
acts review T1
# After reviewing in hunk, approve:
acts approve T1

# Or request changes:
acts reject T1

# Complete task
acts task update T1 --status DONE
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

### Validate Sessions

```bash
acts session parse .story/sessions/20260105-143022-alice.md
# Outputs structured JSON

acts session validate .story/sessions/20260105-143022-alice.md
# Exit 0 if valid, 1 if missing required sections
```

### Validate Project

```bash
acts validate
# Checks schema version, required files, session validity
```

## Command Reference

| Command | Description | Example |
|---------|-------------|---------|
| `init <story-id>` | Initialize new story | `acts init PROJ-42` |
| `state read` | Read story state as JSON | `acts state read` |
| `state write` | Write story state from JSON | `echo '{...}' \| acts state write --story PROJ-42` |
| `task get <id>` | Get task details | `acts task get T1` |
| `task update <id>` | Update task status | `acts task update T1 --status DONE` |
| `review <id>` | Interactive code review with hunk | `acts review T1` |
| `approve <id>` | Approve task-review gate | `acts approve T1` |
| `reject <id>` | Request changes on task-review gate | `acts reject T1` |
| `gate add` | Add gate checkpoint | `acts gate add --task T1 --type approve --status approved` |
| `gate list` | List checkpoints | `acts gate list --task T1` |
| `decision add` | Record decision | `echo '{...}' \| acts decision add` |
| `decision list` | List decisions | `acts decision list --task T1` |
| `approach add --rejected` | Record rejected approach | `echo '{...}' \| acts approach add --rejected` |
| `question add` | Add open question | `echo '{...}' \| acts question add` |
| `question resolve` | Resolve question | `acts question resolve 1 --resolution "..."` |
| `ownership map` | Show file ownership | `acts ownership map` |
| `scope check` | Check file scope | `acts scope check --task T1 --file src/auth.ts` |
| `session parse` | Parse session markdown | `acts session parse file.md` |
| `session validate` | Validate session | `acts session validate file.md` |
| `validate` | Full project validation | `acts validate` |
| `migrate` | Force schema migration | `acts migrate` |

### Code Review Workflow

```bash
# Start interactive review (launches hunk TUI)
acts review T1

# Review with agent rationale (auto-detects .acts/reviews/T1-context.json)
acts review T1 --agent-context notes.json

# Review with watch mode (auto-reload on file changes)
acts review T1 --watch

# After reviewing, approve or reject:
acts approve T1       # Adds approved task-review gate
acts reject T1        # Adds changes_requested gate
```

### Agent Context Format

Create `.acts/reviews/<task-id>-context.json` to provide inline agent rationale:

```json
{
  "version": 1,
  "summary": "Overall change rationale",
  "files": [
    {
      "path": "src/main.zig",
      "summary": "What changed",
      "annotations": [
        {
          "newRange": [15, 35],
          "summary": "Visible inline note",
          "rationale": "Longer explanation of why"
        }
      ]
    }
  ]
}
```

## Architecture

### Data Model

**SQLite** (`.acts/acts.db`) — Source of truth for structured data:

- `stories` — Story metadata and status
- `tasks` — Task definitions with status and assignments
- `task_files` — Many-to-many mapping of tasks to files
- `task_dependencies` — Dependency graph
- `gate_checkpoints` — Gate approvals with timestamps
- `decisions` — Recorded decisions with evidence
- `rejected_approaches` — Cross-task learning
- `open_questions` — Unresolved questions
- `operation_log` — Audit trail

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
```

This means:

- An agent **cannot** bypass gates by editing files directly
- Enforcement happens in SQLite, not in application code
- Even if the binary is bypassed, the triggers still fire

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
acts gate add --task T1 --type task-review --status approved --by reviewer
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
zig build release

# Cross-compile for all platforms
zig build cross
```

### Adding a New Command

1. Add command parser in `src/main.zig` (`handleXxx` function)
2. Add database method in `src/db.zig`
3. Update `printUsage()` with new command
4. Register in command dispatch in `main()`

## License

MIT License — See [LICENSE](LICENSE)

## Contributing

1. Run `acts validate` before committing
2. Follow the ACTS protocol for your own contributions
3. Ensure cross-compilation passes: `zig build cross`
