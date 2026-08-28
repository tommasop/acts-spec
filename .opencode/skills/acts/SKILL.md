---
name: acts
description: "Use ACTS v2 (Git-native coordination protocol) whenever this project uses ACTS for agent-aided development — manage branch stacks, changes, verification gates, PR review, and durable context. Required before writing code in ACTS projects."
license: MIT
compatibility: opencode
metadata:
  project: acts
---

# ACTS v2 — Git-Native Coordination Protocol

ACTS coordinates human + agent development on a shared repo. **Git is the system of record.** A *stack* is a feature (a feature branch off `master`); a *change* is one unit of agent work (a checkpoint on that branch). Verification is the gate. Context is served on demand.

## Rules

- Agent MUST run `acts context` (or `acts state`) before writing code on a change.
- Agent MUST NOT submit a change for review (`acts review`) until `acts verify` passes.
- Agent MUST record a session note (`acts note`) and checkpoint (`acts checkpoint`) before ending a session.
- Agent MUST stay within the change's scope; use `acts scope` to check file ownership.
- Agent MUST get developer approval on the PR before `acts approve` / `acts stack land`.
- Agent MUST run `acts validate` before finishing.

## Commands

| Command | Purpose |
|---------|---------|
| `acts stack create <id> [-t <title>]` | Start a new stack (feature branch + manifest). |
| `acts stack status [--json]` | Show stack tree + change statuses. |
| `acts stack land` | Merge the whole feature branch once all changes are APPROVED. |
| `acts change add <id> -t <title> [--accept <criteria>]` | Add a change (checkpoint on the feature branch). |
| `acts change status [<id>]` | Show change details. |
| `acts verify [<id>] [--all]` | Run quality gates; record evidence. **Gate for review.** |
| `acts review <id>` | Submit/update the stack's ONE PR (feature vs base; requires verify to pass). |
| `acts approve <id>` | Mark approved after human PR review. |
| `acts rework <id>` | Reopen for rework (clears approval). |
| `acts context [<id>]` | Emit scoped context pack (durable task state). |
| `acts note <id> -m <text>` | Append a session note. |
| `acts checkpoint <id> -s <summary>` | Record a status checkpoint. |
| `acts redirect <id> --accept <criteria>` | Update scope mid-flight without context loss. |
| `acts scope <id> <file>` | Check file ownership (derived from diffs). |
| `acts diagram <id> [--delta] [--attach]` | Render the change's architecture impact via archify (HTML). `--delta` = Before/Delta/After; `--attach` = comment on the change's PR. |
| `acts archify install` | Install the archify diagram renderer skill (`npx skills add tt-a1i/archify`). |
| `acts ponytail install` | Install the ponytail minimality skill (rules + commands + plugin; `acts review` then appends its checklist to the PR). |
| `acts migrate [<story-id>]` | Import a v1 SQLite story into a v2 stack. |
| `acts validate` | Validate manifest + branch consistency. |

## Workflow

1. **Plan** — use spec-kit / superpowers for spec, plan, task breakdown (outside ACTS).
   - If a **Zeplin design link** is given, extract the API contract first: `acts_zeplin <url>` (or `node acts-zeplin-contract.mjs --flow <url>` / `--scenario <url>`). Feed the inferred endpoints + fields into acceptance criteria and use the flow path to sequence changes.
2. **Start a stack**: `acts stack create <id> -t "<title>"`. This creates the feature branch `acts/<id>/feature` off `master`.
3. **Add a change**: `acts change add <id> -t "<title>" --accept "<criteria>"`. This records a checkpoint on the feature branch (no branch switch).
4. **Load context**: `acts context <id>` — read acceptance criteria, preceding changes, verification status, notes, and changed files.
5. **Implement** — write code, staying within scope. Check `acts scope <id> <file>` before touching files outside the diff.
6. **Verify**: `acts verify <id>`. Fix failures. **Do NOT review until verify passes.**
7. **Commit** — commit your work with a descriptive message; your commits become the change's checkpoint range.
8. **Review**: `acts review <id>` — submits/updates the stack's ONE PR (feature vs base) via `gh` (requires verify to pass). Push the feature branch if no `gh`.
9. **Iterate** on PR comments, re-verify, `acts rework` then re-review as needed.
10. **Approve & land**: after the human approves the PR, `acts approve <id>`, then `acts stack land` merges the whole feature branch once all changes are approved and closes the PR.
11. **Close out**: `acts note` + `acts checkpoint` session summary, then `acts validate`.

## Context continuity

When you start a session on an existing change, **always** run `acts context <id>` first. It surfaces:
- Acceptance criteria (the contract you must satisfy)
- Preceding changes (what landed/coming before this checkpoint)
- Verification status (what's already proven)
- Checkpoint (where the previous session stopped)
- Session notes (previous session summaries)
- Changed files + commit history (blast radius)

If the human redirects scope, use `acts redirect <id> --accept "<new criteria>"` — this updates the contract in-place so you never lose the accumulated context by restarting.

## Diagrams (archify)

Visualize what a change does to the architecture before review:

- `acts diagram <id>` — render an architecture impact map (HTML) of the components the change touches.
- `acts diagram <id> --delta` — Before/Delta/After comparison (master vs feature branch).
- `acts diagram <id> --attach` — post the delta as a comment on the change's PR (also done automatically by `acts review` when the renderer is installed).
- `acts archify install` (or `acts setup --with-archify`) — install the renderer. Without it, `acts diagram` degrades to a textual delta summary.
- For iterative authoring, the `acts_archify` plugin tool validates/delivers a candidate IR JSON (`validate` → fix per diagnostics → `deliver`).

## Minimality (ponytail)

Keep each change the smallest thing that works — complementary to ACTS checkpoint scoping:

- `acts ponytail install` (or `acts setup --with-ponytail`) installs the ponytail rules, `/ponytail*` slash commands, and frontmatter plugin.
- With ponytail installed, `acts review` appends a **minimality checklist** (YAGNI, reuse, shortest diff, no new deps, one runnable check) with per-change diff stats to the stack's PR.
- Use `/ponytail-review` during review to audit a change's diff for over-engineering.
