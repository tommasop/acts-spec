# ACTS v2.0.0

**Agent Collaborative Tracking Standard** — A git-native coordination protocol for agent-aided development. Git is the system of record: a *stack* is a feature (base branch); a *change* is one unit of agent work (a stacked branch + PR). Verification is the gate; context is served on demand.

[![CI](https://github.com/tommasop/acts-spec/actions/workflows/ci.yml/badge.svg)](https://github.com/tommasop/acts-spec/actions/workflows/ci.yml)
[![Release](https://github.com/tommasop/acts-spec/actions/workflows/release.yml/badge.svg)](https://github.com/tommasop/acts-spec/releases)

## What is ACTS?

ACTS is a protocol for coordinating AI-assisted software development across multiple sessions, developers, and tools. It prevents context loss, enforces verification before review, tracks file ownership, and keeps a durable record of decisions.

**Key features:**

- **Git-native state** — A *stack* is a feature (a base branch off `main`); a *change* is one unit of agent work (a stacked branch + PR). Progress is the git ref state itself — there is no sidecar database to drift or bypass.
- **Manifest**: `.acts/stack.json` — the durable coordination board. Human-readable, diffable, committed to the base branch.
- **Verification is the gate** — `acts verify` runs quality gates (test/lint/typecheck/build), records evidence, and **blocks review until it passes**. No manual preflight ceremony.
- **Risk-based human-in-the-loop** — `acts risk` classifies each change (LOW/MEDIUM/HIGH/CRITICAL) from diff size + cross-repo blast radius. LOW-risk verified changes **auto-approve and auto-land**; HIGH/CRITICAL require mandatory human review with an escalation checklist. Every approval/rework is audited in the manifest.
- **PR-native review** — `acts review` pushes the branch and submits a stacked PR via `gh` (or git-spice `gs`), with the body = agent rationale + verification evidence + acceptance criteria + risk tier.
- **Durable context** — `acts context` emits a scoped context pack (acceptance criteria, parent chain, verification status, notes, changed files); the OpenCode plugin **auto-injects** the active change's pack at session start, with optional CBM blast-radius.
- **Ownership derived from git** — `acts scope` checks whether a file belongs to a change's diff; no manual ownership tables.
- **v1 → v2 migration** — `acts migrate` imports an existing v1 SQLite story into a v2 stack.
- **Cross-repo orchestration** — the `cbm` OpenCode plugin wraps [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp): the 258MB binary is installed **once per machine** (`~/.cache/codebase-memory-mcp/bin`), the fleet shares **one knowledge graph**, and `cbm_bootstrap` idempotently rebuilds it on CI/fresh machines. Native tools (`trace_path`, `query_graph`, …) and `acts_memory scope` trace calls and map impact across repos (`CROSS_*` edges)
- **Standalone binary** — single Zig executable, no runtime dependencies (except libc)
- **Cross-platform** — Linux (x86_64, aarch64), macOS (x86_64, aarch64)

## Installation

### Build from Source

Requires [Zig 0.13.0](https://ziglang.org/download/):

```bash
cd acts-core
zig build release -Dversion=2.0.0
# Binary: zig-out/bin/acts
```

### Project Setup

```bash
# Option 1: Local copy (recommended for a single project)
cp acts-core/zig-out/bin/acts .acts/bin/acts

# Option 2: Install globally
sudo cp acts-core/zig-out/bin/acts /usr/local/bin/
```

> Pre-built binaries for Linux/macOS are published to [GitHub Releases](https://github.com/tommasop/acts-spec/releases) once tagged.

## Quick Start

### Start a Stack (a feature)

```bash
# 1. Start a stack — creates the base branch + manifest
acts stack create auth -t "Add user authentication"
# → stack auth created on branch acts/auth/base

# 2. Add a change (one unit of agent work) on top of the stack
acts change add c1 -t "JWT middleware" --accept "token validated on /api/*
unit tests"
# → change c1 added on branch acts/auth/c1-jwt-middleware
```

### Work a Change

```bash
# Load the durable context pack (acceptance criteria, notes, files, verification)
acts context c1

# ... agent writes code on the change branch ...

# Run quality gates — records evidence; gates review
acts verify c1
#   test: PASS (npm test) [107ms]
#   lint: PASS (npm run lint) [99ms]
#   build: PASS (npm run build) [135ms]
```

### Review (stacked PR)

```bash
# Submit a stacked PR (verify must pass; pushes branch, then gh/gs)
acts review c1
# → PR submitted: https://github.com/you/repo/pull/12

# Human reviews on GitHub → approve
acts approve c1

# Merge approved changes bottom-up
acts stack land
```

### Track Status

```bash
acts stack status
# Stack: auth — Add user authentication (base: acts/auth/base)
#   └ VERIFIED  JWT middleware

acts change status c1
# Change: c1 — JWT middleware
#   status: VERIFIED
#   branch: acts/auth/c1-jwt-middleware
#   verified: yes
```

### Context Continuity

```bash
acts note c1 -m "Implemented middleware; needs token caching"
acts note c1 -m "reviewed" --cost 4.25          # record per-change cost
acts checkpoint c1 -s "done: middleware core; blocked: caching; next: tests"
acts redirect c1 --accept "token cached\nrefresh supported"
```

In OpenCode, the active change's context pack (plus optional CBM blast radius) is **auto-injected** at session start — `acts_context` with `blast_radius: true` appends cross-repo callers/callees for the change's files.

## Command Reference

### Stack Lifecycle

| Command | Description |
|---------|-------------|
| `stack create <id> [-t <title>]` | Start a new stack (base branch + manifest) |
| `stack status [--json]` | Show stack tree + change statuses |
| `stack land` | Merge APPROVED changes bottom-up |

### Change Lifecycle

| Command | Description |
|---------|-------------|
| `change add <id> -t <title> [--accept <criteria>]` | Add a change (branch) on top of the stack |
| `change status [<id>]` | Show change details |
| `verify [<id>] [--all]` | Run quality gates; record evidence (**gate for review**) |
| `review <id>` | Submit stacked PR (requires verify to pass); auto-lands LOW-risk |
| `approve <id>` | Mark approved after human PR review |
| `rework <id>` | Reopen for rework (clears approval) |
| `risk <id>` | Compute + show the change's risk tier (LOW/MEDIUM/HIGH/CRITICAL) |

### Context Continuity

| Command | Description |
|---------|-------------|
| `context [<id>]` | Emit scoped context pack (durable task state) |
| `note <id> -m <text>` | Append a session note |
| `checkpoint <id> -s <summary>` | Record a status checkpoint |
| `redirect <id> --accept <criteria>` | Update scope mid-flight without context loss |

### Coordination

| Command | Description |
|---------|-------------|
| `scope <id> <file>` | Check file ownership (derived from diffs) |
| `validate` | Validate manifest + branch consistency |
| `migrate [<story-id>]` | Import a v1 SQLite story into a v2 stack |
| `version` / `help` | Show version / help |

### Status Values

`TODO` → `IN_PROGRESS` → `VERIFIED` → `IN_REVIEW` → `APPROVED` → `MERGED`

## Architecture

### Data Model

**`.acts/stack.json`** — the coordination manifest (source of truth for coordination state):

```json
{
  "version": 2,
  "id": "auth",
  "title": "Add user authentication",
  "base_branch": "acts/auth/base",
  "changes": [
    {
      "id": "c1",
      "title": "JWT middleware",
      "branch": "acts/auth/c1-jwt-middleware",
      "parent": null,
      "status": "VERIFIED",
      "acceptance": ["token validated on /api/*", "unit tests"],
      "verify": {
        "test": { "cmd": "npm test", "ok": true, "exit_code": 0, "duration_ms": 107 },
        "lint": { "cmd": "npm run lint", "ok": true, "exit_code": 0, "duration_ms": 99 }
      },
      "notes": [".acts/changes/c1/notes/1785920187.md"],
      "checkpoint": "done: middleware core; blocked: caching; next: tests",
      "pr": { "url": "https://github.com/you/repo/pull/12", "approved": true }
    }
  ]
}
```

- **Git branches** — the actual code truth. Each change is a stacked branch; landing merges it into the base branch.
- **Session notes** — `.acts/changes/<id>/notes/*.md`, referenced from the manifest.
- **Cross-repo knowledge graph** — `.acts/cbm/` (gitignored), built by the `cbm` OpenCode plugin.

### Verification Gate

`acts verify` runs quality gates and records evidence into the manifest. A change **cannot be reviewed** until verification passes:

- `review` refuses with `VerifyRequired` if any configured gate failed.
- `verify --all` walks the stack bottom-up.
- Quality gates are auto-detected from the repo (`Makefile`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, …) or configured explicitly via `.acts/acts.json`:

```json
{
  "quality_gate": {
    "test": "npm test && cd acts-core && zig build test",
    "lint": "node --check .opencode/plugins/acts.js",
    "typecheck": null,
    "build": "cd acts-core && zig build"
  }
}
```

Commands containing shell metacharacters (`&&`, `|`, `>`, `;`) are run via `sh -c`.

### Risk-Based Human-in-the-Loop

`acts risk <id>` classifies a change by how much damage it can do:

| Tier | Trigger | Control |
|------|---------|---------|
| **LOW** | small diff, no cross-repo edges, verified | **Auto-approve + auto-land** after verify |
| **MEDIUM** | moderate diff (≥8 files) or 1–2 complex symbols | Standard PR review |
| **HIGH** | 1 cross-repo edge, ≥30 files, or ≥5 complex symbols | Mandatory human review |
| **CRITICAL** | ≥2 cross-repo edges | Mandatory human review + escalation checklist |

- Tier is computed by `acts verify` / `acts review` and stored in the manifest.
- The CBM plugin can feed real cross-repo edge counts (`risk_cbm`), making the tier precise.
- Auto-land is gated by `.acts/acts.json`:

```json
{ "hilt": { "auto_land_low": false } }
```

- Every approve/rework (human or `__auto__`) is recorded in the change's `approvals[]` audit log with its tier.
- **Stale-verification guard**: if the base branch moves after a change was verified, `stack land` requires `acts verify` again.

### File Ownership

Ownership is **derived from git diffs**, not stored:

```bash
acts scope c1 src/auth.ts
# { "file_path": "src/auth.ts", "action": "ok", "message": "File is part of change c1's diff" }
```

If a file is not in the change's diff, `acts scope` returns `warn` — a signal to confirm it belongs to the task before editing.

## Integration Guides

### OpenCode (Plugin + Skill)

The OpenCode plugin provides automatic context injection and native tools; a superpowers-style skill teaches agents the workflow.

**Installation** — in `opencode.json`:

```json
{
  "plugin": [
    "superpowers@git+https://github.com/obra/superpowers.git",
    "./.opencode/plugins/acts.js",
    "./.opencode/plugins/cbm.js"
  ],
  "permission": { "skill": { "acts": "allow" } }
}
```

**What the plugin does:**

1. Injects an ACTS v2 bootstrap + stack context into the first user message of every session
2. Registers native tools: `acts`, `acts_context`, `acts_mode`, `acts_zeplin`
3. Auto-discovers the binary at `.acts/bin/acts` (or `$PATH`)
4. The `acts` skill (`.opencode/skills/acts/SKILL.md`) auto-activates so the agent loads context before coding

**Agent usage:**

```
acts_context            # Load the context pack for the active change before coding
acts "verify c1"        # Run quality gates (records evidence)
acts "review c1"        # Submit the stacked PR
acts "stack status"     # Show stack + change statuses
```

**Zeplin design links** — when a design link is given, use `acts_zeplin <url>` (or `node acts-zeplin-contract.mjs --flow <url>` / `--scenario <url>`) to extract the inferred API contract and feed it into the change's acceptance criteria. Requires `ZEPLIN_ACCESS_TOKEN`.

See [docs/INTEGRATION.md](docs/INTEGRATION.md) for details.

### Claude / Cursor / Other Editors (Manual)

For editors without plugin support, agents use the binary via CLI commands described in this README. Add the ACTS v2 rules + commands to `AGENTS.md` (see [docs/templates/agents-minimal.md](docs/templates/agents-minimal.md)).

## CI / CD

ACTS ships with a CI workflow that builds the binary, runs unit + plugin tests, and exercises the full v2 lifecycle (stack create → change add → verify gate blocks review → verify → approve → land → validate). See [docs/ci-cd-examples.md](docs/ci-cd-examples.md) and [`.github/workflows/ci.yml`](.github/workflows/ci.yml).

## Development

### Project Structure

```
acts-core/
├── build.zig          # Build configuration
├── build.zig.zon      # Package manifest
├── src/
│   ├── main.zig       # CLI entrypoint and command dispatch
│   ├── stack.zig      # v2 manifest model + validation
│   ├── git.zig        # git/gh/git-spice subprocess wrapper
│   ├── verify.zig     # Quality-gate runner (detect + execute)
│   └── context.zig    # Durable context pack builder
└── tests/             # Zig unit tests
.opencode/
├── plugins/
│   ├── acts.js        # ACTS v2 OpenCode plugin
│   └── cbm.js         # codebase-memory-mcp plugin (cross-repo)
├── skills/acts/       # superpowers-style skill
└── commands/          # slash commands
tests/                 # npm plugin tests (acts + cbm)
```

### Build & Test Commands

```bash
cd acts-core
zig build              # Debug build
zig build test         # Zig unit tests
zig build release -Dversion=2.0.0   # Optimized release
cd ..
npm test               # Plugin tests (acts-plugin + cbm-plugin)
```

### Adding a New Command

1. Add a `cmd*` function in `src/main.zig`
2. Register the dispatch in `runCommand`
3. Add a helper in `src/stack.zig` / `src/git.zig` as needed
4. Update the usage text and this README

## Migration from v1

ACTS v2 replaces the v1 SQLite-backed model (stories/tasks/gates) with a git-native model (stacks/changes). Import an existing v1 story:

```bash
# Requires the `sqlite3` CLI
acts migrate LEGACY-42
# → migrated v1 story LEGACY-42 → v2 stack (base branch acts/LEGACY-42/base, 3 changes)
```

`acts migrate` maps v1 tasks → v2 changes (preserving parent chains, statuses, and file ownership as session notes). See [docs/MIGRATION.md](docs/MIGRATION.md).

## License

MIT License — See [LICENSE](LICENSE)

## Contributing

1. Run `acts validate` before committing
2. Follow the ACTS v2 protocol for your own contributions
3. Run plugin tests: `npm test` (offline tests for the `acts` and `cbm` OpenCode plugins)

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| 2.1.0 | 2026-08 | **Risk-based HITL + centralized CBM**: `acts risk` tiering (LOW/MEDIUM/HIGH/CRITICAL), auto-land LOW-risk verified changes, escalation checklist for HIGH/CRITICAL, approval audit log, stale-verification guard; CBM binary installed once per machine with one shared graph + `cbm_bootstrap` for CI; plugin auto-injects the active change's context pack with optional CBM blast-radius; per-change cost tracking (`acts note --cost`) |
| 2.0.0 | 2026-08 | **Git-native redesign**: SQLite replaced by `.acts/stack.json` manifest; story/task/gate model replaced by **stack** (base branch) + **change** (stacked branch + PR); verification gates (`acts verify`) replace preflight/review ceremony; review via standard stacked PRs (gh/git-spice); durable context packs (`acts context`) with notes/checkpoint/redirect; ownership derived from git diffs; OpenCode skill + slash commands; greenfield Zig core |
| 1.3.1 | 2026-07 | Cross-repo memory delivered as a dedicated `cbm` OpenCode plugin: auto-installs the codebase-memory-mcp binary, exposes its 14 native tools + fleet helpers (`cbm_repos`/`cbm_index_all`/`cbm_changes`/`cbm_install`), `acts_memory scope` ACTS bridge; removed the separate `mcp` server entry; offline `npm test` added |
| 1.3.0 | 2026-07 | Cross-repo orchestration via codebase-memory-mcp: OpenCode `references` indexed into a shared knowledge graph, `acts_memory` plugin tool (index, scope, trace, query, changes), cross-repo system context |
| 1.2.0 | 2026-07 | Story coding rules, markdown compression pipeline, per-story rule sections with tag/glob applicability scoring, token budget enforcement, parent story inheritance |
| 1.1.3 | 2026-05 | Memory leak fixes, SQL prepare fix, version string consistency, QueryFailed error reporting, `acts state read --format` (json/pretty/table), JSON output fix |
| 1.1.2 | 2026-05 | Human Review Experience (HRE), file override system, vim navigation, quality gates |
| 1.1.0 | 2026-05 | Multi-story, WAL mode, maintenance tasks, proactive triggers, changelog, git-based review |
| 1.0.0 | 2026-01 | SQLite backend, Zig binary, gate triggers |
| 0.6.2 | 2026-04 | Code review gates, GitHuman integration |
| 0.6.1 | 2026-03 | Session summaries, agent compliance |
| 0.6.0 | 2026-03 | Operations framework, preflight |
