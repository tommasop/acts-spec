# ACTS FAQ

## What is ACTS?

ACTS is a protocol that coordinates how developers use AI coding agents on shared codebases. It prevents drift, duplication, and context loss.

## What does ACTS actually do?

ACTS defines:

1. **State** — A SQLite database (`.acts/acts.db`) tracking stories, tasks, and gates
2. **Gates** — Points where humans must approve before proceeding (enforced at database level)
3. **Sessions** — Records of what happened each time someone worked
4. **Ownership** — Which completed tasks own which files

Your AI agent reads state and follows the rules. SQLite triggers enforce gates.

## What is AGENTS.md?

[AGENTS.md](https://agents.md/) is an industry-standard file adopted by 60k+ open source projects. It provides context and instructions for AI coding agents.

ACTS uses AGENTS.md as its constitution file — a single file that serves both:
- **Project context** for any AI agent (setup, code style, testing)
- **ACTS rules** for multi-developer coordination

See the [AGENTS.md standard](https://agents.md/) for details.

## Do I need ACTS if I work alone?

**Yes, for two reasons:**

1. **Session summaries** — Remember what you did and why, even months later
2. **Gate enforcement** — SQLite triggers prevent accidental state transitions

## Do I need ACTS if I already have agent rules (Cursor Rules, CLAUDE.md)?

**Yes, because ACTS is above that layer:**

- Cursor Rules tell your agent HOW to write code
- ACTS tells your agent WHAT to check before writing, WHEN to stop, and HOW to hand off to others
- ACTS uses AGENTS.md (the industry standard) while Cursor Rules use tool-specific formats

## Is this just for teams?

No. Freelancers and open source maintainers benefit from:

- Context persistence (session summaries)
- Cost tracking (agent attribution)
- Quality assurance (gate enforcement)

## What AI tools does ACTS work with?

Any tool that can run CLI commands:

- Cursor
- Claude Code
- OpenCode (with plugin)
- Copilot
- Gemini CLI
- Codex
- Aider
- Windsurf
- Devin
- Any custom agent

## How do I install ACTS?

```bash
# Download pre-built binary
curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-linux-x86_64.tar.gz | tar xz
sudo mv acts-linux-x86_64 /usr/local/bin/acts

# Or build from source
cd acts-core && zig build release
```

## What's the minimum to try ACTS?

3 things: the binary, `AGENTS.md`, and `acts init`:

```bash
acts init TEST-1 --title "My First ACTS Story"
# Creates:
#   .acts/acts.db      (SQLite database)
#   .story/plan.md     (plan template)
#   .story/spec.md     (spec template)
#   .story/sessions/   (session directory)
```

See [Minimal Viable ACTS](minimal-viable-acts.md).

## Is this a framework I need to install?

You install a single binary (`acts`). Everything else lives in your repo:
- `.acts/acts.db` — SQLite state
- `.story/` — Markdown narratives
- `AGENTS.md` — Project constitution

## How does ACTS compare to Cursor Rules / CLAUDE.md?

| | Cursor Rules | ACTS |
|---|---|---|
| Scope | One tool | Any tool |
| Purpose | How to write code | How to coordinate work |
| State | None | SQLite database |
| Human oversight | None | Gates at key decisions |
| Multi-developer | Not addressed | First-class handoffs |
| Industry standard | No (tool-specific) | Yes (AGENTS.md) |

## Can I use ACTS without git?

No. ACTS is git-native. All state lives in the repository.

## What happens if my agent doesn't follow ACTS?

The agent will report non-compliance in the session summary's "Agent Compliance" section. This enables you to identify patterns and adjust agent configuration.

SQLite triggers also prevent invalid state transitions even if the agent tries to bypass the binary.

## How much does ACTS cost?

ACTS itself is free (MIT License).
Your AI agent tool may have costs.
ACTS tracks token usage in session summaries so you can see what you're spending.

## What is strict mode?

ACTS Strict adds extra gate types:

1. **commit-review** — Agent groups commits into batches and gets approval before continuing.
2. **architecture-discuss** — Before making significant design decisions, agent presents reasoning and gets approval.

Enable in `.acts/acts.json`:
```json
{
  "conformance_level": "strict"
}
```

## Do I need superpowers?

No. ACTS works without superpowers. But superpowers improves the quality of individual agent sessions with TDD, systematic planning, subagent-driven development, and code review workflows.

ACTS handles multi-developer coordination (state, handoffs, file ownership).
Superpowers handles single-developer agent quality (TDD, planning, code review, debugging).

Install at: https://github.com/obra/superpowers

## How do gates work?

Gates are enforced by SQLite triggers in `.acts/acts.db`:

```sql
-- Cannot start task without preflight gate
CREATE TRIGGER enforce_preflight_gate
BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'IN_PROGRESS' AND OLD.status = 'TODO'
BEGIN
  SELECT CASE WHEN (
    SELECT COUNT(*) FROM gate_checkpoints
    WHERE task_id = NEW.id AND gate_type = 'approve' AND status = 'approved'
  ) = 0
  THEN RAISE(ABORT, 'Cannot start task: preflight gate not approved')
  END;
END;
```

This means an agent **cannot** bypass gates by editing files directly. The database enforces the rules.

## Can I migrate from the old JSON-based ACTS?

Yes. The binary can ingest old `.story/state.json`:

```bash
cat .story/state.json | acts state write --story <story-id>
```

Then remove `.story/state.json` — SQLite is now the source of truth.

## Where is the data stored?

| Data | Location | Format |
|------|----------|--------|
| Story state, tasks, gates | `.acts/acts.db` | SQLite |
| Decisions, approaches, questions | `.acts/acts.db` | SQLite |
| Plan, spec | `.story/plan.md`, `.story/spec.md` | Markdown |
| Session summaries | `.story/sessions/*.md` | Markdown |
| Task notes | `.story/tasks/<id>/notes.md` | Markdown |
