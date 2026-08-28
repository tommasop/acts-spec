# Design: Single-Branch Stacks (checkpoints + one PR)

**Date:** 2026-08-28
**Status:** Approved (design)
**Change:** `c1` (stack `single-branch`)

## Problem

The ACTS v2 stacked-branch model is confusing to follow. Each change is a branch
created off the previous change's branch, so:

- The branch topology is nested (`c2` contains `c1`'s commits; a chain, not a line).
- With the `gh` fallback, per-change PRs target the stack base and show **overlapping diffs**.
- With git-spice, PRs are interdependent and merge-order matters (bottom-up).
- `acts stack land` merges into the base branch but **leaves PRs open** on GitHub.

The mental model (stack → base branch, change → nested branch, parent chains)
is the source of the confusion, not the tooling around it.

## Goal

Make ACTS follow the simplest possible model:

- A **stack** is one feature = one branch off `master`.
- A **change** is a checkpoint on that branch: a commit range `[start_sha, end_sha]`.
- Review is **one PR** (feature branch → `master`), updated as checkpoints accumulate.
- `acts stack land` merges the whole branch into `master` with a single
  `--no-ff` merge once **all** changes are approved, then **closes the PR**.

## Mental model

```
master ────────────────────────────►   (one merge when the feature lands)
         \                         /
          acts/<id>/feature ──────►
            c1    c2    c3            checkpoints = commits on the feature branch
```

There are no branch-off-branch relationships anywhere. `parent` chains disappear.

## Data model (`.acts/stack.json`, v3)

```json
{
  "version": 3,
  "id": "auth",
  "title": "Add auth",
  "branch": "acts/auth/feature",
  "pr": { "url": "https://github.com/org/repo/pull/12" },
  "changes": [
    {
      "id": "c1",
      "title": "JWT middleware",
      "status": "VERIFIED",
      "start_sha": "abc123…",
      "end_sha": "def456…",
      "acceptance": ["token validated on /api/*"],
      "verify": { "test": { "cmd": "npm test", "ok": true, "exit_code": 0, "duration_ms": 107 } },
      "notes": [".acts/changes/c1/notes/1785920187.md"],
      "checkpoint": "done: middleware core",
      "approvals": []
    }
  ]
}
```

Changes from v2:

- Root `base_branch` → `branch` (the feature branch). Kept key names stay stable.
- Stack-level `pr` (one PR for the whole stack) replaces per-change `pr`.
- Change entries **drop** `branch` and `parent` (implicit order = array order).
- Change entries **gain** `start_sha` (checkpoint at add time) and `end_sha`
  (frozen at verify/land time; null while open).

### Backward compatibility

Old v2 manifests (per-change `branch` + `parent` + `pr`) still **parse and
validate** — reading tolerates the legacy fields, and legacy fields are ignored
for new operations. Only new stacks are written as v3.

## Command behavior

| Command | Current (v2) | New (v3) |
|---|---|---|
| `stack create <id>` | Base branch `acts/<id>/base` off `master` | Feature branch `acts/<id>/feature` off `master` |
| `change add <id>` | New nested branch off top of stack; switches to it | **No new branch**; records `start_sha = HEAD`; stays on the feature branch |
| `verify <id>` | Gates on repo; records evidence | Same, plus freezes `end_sha = HEAD` on success |
| `review` | Per-change stacked PR (`gh`/`gs`) | **One PR** feature→master; **creates or updates** it (`gh pr create` / `gh pr edit`); body = all changes + evidence + risk tiers + archify delta (master→feature) |
| `approve <id>` | Per-change approval | Unchanged (per-change approval) |
| `stack land` | Merges APPROVED changes bottom-up into base | **Refuse unless all changes APPROVED**; one `git merge --no-ff` feature→master; close PR; mark all changes MERGED |
| `stack status` | Tree with parent chains | **Linear list**: status, title, SHA range, PR url |
| `change status <id>` | Branch + parent | start/end SHA + diff stat |
| `scope <id> <file>` | File in change branch's diff | File in `start_sha..end_sha` (or `..HEAD` while open) |
| `diagram <id> --delta` | base vs change branch | Per-change range `start_sha..end_sha`; whole-stack delta = `master`→`acts/<id>/feature` |
| `migrate` | v1 SQLite → v2 stack | v1 SQLite → v3 stack (same mapping, v3 output) |

## Interactions with existing features

- **Verification gate**: unchanged mechanics; `end_sha` freezes the change's scope
  when gates pass. The stale-verify guard now compares `master`'s SHA (instead of
  the old base branch).
- **Risk-based HITL**: unchanged; risk computed from the change's commit-range
  diff (`start_sha..end_sha`).
- **Context continuity** (`context`/`note`/`checkpoint`/`redirect`): unchanged.
- **archify diagrams**: maps cleanly to the one-PR model — Before = `master`,
  After = feature branch; per-change deltas use the change's commit range.
- **ACTS session rule "stay within the change's scope"**: scope is now derived
  from the change's commit range instead of its (nested) branch diff.

## Edge cases and error handling

- `change add` with no prior stack → existing `NoStack` guard.
- `review` with no verified change → refuse (`VerifyRequired` semantics retained).
- `review` when a stack PR already exists → update it, never create a duplicate.
- `stack land` with unapproved changes → refuse and list the unapproved changes.
- `master` moved since a change was verified → stale-verify guard requires re-verify.
- Overlapping ranges (c1 verified while c2 open) → allowed; ranges are ordered by
  manifest array order.
- Legacy v2 manifest present → validates; new operations write v3 on the next
  `change add`/`verify`.

## Testing

- **Zig unit tests** (`zig build test`):
  - v3 manifest round-trip; `start_sha`/`end_sha` tracking.
  - `stack land` refuses when not all changes APPROVED.
  - `review` updates an existing PR instead of creating a duplicate.
  - Legacy v2 manifest still validates.
  - Scope from `start_sha..end_sha`.
- **Plugin tests** (`npm test`): context pack shape unchanged; linear stack status.
- **Manual**: create stack → add 3 changes → work/verify → review → one PR → land
  → PR closed; archify delta attached.

## Docs to update

- `README.md` (stack/change model, command reference, version history).
- `docs/INTEGRATION.md`, `docs/faq.md`, `docs/MIGRATION.md`,
  `docs/minimal-viable-acts.md`, `docs/example-*.md`.
- `.opencode/skills/acts/SKILL.md`, AGENTS.md sections, `setup.zig` `agents_section`.

## Out of scope

- git-spice support (obsolete under one-PR-per-stack; `gs` detection can remain but
  review always uses `gh`).
- Deleting/renaming old v2 branches on disk (history is preserved by git).