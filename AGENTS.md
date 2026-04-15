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
- Agent MUST read `.story/state.json` before writing code
- Agent MUST NOT modify files owned by completed tasks
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion (v0.6.0)

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

### MCP Context Engine (optional)
If Layer 7 is enabled, the MCP server delivers context automatically.
No manual file reads needed. Configure in `.acts/acts.json`.

### Architecture
[Reference to project architecture docs]

### Forbidden
[Project forbidden patterns]
