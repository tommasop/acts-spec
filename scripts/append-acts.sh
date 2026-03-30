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

This project uses ACTS (Agent Collaborative Tracking Standard) for multi-developer coordination.

### Rules
- Agent MUST read `.story/state.json` before writing code
- Agent MUST NOT modify files owned by completed tasks
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion (v0.4.0)

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
echo "  2. Create .acts/ and .story/ directories"
echo "  3. Install GitHuman: npm install -g githuman"
