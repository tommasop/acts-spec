# [Project Name]

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

This project uses ACTS (Agent Collaborative Tracking Standard) v1.0.0 for multi-developer coordination.

### Rules
- Agent MUST read state before writing code: `acts state read`
- Agent MUST NOT modify files owned by completed tasks: `acts scope check --task <id> --file <path>`
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion

### ACTS Commands
- `acts init <story-id>` — Initialize new ACTS story
- `acts state read` — Read current story state (JSON)
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
Files owned by DONE tasks are locked. To override:
1. Request: `acts_override request --file <path> --task <id> --reason "..."`
2. Human approves: `acts_override approve --override_id <id>`
3. Verify: `acts_override check --override_id <id>`
- AI agents MUST NEVER approve their own overrides.
- Approvals expire after 24 hours.

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
[Project forbidden patterns]
