# Minimal Viable ACTS

The absolute minimum to try ACTS. One binary, one command.

---

## Prerequisites

Install the `acts` binary:

```bash
# Linux x86_64
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-linux-x86_64.tar.gz | tar xz
sudo mv acts-linux-x86_64 /usr/local/bin/acts

# macOS Apple Silicon
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-macos-aarch64.tar.gz | tar xz
sudo mv acts-macos-aarch64 /usr/local/bin/acts
```

Or build from source (requires [Zig 0.13.0](https://ziglang.org/download/)):

```bash
cd acts-core
zig build release
sudo cp zig-out/bin/acts /usr/local/bin/
```

---

## The 2 Files You Need

### 1. AGENTS.md (Project Context + ACTS Rules)

Create at repo root:

```markdown
# [Your Project Name]

## Setup
- Install: `[your install command]`
- Dev: `[your dev command]`
- Test: `[your test command]`

## Code Style
[Your style conventions]

## Testing
[Your testing conventions]

## PR Instructions
- Title format: `[format]`
- Run lint and test before committing

---

## ACTS Integration

This project uses ACTS (Agent Collaborative Tracking Standard) for multi-developer coordination.

### Rules
- Agent MUST read state before writing code: `acts state read`
- Agent MUST NOT modify files owned by completed tasks: `acts scope check --task <id> --file <path>`
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion

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

### Architecture
[Your project architecture]

### Forbidden
[What your agent must never do]
```

### 2. Initialize ACTS

```bash
acts init TEST-1 --title "My First ACTS Story"
```

This creates:
- `.acts/acts.db` — SQLite database with schema and triggers
- `.story/plan.md` — Plan template
- `.story/spec.md` — Spec template
- `.story/sessions/` — Session directory

---

## How to Test

1. Create `AGENTS.md` at repo root
2. Run `acts init TEST-1 --title "My First ACTS Story"`
3. Tell your AI agent:

```
Read AGENTS.md. Before writing any code, run `acts state read`.
After writing code, record a session summary.
```

4. See if the agent follows the rules

---

## What You Can Skip Initially

- ❌ Review providers (skip for basic conformance)
- ❌ Templates (write your own AGENTS.md)
- ❌ Validation scripts (run `acts validate` later)

---

## Adding Features Gradually

Once basics work, add:

1. **Session validation** — `acts session validate file.md`
2. **Scope checking** — `acts scope check --task <id> --file <path>`
3. **Decisions tracking** — `acts decision add` (JSON from stdin)
4. **Strict mode** — Enable `conformance_level: "strict"` in `.acts/acts.json` for extra gates

---

## What ACTS Actually Does

**Without ACTS:**
- Agent writes code without checking what's been done
- No record of what happened between sessions
- No way to know what AI did vs what you did
- No enforcement of review before completion

**With ACTS:**
- Agent reads state before coding (via `acts state read`)
- SQLite triggers enforce gates (cannot bypass)
- Session summaries capture decisions and context
- File ownership prevents unauthorized modifications

---

## Next Steps

Once you've tested with 2 files:

1. Read the full [README](../README.md)
2. Read the [Integration Guide](INTEGRATION.md) for your editor
3. Install [superpowers](https://github.com/obra/superpowers) for agent workflow skills (TDD, planning, code review)
4. Use [templates](./templates/) for team coordination
