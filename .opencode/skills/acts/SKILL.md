---
name: acts
description: "Use ACTS v2 (Git-native coordination protocol) whenever this project uses ACTS for agent-aided development — manage branch stacks, changes, verification gates, PR review, and durable context. Required before writing code in ACTS projects."
license: MIT
compatibility: opencode
metadata:
  project: acts
---

# ACTS v2 — Git-Native Coordination Protocol

ACTS coordinates human + agent development on a shared repo. **Git is the system of record.** A *stack* is a feature (a base branch); a *change* is one unit of agent work (a stacked branch + PR). Verification is the gate. Context is served on demand.

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
| `acts stack create <id> [-t <title>]` | Start a new stack (base branch + manifest). |
| `acts stack status [--json]` | Show stack tree + change statuses. |
| `acts stack land` | Merge APPROVED changes bottom-up. |
| `acts change add <id> -t <title> [--accept <criteria>]` | Add a change on top of the stack. |
| `acts change status [<id>]` | Show change details. |
| `acts verify [<id>] [--all]` | Run quality gates; record evidence. **Gate for review.** |
| `acts review <id>` | Submit stacked PR (requires verify to pass). |
| `acts approve <id>` | Mark approved after human PR review. |
| `acts rework <id>` | Reopen for rework (clears approval). |
| `acts context [<id>]` | Emit scoped context pack (durable task state). |
| `acts note <id> -m <text>` | Append a session note. |
| `acts checkpoint <id> -s <summary>` | Record a status checkpoint. |
| `acts redirect <id> --accept <criteria>` | Update scope mid-flight without context loss. |
| `acts scope <id> <file>` | Check file ownership (derived from diffs). |
| `acts validate` | Validate manifest + branch consistency. |

## Workflow

1. **Plan** — use spec-kit / superpowers for spec, plan, task breakdown (outside ACTS).
2. **Start a stack**: `acts stack create <id> -t "<title>"`.
3. **Add a change**: `acts change add <id> -t "<title>" --accept "<criteria>"`. This checks out the new branch.
4. **Load context**: `acts context <id>` — read acceptance criteria, parent chain, verification status, notes, and changed files.
5. **Implement** — write code, staying within scope. Check `acts scope <id> <file>` before touching files outside the diff.
6. **Verify**: `acts verify <id>`. Fix failures. **Do NOT review until verify passes.**
7. **Commit** — commit your work with a descriptive message.
8. **Review**: `acts review <id>` — submits a stacked PR via `gh` (requires verify to pass). Push branch if no `gh`.
9. **Iterate** on PR comments, re-verify, `acts rework` then re-review as needed.
10. **Approve & land**: after the human approves the PR, `acts approve <id>`, then `acts stack land` merges bottom-up.
11. **Close out**: `acts note` + `acts checkpoint` session summary, then `acts validate`.

## Context continuity

When you start a session on an existing change, **always** run `acts context <id>` first. It surfaces:
- Acceptance criteria (the contract you must satisfy)
- Parent chain (what landed/coming before this change)
- Verification status (what's already proven)
- Checkpoint (where the previous session stopped)
- Session notes (previous session summaries)
- Changed files + commit history (blast radius)

If the human redirects scope, use `acts redirect <id> --accept "<new criteria>"` — this updates the contract in-place so you never lose the accumulated context by restarting.
