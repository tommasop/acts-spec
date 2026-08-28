# [Project Name]

## Setup
- Install: `[install command]`
- Dev: `[dev command]`
- Test: `[test command]`

## Code Style
[Project style conventions]

## Testing
- Vitest for unit tests
- Playwright for E2E
- Read full: `.testing/conventions.md`

## PR Instructions
- Title format: `[format]`
- Run lint and test before committing

---

## ACTS Integration (v2)

This project uses ACTS v2 — a **git-native coordination protocol** for agent-aided development. Git is the system of record: a *stack* is a feature (a **feature branch** off `master`), a *change* is one unit of agent work (**a checkpoint on that branch**). Verification is the gate; context is served on demand.

### Rules
- Agent MUST load context before writing code: `acts context <change>`
- Agent MUST NOT submit a change for review until `acts verify <change>` passes
- Agent MUST record a session note + checkpoint before ending: `acts note` / `acts checkpoint`
- Agent MUST stay within the change's scope: `acts scope <change> <file>`
- Agent MUST get developer approval on the PR before `acts approve` / `acts stack land`
- Agent MUST run `acts validate` before finishing
- Agent SHOULD use cost-effective models for routine tasks

### ACTS Commands
- `acts stack create <id> [-t <title>]` — Start a new stack (feature branch + manifest)
- `acts stack status` — Show stack tree + change statuses
- `acts stack land` — Merge the whole feature branch once all changes are APPROVED
- `acts change add <id> -t <title> [--accept <criteria>]` — Add a change (checkpoint on the feature branch)
- `acts change status [<id>]` — Show change details
- `acts verify [<id>] [--all]` — Run quality gates; record evidence (**GATE for review**)
- `acts review <id>` — Submit/update the stack's ONE PR (feature vs base; requires verify to pass)
- `acts approve <id>` — Mark approved after human PR review
- `acts rework <id>` — Reopen for rework (clears approval)
- `acts context [<id>]` — Emit scoped context pack (durable task state)
- `acts note <id> -m <text>` — Append a session note
- `acts checkpoint <id> -s <summary>` — Record a status checkpoint
- `acts redirect <id> --accept <criteria>` — Update scope mid-flight without context loss
- `acts scope <id> <file>` — Check file ownership (derived from diffs)
- `acts validate` — Validate manifest + branch consistency

### Review Workflow
1. Implement on the stack's feature branch (change loaded via `acts context`); commits become the change's checkpoint range.
2. `acts verify <change>` runs quality gates; a change CANNOT be reviewed until verify passes.
3. `acts review <change>` submits/updates the stack's ONE PR (via `gh`), body = rationale + verification evidence + acceptance criteria.
4. Human reviews on GitHub PR UI → `acts approve <change>`.
5. `acts stack land` merges the whole feature branch once all changes are approved, then closes the PR.
6. Record `acts note` + `acts checkpoint`, then `acts validate`.

### Data Storage
- Coordination state: `.acts/stack.json` (git-committed manifest, diffable) — a change = a checkpoint (commit range `start_sha..end_sha`) on the stack's feature branch; one PR per stack
- Code truth: the stack's feature branch + its ONE PR (no sidecar database)
- Session notes: `.acts/changes/<id>/notes/*.md`

### Model Budgeting

#### Cost Tiers
| Tier | Model | Use For |
|------|-------|---------|
| **Cheap** | Claude Haiku / GPT-mini | Routine tasks, boilerplate, refactors |
| **Standard** | Claude Sonnet / GPT-4o | Default coding |
| **Expensive** | Claude Opus / GPT-4.5 | Complex architecture, tricky bugs, cross-repo changes |

#### Budget Rules
- Use the **cheapest** model that can reliably complete the task
- Escalate to a higher tier only after two failed attempts
- Every session records cost in its `acts note`
- If a change is estimated to cost > $10, split it into smaller changes

#### Decision Guide
| Task Type | Recommended Tier |
|-----------|------------------|
| Add a field to an existing schema | Cheap |
| New endpoint following existing patterns | Cheap |
| Feature with cross-cutting changes | Standard |
| Debugging flaky tests / race conditions | Standard |
| Cross-repo impact analysis | Expensive |
| Architecture/design work | Expensive |

### Architecture
[Reference to project architecture docs]

### Forbidden
- Never commit `.env` files
- Never use `eval()` or `Function()`
- Never store secrets in code
- Never bypass the verification gate (`acts verify` before `acts review`)
