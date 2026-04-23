# [Project Name]

## Setup
- Install: `[install command]`
- Dev: `[dev command]`
- Test: `[test command]`

## Code Style
[Project style conventions]

## Testing
- Frontend: Vitest + React Testing Library
- Backend: Node.js test runner + Supertest
- Integration: Playwright
- Read full: `.testing/conventions.md`

## PR Instructions
- Title format: `[format]`
- Run lint and test before committing

---

## ACTS Integration

This project uses ACTS (Agent Collaborative Tracking Standard) for multi-developer coordination.

### Rules
- Agent MUST read `.story/state.json` before writing code
- Agent MUST NOT modify files owned by completed tasks
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST run code review before task completion (v0.4.0)
- Agent MUST use role-specific configuration when defined

### Role Configurations

#### Frontend
- **Agent:** Cursor v0.45.0 (Claude-3.5-Sonnet)
- **Config:** `.agents/frontend-ruleset.json`
- **Scope:** `src/components/`, `src/pages/`, `src/hooks/`
- **Session Budget:** $8.00
- **Notes:** TypeScript strict mode, ESLint enforced

#### Backend
- **Agent:** Cursor v0.45.0 (Claude-3.5-Sonnet)
- **Config:** `.agents/backend-ruleset.json`
- **Scope:** `src/routes/`, `src/services/`, `src/models/`
- **Session Budget:** $12.00
- **Notes:** Database migrations require review

#### Infrastructure
- **Agent:** Cursor v0.45.0 (Claude-3.5-Sonnet)
- **Config:** `.agents/infra-ruleset.json`
- **Scope:** `infrastructure/`, `scripts/`, `.github/`
- **Session Budget:** $5.00
- **Notes:** Infrastructure changes require approval

### Orchestration Patterns

#### Pattern 1: Sequential Execution
For stories with dependent tasks, execute sequentially:
1. Complete frontend subtask with frontend config
2. Run task-review, get approval
3. Complete backend subtask with backend config
4. Run task-review, get approval

#### Pattern 2: Parallel Execution (Independent Files)
For stories with independent tasks touching different file scopes:
- Developer 1 runs frontend agent on `.tsx` files (in their worktree)
- Developer 2 runs backend agent on `.py` files (in their worktree)
- Merge via standard git workflow

#### Pattern 3: Agent-Assisted Review
For complex code review:
1. Agent runs preflight, presents report
2. Agent suggests review approach
3. Human reviews in GitHuman (v0.6.2+ default) or lazygit (v0.5.0)
4. Agent addresses comments, human approves

### Architecture
- Frontend: React 19 + TypeScript
- Backend: Fastify + PostgreSQL
- Shared: TypeScript packages in `packages/`
- Read full: `.architecture/overview.md`

### Forbidden
- Never commit `.env` files
- Never use `eval()` or `Function()`
- Never store secrets in code
- Never bypass code review gate
