# Agent Configuration — [Project Name]

## Rules
- Agent MUST read `.story/state.json` before writing code
- Agent MUST NOT modify files owned by completed tasks
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion (v0.4.0)

## Agent Configuration
```json
{
  "tool": "Cursor",
  "version": "0.45.0",
  "model": "claude-3.5-sonnet",
  "cost_limit_per_session": 10.00,
  "config_preset": "default-ruleset"
}
```

## Architecture
[Reference to project architecture docs]

## Testing
[Project testing conventions]

## Git
[Project git conventions]

## Forbidden
[Project forbidden patterns]
