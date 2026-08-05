# Minimal Viable ACTS

The absolute minimum to try ACTS v2. One binary, two commands.

---

## Prerequisites

Install the `acts` binary:

```bash
cd acts-core
zig build release
sudo cp zig-out/bin/acts /usr/local/bin/acts
```

Or copy project-locally:

```bash
mkdir -p .acts/bin
cp acts-core/zig-out/bin/acts .acts/bin/acts
```

---

## The 1 File You Need

### AGENTS.md (Project Context + ACTS Rules)

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

## ACTS Integration (v2)

This project uses ACTS v2 — a git-native coordination protocol for agent-aided development.

### Rules
- Agent MUST load context before writing code: `acts context <change>`
- Agent MUST NOT submit a change for review until `acts verify <change>` passes
- Agent MUST record a session note + checkpoint before ending: `acts note` / `acts checkpoint`
- Agent MUST stay within the change's scope: `acts scope <change> <file>`
- Agent MUST get developer approval on the PR before `acts approve` / `acts stack land`
- Agent MUST run `acts validate` before finishing

### ACTS Commands
- `acts stack create <id> [-t <title>]` — Start a new stack (base branch + manifest)
- `acts stack status` — Show stack tree + change statuses
- `acts stack land` — Merge APPROVED changes bottom-up
- `acts change add <id> -t <title> [--accept <criteria>]` — Add a change on top of the stack
- `acts change status [<id>]` — Show change details
- `acts verify [<id>] [--all]` — Run quality gates; record evidence (GATE for review)
- `acts review <id>` — Submit stacked PR (requires verify to pass)
- `acts approve <id>` — Mark approved after human PR review
- `acts rework <id>` — Reopen for rework (clears approval)
- `acts context [<id>]` — Emit scoped context pack (durable task state)
- `acts note <id> -m <text>` — Append a session note
- `acts checkpoint <id> -s <summary>` — Record a status checkpoint
- `acts redirect <id> --accept <criteria>` — Update scope mid-flight
- `acts scope <id> <file>` — Check file ownership (derived from diffs)
- `acts validate` — Validate manifest + branch consistency

Status Values: TODO, IN_PROGRESS, VERIFIED, IN_REVIEW, APPROVED, MERGED

### Architecture
[Your project architecture]

### Forbidden
[What your agent must never do]
```

---

## How to Test

1. Create `AGENTS.md` at repo root
2. Start a stack:
   ```bash
   acts stack create demo -t "Demo"
   acts change add c1 -t "First change" --accept "works"
   ```
3. Tell your AI agent:

   ```
   Read AGENTS.md. Run `acts context` before writing any code.
   After writing code, run `acts verify`, then `acts review`.
   ```

4. See if the agent follows the rules

---

## What You Can Skip Initially

- ❌ Stacked PRs (run `acts review` later; `acts verify` works locally)
- ❌ OpenCode plugin (the CLI is enough)
- ❌ Cross-repo memory (`cbm` plugin — add when you have multiple repos)

---

## Adding Features Gradually

Once basics work, add:

1. **Stacked PRs** — `acts review c1` (needs `gh` or git-spice)
2. **Context continuity** — `acts note`, `acts checkpoint`, `acts redirect`
3. **Cross-repo memory** — the `cbm` OpenCode plugin + `references`
4. **Custom quality gates** — configure `.acts/acts.json`

---

## What ACTS Actually Does

**Without ACTS:**
- Agent writes code without checking what's been done
- No record of what happened between sessions
- No way to know what AI did vs what you did
- No verification before review

**With ACTS:**
- Agent loads context before coding (`acts context`)
- `acts verify` records quality-gate evidence; review is blocked until green
- Session notes + checkpoints survive session boundaries
- File ownership is derived from git diffs (`acts scope`)

---

## Next Steps

Once you've tested with 1 file:

1. Read the full [README](../README.md)
2. Read the [Integration Guide](INTEGRATION.md) for your editor
3. Read the [FAQ](faq.md)
4. Use [templates](./templates/) for AGENTS.md
