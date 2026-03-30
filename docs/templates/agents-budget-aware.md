# Agent Configuration — Budget-Aware Project

## Rules
- Agent MUST read `.story/state.json` before writing code
- Agent MUST NOT modify files owned by completed tasks
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST run code review before task completion (v0.4.0)
- Agent SHOULD use cost-effective models for routine tasks

## Agent Configuration
```json
{
  "tool": "Cursor",
  "version": "0.45.0",
  "primary_model": "claude-3.5-sonnet",
  "fallback_model": "gpt-4o-mini",
  "cost_limit_per_session": 5.00,
  "config_preset": "efficient-ruleset"
}
```

## Budget Rules
1. **Simple tasks** (docs, chore, test-only): Use fallback model
2. **Complex tasks** (architecture, new features): Use primary model
3. **Code review**: Use primary model (quality matters)
4. **Preflight/Status**: Read-only, minimal tokens

## Session Budgets
- $2.00 for simple tasks (docs, chore)
- $5.00 for standard tasks
- $10.00 for complex tasks (new features, architecture)
- Alert at 80% of budget

## Architecture
- Next.js 15 + TypeScript
- Supabase for DB
- Read full: `.architecture/overview.md`

## Testing
- Vitest for unit tests
- Playwright for E2E
- Read full: `.testing/conventions.md`

## Git
- Branch naming: `story/<STORY_ID>`
- Commit messages: `feat(<STORY_ID>): <description>`
- No PR required for features < 100 lines

## Forbidden
- Never commit `.env` files
- Never use `eval()`
- Never store API keys in code
