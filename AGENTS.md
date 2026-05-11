# acts-spec

## Setup
- Install: `[install command]`
- Dev: `[dev command]`
- Test: `[test command]`

## Code Style
[Project style conventions]

## Testing
[Project testing conventions]

## PR Instructions
- Title format: `[format]`
- Run lint and test before committing

---

## ACTS Integration

This project uses ACTS (Agent Collaborative Tracking Standard) for multi-developer coordination.

### Agent Framework

This project uses [superpowers](https://github.com/obra/superpowers) for agent workflow skills.

**Required for all agents:**
- Install superpowers plugin for your platform before starting work
- Skills auto-activate: brainstorming, TDD, subagent-driven-development, code review
- ACTS handles multi-developer coordination (state, handoffs, file ownership)
- Superpowers handles single-developer agent quality (TDD, planning, code review, debugging)

### Rules
- Agent MUST read state before writing code: `acts state read`
- Agent MUST NOT modify files owned by completed tasks: `acts scope check --task <id> --file <path>`
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion (v0.6.1)

### Review Workflow

```bash
# 1. Agent completes implementation
# ... writes code ...

# 2. Agent creates review context with rationale (optional but recommended)
cat > .acts/reviews/T1-context.json << 'EOF'
{
  "version": 1,
  "summary": "Replaced tmux with hunk daemon for cleaner UX",
  "files": [
    {
      "path": "src/main.zig",
      "summary": "Added daemon spawning and session seeding",
      "annotations": [
        {
          "newRange": [354, 397],
          "summary": "Three new daemon management functions",
          "rationale": "spawnHunkDaemon starts the broker, seedHunkSession registers a session, killHunkDaemon cleans up"
        }
      ]
    }
  ]
}
EOF

# 3. Agent launches review (auto-detects context file)
acts review T1
#   → If TTY: opens hunk diff interactively
#   → If no TTY: starts daemon, exports artifact, polls for approval

# 4. Human reviews in hunk, then approves:
acts approve T1

# 5. Agent marks task done
acts task update T1 --status DONE
```

### ACTS Binary Commands
- `acts init <story-id>` — Initialize new ACTS story
- `acts state read` — Read current story state
- `acts state write --story <id>` — Update story state (JSON from stdin)
- `acts task get <task-id>` — Get task details
- `acts task update <id> --status <status>` — Update task status (enforces gates)
- `acts review <task-id>` — Interactive code review with hunk
- `acts approve <task-id>` — Approve task-review gate (shorthand)
- `acts reject <task-id>` — Request changes on task-review gate (shorthand)
- `acts gate add --task <id> --type <type> --status <status>` — Add gate checkpoint
- `acts ownership map` — Show file ownership
- `acts scope check --task <id> --file <path>` — Check if file is safe to modify
- `acts validate` — Validate entire ACTS project
- `acts migrate` — Force schema migration

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

### OpenCode Plugin
The ACTS OpenCode plugin is installed at `.opencode/plugins/acts.js`.
Add `"./.opencode/plugins/acts.js"` to your `opencode.json` plugin array.

### Data Storage
- Structured state (stories, tasks, gates, decisions): SQLite at `.acts/acts.db`
- Narratives (plan, spec, sessions, notes): Markdown files
- `.story/state.json`: REMOVED (replaced by SQLite)

### Architecture
[Reference to project architecture docs]

### Forbidden
[Project forbidden patterns]
