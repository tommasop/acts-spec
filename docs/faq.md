# ACTS FAQ

## What is ACTS?

ACTS is a protocol that coordinates how developers use AI coding agents on shared codebases. It prevents drift, duplication, and context loss.

## What does ACTS actually do?

ACTS defines:

1. **State** — A git-native manifest (`.acts/stack.json`) tracking stacks and changes
2. **Verification** — `acts verify` runs quality gates and blocks review until they pass (the gate is evidence, not ceremony)
3. **Context** — Scoped context packs (`acts context`) that survive session boundaries
4. **Review** — Changes map to stacked PRs; review happens on GitHub/GitLab
5. **Ownership** — Which change owns which files, derived from git diffs

Your AI agent reads the manifest and follows the rules. Git is the source of truth — there is no sidecar database to drift or bypass.

## What is AGENTS.md?

[AGENTS.md](https://agents.md/) is an industry-standard file adopted by 60k+ open source projects. It provides context and instructions for AI coding agents.

ACTS uses AGENTS.md as its constitution file — a single file that serves both:
- **Project context** for any AI agent (setup, code style, testing)
- **ACTS rules** for multi-developer coordination

See the [AGENTS.md standard](https://agents.md/) for details.

## Do I need ACTS if I work alone?

**Yes, for two reasons:**

1. **Context persistence** — `acts context` / `acts note` / `acts checkpoint` remember what you did and why, even across sessions
2. **Verification gate** — agents can't claim "done" without quality-gate evidence

## Do I need ACTS if I already have agent rules (Cursor Rules, CLAUDE.md)?

**Yes, because ACTS is above that layer:**

- Cursor Rules tell your agent HOW to write code
- ACTS tells your agent WHAT to check before writing, WHEN to stop (verify), and HOW to hand off (PRs)
- ACTS uses AGENTS.md (the industry standard) while Cursor Rules use tool-specific formats

## Is this just for teams?

No. Freelancers and open source maintainers benefit from:

- Context persistence (session notes + context packs)
- Quality gates (verification before review)
- Stacked PRs (small, reviewable slices of agent work)

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
# Build from source (requires Zig 0.13.0)
cd acts-core
zig build release
sudo cp zig-out/bin/acts /usr/local/bin/acts

# Or copy project-locally
cp acts-core/zig-out/bin/acts .acts/bin/acts
```

## How do I visualize what a change does to the architecture?

Use archify via ACTS:

```bash
acts archify install                    # one-time: installs the renderer (needs node/npx)
acts diagram c1 --delta                 # Before/Delta/After architecture HTML
acts diagram c1 --delta --attach        # also comment it on the change's PR
```

`acts review` attaches the delta automatically when the renderer is installed. Without it, `acts diagram` prints a textual delta summary (component | status | kind).

## What's the minimum to try ACTS?

Two commands:

```bash
acts stack create demo -t "My First Stack"
acts change add c1 -t "First change" --accept "works"
```

Then work on the change branch, `acts verify c1`, `acts review c1`.

See [Minimal Viable ACTS](minimal-viable-acts.md).

## Is this a framework I need to install?

You install a single binary (`acts`). Everything else lives in your repo:
- `.acts/stack.json` — coordination manifest
- `.acts/changes/<id>/notes/` — session notes
- `AGENTS.md` — Project constitution

## How does ACTS compare to Cursor Rules / CLAUDE.md?

| | Cursor Rules | ACTS |
|---|---|---|
| Scope | One tool | Any tool |
| Purpose | How to write code | How to coordinate work |
| State | None | `.acts/stack.json` manifest |
| Human oversight | None | PR review + verification gate |
| Multi-developer | Not addressed | First-class handoffs |
| Industry standard | No (tool-specific) | Yes (AGENTS.md) |

## Can I use ACTS without git?

No. ACTS is git-native. State lives in git branches and a manifest committed to the base branch.

## What happens if my agent doesn't follow ACTS?

`acts verify` blocks `acts review` until quality gates pass, so an agent can't submit unreviewed work. Session notes record what actually happened, so you can identify compliance gaps.

## How much does ACTS cost?

ACTS itself is free (MIT License).
Your AI agent tool may have costs.

## What are stacks and changes?

- A **stack** is a feature: a base branch off `main` plus an ordered list of changes.
- A **change** is one unit of agent work: a stacked branch + a PR.

The stack is like a PR stack (Graphite/git-spice style) — each change is a small, reviewable slice that CI and humans can verify independently.

## How does verification work?

`acts verify` auto-detects your project's quality gates (npm/cargo/go/make/pytest/mix) or reads them from `.acts/acts.json`:

```json
{ "quality_gate": { "test": "npm test", "lint": "npm run lint", "typecheck": null, "build": "npm run build" } }
```

Results are recorded in the manifest. **`acts review` refuses to submit until verification passes.**

## What's the difference between v1 and v2?

v1 used a SQLite database with stories, tasks, and gates enforced by SQL triggers. v2 is **git-native**: stacks and changes are just branches and PRs; the manifest is a diffable file; verification is the gate. See [MIGRATION.md](MIGRATION.md).

## How do I migrate from v1?

```bash
# Requires the sqlite3 CLI
acts migrate LEGACY-42
```

Imports a v1 story into a v2 stack, mapping tasks→changes and preserving file ownership as notes. See [MIGRATION.md](MIGRATION.md).

## Where is the data stored?

| Data | Location | Format |
|------|----------|--------|
| Stack/change coordination state | `.acts/stack.json` | JSON manifest (git-committed) |
| Code truth | git branches / PRs | Git |
| Session notes | `.acts/changes/<id>/notes/*.md` | Markdown |
| Cross-repo knowledge graph | `.acts/cbm/` | Gitignored |
