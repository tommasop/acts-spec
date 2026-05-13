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
- Agent MUST run code review before task completion (v1.0.0)

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

### ACTS Mode (Plugin)

The OpenCode plugin supports three modes:

| Mode | Behavior |
|------|----------|
| `off` | No ACTS context injection. Use when ACTS is not relevant to the conversation. |
| `on` | Full context injection: story state, active tasks, file ownership, approved overrides. |
| `strict` | All of `on` plus enforcement language. Agent MUST follow gate protocol explicitly. |

**Commands:**
- `acts_mode enter [--level strict]` — Activate ACTS mode
- `acts_mode exit` — Deactivate ACTS mode
- `acts_mode status` — Show current mode

**When to use strict mode:**
- Multi-developer projects with concurrent agents
- High-risk changes (production code, infrastructure)
- When gate violations have been observed

### File Override Protocol

Files owned by **DONE** tasks are locked by default. To modify a locked file:

**1. Agent requests override:**
```
acts_override request --file src/locked.ts --task T3 --reason "bugfix: null pointer"
```

**2. Human developer MUST approve:**
```
acts_override approve --override_id ovr-abc123
```
*Or edit `.acts/override-approvals.json` manually.*

**3. Agent verifies approval:**
```
acts_override check --override_id ovr-abc123
```

**Rules:**
- AI agents MUST NEVER approve their own override requests.
- Overrides expire after 24 hours.
- All approvals are logged in `.acts/override-approvals.json` for audit.
- Without approval, the agent MUST NOT modify the file.

### Data Storage
- Structured state (stories, tasks, gates, decisions): SQLite at `.acts/acts.db`
- Narratives: Markdown files
- `.story/state.json`: REMOVED (replaced by SQLite)

### Architecture
[Reference to project architecture docs]

### Forbidden
[Project forbidden patterns]
