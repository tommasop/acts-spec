# ACTS v2.0.0

**Agent Collaborative Tracking Standard** — A git-native coordination protocol for agent-aided development. Git is the system of record: a *stack* is a feature (a **feature branch** off `master`); a *change* is one unit of agent work (**a checkpoint on that branch**). Verification is the gate; context is served on demand.

[![CI](https://github.com/tommasop/acts-spec/actions/workflows/ci.yml/badge.svg)](https://github.com/tommasop/acts-spec/actions/workflows/ci.yml)
[![Release](https://github.com/tommasop/acts-spec/actions/workflows/release.yml/badge.svg)](https://github.com/tommasop/acts-spec/releases)

## What is ACTS?

ACTS is a protocol for coordinating AI-assisted software development across multiple sessions, developers, and tools. It prevents context loss, enforces verification before review, tracks file ownership, and keeps a durable record of decisions.

**Key features:**

- **Git-native state** — A *stack* is a feature (a feature branch off `master`); a *change* is one unit of agent work (a checkpoint, `start_sha..end_sha`, on that branch). Progress is the git ref state itself — there is no sidecar database to drift or bypass.
- **Manifest**: `.acts/stack.json` — the durable coordination board. Human-readable, diffable, committed to the stack's feature branch.
- **Verification is the gate** — `acts verify` runs quality gates (test/lint/typecheck/build), records evidence, and **blocks review until it passes**. No manual preflight ceremony.
- **Risk-based human-in-the-loop** — `acts risk` classifies each change (LOW/MEDIUM/HIGH/CRITICAL) from diff size + cross-repo blast radius. LOW-risk verified changes **auto-approve and auto-land**; HIGH/CRITICAL require mandatory human review with an escalation checklist. Every approval/rework is audited in the manifest.
- **PR-native review** — `acts review` pushes the stack's feature branch and submits/updates the stack's ONE PR via `gh`, with the body = agent rationale + verification evidence + acceptance criteria + risk tier.
- **Durable context** — `acts context` emits a scoped context pack (acceptance criteria, preceding changes, verification status, notes, changed files); the OpenCode plugin **auto-injects** the active change's pack at session start, with optional CBM blast-radius.
- **Ownership derived from git** — `acts scope` checks whether a file belongs to a change's diff; no manual ownership tables.
- **v1 → v2 migration** — `acts migrate` imports an existing v1 SQLite story into a v2 stack.
- **Cross-repo orchestration** — [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) is a **native OpenCode MCP server** (no plugin): the binary is installed **once per machine** (`~/.local/bin` / `~/.cache/codebase-memory-mcp`), the fleet shares **one knowledge graph**, and `acts graph bootstrap` idempotently rebuilds it on CI/fresh machines. Native tools (`trace_path`, `query_graph`, …) trace calls across repos (`CROSS_*` edges); `acts graph span` maps a change to its repos, `acts tech-lead` runs pre-flight risk, `acts doc-risk` evaluates a spec against the code.
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

### Install Binaries Globally (acts + cbm)

The quickest path installs `acts` **and** the cross-repo graph engine `cbm` once per machine — no per-project copies:

```bash
# Install acts globally (~/.local/bin), plus cbm for cross-repo intelligence
curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/master/install.sh | bash -s -- --with-cbm

# Update both later
curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/master/install.sh | bash -s -- --update --with-cbm
```

### Global AI skills (archify, cbm, ponytail)

The three companion skills are **available to every project** when installed once per machine:

| Skill | What it gives every project | Global install |
|-------|-----------------------------|----------------|
| **cbm** (codebase-memory-mcp) | Cross-repo knowledge graph, `acts graph` / `tech-lead` / `doc-risk` | Already global — `acts setup` installs the binary + shared graph at `~/.cache/codebase-memory-mcp` |
| **archify** | `acts diagram` renders architecture HTML; `acts review` attaches the delta | `acts archify install --global` → `~/.agents/skills/archify` (auto-loaded by opencode) |
| **ponytail** | `/ponytail*` commands + rules; `acts review` appends the minimality checklist | `acts ponytail install --global` → `~/.config/opencode/{command,plugin,agents}` + registered in the global `opencode.json` |

`acts setup --with-archify --with-ponytail --global` wires a project AND installs both skills machine-wide. Per-project installs (no `--global`) still work and override global detection.

Or, after building from source, self-install with the binary itself:

```bash
cd acts-core && zig build release -Dversion=2.0.0
./zig-out/bin/acts setup . --bin-dir ~/.local/bin --github
# → copies `acts` to ~/.local/bin, installs `cbm`, and bootstraps the project
```

### Bootstrap a Project (no clone needed)

You do **not** need to clone `acts-spec` to use ACTS. Once `acts` is installed, run:

```bash
acts setup . --github
# → installs .opencode/plugins/acts.js + skill + slash commands
# → wires opencode.json (acts plugin + codebase-memory-mcp MCP server, skill permission)
# → injects the ACTS v2 section into AGENTS.md (idempotent)
# → writes .github/workflows/opencode.yml (OpenCode GitHub integration)
```

Options: `--source <acts-spec-dir>` (use a local checkout instead of GitHub, e.g. offline), `--no-install` (skip binary install), `--bin-dir <dir>` (global install location), `--force` (overwrite existing files).

> Pre-built binaries for Linux/macOS are published to [GitHub Releases](https://github.com/tommasop/acts-spec/releases) once tagged. Release artifacts (`dist/`) are **built by CI**, never committed to the repo.

## Releasing

Releases are produced entirely by [`.github/workflows/release.yml`](.github/workflows/release.yml) — no local `dist/` build is needed. To cut a release:

```bash
git tag 2.1.0            # push a tag (with or without a leading 'v')
git push origin 2.1.0
```

CI cross-compiles for Linux/macOS (x86_64 + aarch64), packages `acts-<version>-<platform>.tar.gz` per target, and attaches them to a GitHub Release. `install.sh` downloads these exact archives, so the archive name must stay `acts-<version>-<platform>.tar.gz`.

A local host-only archive (for testing) is available via `make package VERSION=2.1.0` — it writes to `dist/` (gitignored).

## Quick Start

### Start a Stack (a feature)

```bash
# 1. Start a stack — creates the feature branch + manifest
acts stack create auth -t "Add user authentication"
# → stack auth created on branch acts/auth/feature

# 2. Add a change (one unit of agent work — a checkpoint on the feature branch)
acts change add c1 -t "JWT middleware" --accept "token validated on /api/*
unit tests"
# → change c1 added (checkpoint) on feature branch acts/auth/feature
```

### Work a Change

```bash
# Load the durable context pack (acceptance criteria, notes, files, verification)
acts context c1

# ... agent writes code; its commits become change c1's checkpoint on the feature branch ...

# Run quality gates — records evidence; gates review
acts verify c1
#   test: PASS (npm test) [107ms]
#   lint: PASS (npm run lint) [99ms]
#   build: PASS (npm run build) [135ms]
```

### Review (the stack's ONE PR)

```bash
# Submit/update the stack's ONE PR (feature → master); verify must pass
acts review c1
# → PR submitted: https://github.com/you/repo/pull/12

# Human reviews on GitHub → approve
acts approve c1

# Merge the whole feature branch once all changes are approved; closes the PR
acts stack land
```

### Track Status

```bash
acts stack status
# Stack: auth — Add user authentication
#   feature: acts/auth/feature (off master)
#   PR: https://github.com/you/repo/pull/12
#   [ ] VERIFIED  JWT middleware  (abc1234..def5678)

acts change status c1
# Change: c1 — JWT middleware
#   status: VERIFIED
#   range: abc1234..def5678
#   risk: LOW
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
| `stack create <id> [-t <title>]` | Start a new stack (feature branch + manifest) |
| `stack status [--json]` | Show stack tree + change statuses |
| `stack land` | Merge the whole feature branch (all changes APPROVED) |

### Change Lifecycle

| Command | Description |
|---------|-------------|
| `change add <id> -t <title> [--accept <criteria>]` | Add a change (checkpoint on the feature branch) |
| `change status [<id>]` | Show change details |
| `verify [<id>] [--all] [--force -m <reason> \| --manual <evidence>]` | Run quality gates; record evidence (**gate for review**). `--force` overrides failures outside the change; `--manual` skips gates |
| `review <id>` | Submit/update the stack's ONE PR (feature vs base; requires verify to pass); auto-lands LOW-risk |
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
| `diagram <id> [--delta] [--attach]` | Render the change's architecture impact via archify (self-contained HTML; `--delta` = Before/Delta/After; `--attach` = comment on the change's PR) |
| `archify install [--global]` | Install the archify diagram renderer skill (`npx skills add tt-a1i/archify`; `--global` installs machine-wide) |
| `ponytail install [--global]` | Install the ponytail minimality skill (rules + commands + plugin; `--global` installs machine-wide; `acts review` appends its checklist to the PR) |
| `validate` | Validate manifest + branch consistency |
| `setup [dir] [--source <acts-spec>] [--github] [--force] [--bin-dir <dir>] [--with-archify] [--with-ponytail] [--global]` | Install binaries globally + wire a project (plugins, opencode.json, AGENTS.md, GitHub workflow). `--with-archify` also installs the archify diagram renderer skill; `--with-ponytail` the ponytail minimality skill; `--global` installs those two machine-wide instead of per-project |
| `migrate [<story-id>]` | Import a v1 SQLite story into a v2 stack |
| `version` / `help` | Show version / help |

### Status Values

`TODO` → `IN_PROGRESS` → `VERIFIED` → `IN_REVIEW` → `APPROVED` → `MERGED`

## Architecture

### Data Model

**`.acts/stack.json`** — the coordination manifest (source of truth for coordination state):

```json
{
  "version": 3,
  "id": "auth",
  "title": "Add user authentication",
  "branch": "acts/auth/feature",
  "base_branch": "master",
  "pr": { "url": "https://github.com/you/repo/pull/12" },
  "changes": [
    {
      "id": "c1",
      "title": "JWT middleware",
      "status": "APPROVED",
      "start_sha": "abc…",
      "end_sha": "def…",
      "acceptance": ["token validated on /api/*"],
      "verify": { "test": { "cmd": "npm test", "ok": true, "exit_code": 0, "duration_ms": 107 } },
      "checkpoint": "done: middleware core"
    }
  ]
}
```

- **Git branches** — the actual code truth. The stack lives on one feature branch; a change is a commit range on it; landing merges the feature branch into `master`.
- **Checkpoints** — A change is a checkpoint: `start_sha..end_sha` on the feature branch. The stack has ONE PR.
- **Session notes** — `.acts/changes/<id>/notes/*.md`, referenced from the manifest.
- **Cross-repo knowledge graph** — `.acts/cbm/` (gitignored), built by the `cbm` OpenCode plugin.

### Verification Gate

`acts verify` runs quality gates and records evidence into the manifest. A change **cannot be reviewed** until verification passes:

- `review` refuses with `VerifyRequired` if any configured gate failed.
- `verify --all` walks the stack's checkpoints in order.
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

#### Forcing verification

Sometimes gates fail for reasons **outside the change** — e.g. a repo-wide `make lint` flags pre-existing files owned by another change, or the gate tooling itself is broken in the environment. ACTS lets you override, but **only when the failure is provably outside this change**:

```bash
# Run gates; override failures attributed to files OUTSIDE this change's diff.
acts verify c1 --force -m "lint fails on pre-existing files owned by BACKEND-AS-SERVICE"

# Skip gates entirely and record evidence (e.g. tooling hangs in this env).
acts verify c1 --manual "gates hang in this environment; verified manually"
```

**Enforcement:** `--force` refuses to override if the failing gate output references a file this change owns (via `git diff`):

```
force denied: the failing gate output includes files this change owns.
  Fix the code or correct the gate config (`.acts/acts.json` quality_gate), then re-verify.
```

So force covers:
- **A** — failing files are outside the change's diff (another change's files), or
- **B** — no files can be attributed (broken/wrong gate tooling).

It can never hide a regression in code you touched. A forced verification is recorded in the manifest (`verify.forced`, `verify.force_reason`), appended to the change's `approvals[]` audit log, and surfaced as **"⚠️ forced verification"** in `acts context` and the PR body. Manual verification is the `verify.force_kind = "manual"` variant.

To override manually (e.g. to unblock review when tooling can't run), add to the change's `verify` object in `.acts/stack.json`:

```json
"verify": {
  "lint": { "cmd": "make lint", "ok": false, "exit_code": 1 },
  "forced": true,
  "force_reason": "lint fails on pre-existing files owned by BACKEND-AS-SERVICE; none in this change's diff"
}
```

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
- **Stale-verification guard**: if the integration branch (`master`) moves after a change was verified, `stack land` requires `acts verify` again.

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
    "./.opencode/plugins/acts.js"
  ],
  "mcp": {
    "codebase-memory-mcp": {
      "type": "local",
      "command": ["codebase-memory-mcp"],
      "enabled": true
    }
  },
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
acts "review c1"        # Submit/update the stack's ONE PR
acts "stack status"     # Show stack + change statuses
```

**Zeplin design links** — when a design link is given, use `acts_zeplin <url>` (or `node acts-zeplin-contract.mjs --flow <url>` / `--scenario <url>`) to extract the inferred API contract and feed it into the change's acceptance criteria. Requires `ZEPLIN_ACCESS_TOKEN`.

**Architecture diagrams (archify)** — visualize what a change does to the architecture before review. `acts diagram <id>` renders a self-contained HTML impact map (via the [archify](https://github.com/tt-a1i/archify) agent skill); `--delta` produces a Before/Delta/After comparison of the components the change touches. `acts review` auto-attaches the delta as a PR comment. Install the renderer with `acts archify install` (or `acts setup --with-archify`); without it `acts diagram` degrades to a textual delta summary. The `acts_archify` plugin tool validates/delivers candidate IR JSON directly.

**Minimality (ponytail)** — keep each change the smallest thing that works. `acts ponytail install` (or `acts setup --with-ponytail`) fetches the [ponytail](https://github.com/DietrichGebert/ponytail) rules, `/ponytail*` slash commands, and frontmatter plugin; with it installed, `acts review` appends a ponytail minimality checklist (YAGNI, reuse, shortest diff, no new deps, one runnable check) with per-change diff stats to the stack's PR.

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
│   ├── context.zig    # Durable context pack builder
│   ├── cbm.zig        # CBM client (acts graph / tech-lead / doc-risk)
│   ├── graph.zig      # acts graph + acts tech-lead commands
│   ├── archify.zig    # archify IR builder + renderer discovery
│   ├── diagram.zig    # acts diagram + acts archify install commands
│   └── docrisk.zig    # acts doc-risk static+code-intel analysis
└── tests/             # Zig unit tests
.opencode/
├── plugins/
│   └── acts.js        # ACTS v2 OpenCode plugin (CBM via MCP)
├── skills/acts/       # superpowers-style skill
└── commands/          # slash commands
tests/                 # npm plugin tests (acts.js)
```

### Build & Test Commands

```bash
cd acts-core
zig build              # Debug build
zig build test         # Zig unit tests
zig build release -Dversion=2.0.0   # Optimized release
cd ..
npm test               # Plugin tests (acts.js)
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
# → migrated v1 story LEGACY-42 → v3 stack (feature branch acts/LEGACY-42/feature, 3 changes)
```

`acts migrate` maps v1 tasks → changes (preserving statuses and file ownership as session notes). See [docs/MIGRATION.md](docs/MIGRATION.md).

## License

MIT License — See [LICENSE](LICENSE)

## Contributing

1. Run `acts validate` before committing
2. Follow the ACTS v2 protocol for your own contributions
3. Run plugin tests: `npm test` (offline tests for the `acts` OpenCode plugin)

## Version History

| Version | Date | Key Changes |
|---------|------|-------------|
| 2.5.0 | 2026-08 | **Global skills**: `acts archify install --global` / `acts ponytail install --global` (and `acts setup --global`) install archify + ponytail machine-wide (`~/.agents/skills/archify`, `~/.config/opencode/{command,plugin,agents}`) so every project gets them; cbm was already global; global ponytail detection added to `findPonytail` |
| 2.4.0 | 2026-08 | **ponytail minimality skill**: `acts ponytail install` / `acts setup --with-ponytail` fetch the ponytail rules + `/ponytail*` slash commands + frontmatter plugin; `acts review` appends a ponytail minimality checklist (YAGNI, reuse, shortest diff, no new deps, one runnable check) with per-change diff stats to the stack's PR |
| 2.3.0 | 2026-08 | Single-branch stacks: a stack is one feature branch, a change is a checkpoint (commit range), review is ONE PR per stack (feature → base), and stack land merges the whole branch once all changes are approved (then closes the PR). Legacy v2 manifests still validate |
| 2.2.0 | 2026-08 | **archify diagrams**: new `acts diagram <id>` renders a change's architecture impact as a self-contained interactive HTML via the [archify](https://github.com/tt-a1i/archify) skill (`--delta` = Before/Delta/After, `--attach` = PR comment). `acts review` auto-attaches the delta. `acts archify install` / `acts setup --with-archify` install the renderer; `acts_archify` plugin tool validates/delivers IR. Degrades to a textual delta when the renderer is missing |
| 2.1.6 | 2026-08 | **CBM without the plugin**: removed `cbm.js` — CBM is now a native OpenCode MCP server (`mcp.codebase-memory-mcp`, wired by `acts setup`). Fleet helpers moved into the Zig binary: `acts graph repos/index --all/bootstrap/span`, plus `acts tech-lead <id>` (pre-flight risk report) and `acts doc-risk <file>` (static + code-intelligence doc risk evaluation). Shared CBM client (`cbm.zig`) used across all commands |
| 2.1.0 | 2026-08 | **Risk-based HITL + centralized CBM + `acts setup`**: risk tiering (LOW/MEDIUM/HIGH/CRITICAL), auto-land LOW-risk verified changes, escalation checklist, approval audit log, stale-verification guard; CBM binary installed once per machine with one shared graph + `cbm_bootstrap` for CI; plugin auto-injects the active change's context pack with optional CBM blast-radius; per-change cost tracking; `acts setup` bootstraps a project without cloning (global binary install + plugins/skill/commands + opencode.json + AGENTS.md + GitHub workflow) |
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
