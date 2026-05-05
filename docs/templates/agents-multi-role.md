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

This project uses ACTS (Agent Collaborative Tracking Standard) v1.0.0 for multi-developer coordination.

### Rules
- Agent MUST read state before writing code: `acts state read`
- Agent MUST NOT modify files owned by completed tasks: `acts scope check --task <id> --file <path>`
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST run code review before task completion
- Agent MUST use role-specific configuration when defined

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

### Data Storage
- Structured state: SQLite at `.acts/acts.db`
- Narratives: Markdown files in `.story/`

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
2. Run `acts gate add --task <id> --type task-review --status approved`
3. Complete backend subtask with backend config
4. Run `acts gate add --task <id> --type task-review --status approved`

#### Pattern 2: Parallel Execution (Independent Files)
For stories with independent tasks touching different file scopes:
- Developer 1 runs frontend agent on `.tsx` files (in their worktree)
- Developer 2 runs backend agent on `.py` files (in their worktree)
- Merge via standard git workflow

#### Pattern 3: Agent-Assisted Review
For complex code review:
1. Agent runs `acts state read`, presents report
2. Agent suggests review approach
3. Human reviews changes
4. Agent addresses comments, human approves via `acts gate add`

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
