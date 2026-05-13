#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# append-acts.sh — Append ACTS integration to AGENTS.md
#
# Usage:
#   ./scripts/append-acts.sh                    # append to ./AGENTS.md
#   ./scripts/append-acts.sh /path/to/AGENTS.md # append to specific file
#   ./scripts/append-acts.sh --dry-run          # show what would be appended
# ─────────────────────────────────────────────

TARGET="${1:-AGENTS.md}"
DRY_RUN=false

if [ "$TARGET" = "--dry-run" ]; then
  TARGET="AGENTS.md"
  DRY_RUN=true
fi

ACTS_SECTION='---

## ACTS Integration

This project uses ACTS (Agent Collaborative Tracking Standard) v1.0.0 for multi-developer coordination.

### Rules
- Agent MUST read state before writing code: `acts state read`
- Agent MUST NOT modify files owned by completed tasks: `acts scope check --task <id> --file <path>`
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion (v1.0.0)

### ACTS Commands
- `acts init <story-id>` — Initialize new ACTS story
- `acts state read` — Read current story state
- `acts state write --story <id>` — Update story state (JSON from stdin)
- `acts task get <task-id>` — Get task details
- `acts task update <id> --status <status>` — Update task status (enforces gates)
- `acts gate add --task <id> --type <type> --status <status>` — Add gate checkpoint
- `acts ownership map` — Show file ownership
- `acts scope check --task <id> --file <path>` — Check if file is safe to modify
- `acts validate` — Validate entire ACTS project
- `acts migrate` — Force schema migration

### Gate Protocol
1. Before starting task: `acts gate add --task <id> --type approve --status approved`
2. Before completing task: `acts gate add --task <id> --type task-review --status approved`

### File Override Protocol

Files owned by **DONE** tasks are locked by default. To modify a locked file:

1. **Agent requests override:**
   ```
   acts_override request --file src/locked.ts --task T3 --reason "bugfix"
   ```

2. **Human developer MUST approve:**
   ```
   acts_override approve --override_id ovr-abc123
   ```
   *Or edit `.acts/override-approvals.json` manually.*

3. **Agent verifies approval:**
   ```
   acts_override check --override_id ovr-abc123
   ```

**Rules:**
- AI agents MUST NEVER approve their own override requests.
- Overrides expire after 24 hours.
- All approvals are logged in `.acts/override-approvals.json` for audit.
- Without approval, the agent MUST NOT modify the file.

### Data Storage
- Structured state: SQLite at `.acts/acts.db`
- Narratives: Markdown files in `.story/`

### Agent Configuration
```json
{
  "tool": "Cursor",
  "version": "0.45.0",
  "model": "claude-3.5-sonnet",
  "cost_limit_per_session": 10.00,
  "config_preset": "default-ruleset"
}
```

### Architecture
[Reference to project architecture docs]

### Forbidden
[Project forbidden patterns]'

if [ "$DRY_RUN" = "true" ]; then
  echo "Would append to: $TARGET"
  echo ""
  echo "$ACTS_SECTION"
  exit 0
fi

if [ ! -f "$TARGET" ]; then
  echo "❌ File not found: $TARGET"
  echo ""
  echo "Usage: $0 [path/to/AGENTS.md] [--dry-run]"
  exit 1
fi

# Check if ACTS section already exists
if grep -q "## ACTS Integration" "$TARGET"; then
  echo "⚠️  ACTS Integration section already exists in $TARGET"
  echo "   Remove it first or edit manually."
  exit 1
fi

# Append ACTS section
echo "" >> "$TARGET"
echo "$ACTS_SECTION" >> "$TARGET"

echo "✅ ACTS Integration appended to $TARGET"
echo ""
echo "Next steps:"
echo "  1. Edit $TARGET to customize the ACTS section"
echo "  2. Initialize ACTS in your project: acts init <story-id>"
echo "  3. Configure the OpenCode plugin in opencode.json"
echo "  4. Run 'acts validate' to verify setup"
