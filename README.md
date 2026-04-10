# ACTS — Agent Collaborative Tracking Standard

**The protocol for developers using AI agents on shared code.**

---

## The Problem

When multiple developers use AI coding agents on shared work, three failures emerge:

- **Drift** — agents diverge from the agreed technical design
- **Duplication** — agents reimplement already-completed work
- **Context loss** — handoffs between developers lose decisions and state

## The Solution

ACTS defines a minimal, git-native protocol that sits above your tools.

Your AI agent (Cursor, Claude Code, Copilot, etc.) reads operation files and executes structured workflows. Humans approve at gates. State lives in your repo.

```text
┌─────────────────────────────────────────────┐
│  Layer 7: MCP CONTEXT ENGINE (OPTIONAL)     │
│  Operation-aware context delivery            │
├─────────────────────────────────────────────┤
│  Layer 6: CODE REVIEW                       │
│  tuicr, mandatory before task completion      │
├─────────────────────────────────────────────┤
│  Layer 5: ADAPTERS (community)              │
│  Tool-specific bridges                      │
├─────────────────────────────────────────────┤
│  Layer 4: COMMUNICATION                     │
│  Changelog, tracker sync                    │
├─────────────────────────────────────────────┤
│  Layer 3: OPERATIONS                        │
│  Portable workflow definitions              │
├─────────────────────────────────────────────┤
│  Layer 2: STATE                             │
│  .story/ directory, sessions                │
├─────────────────────────────────────────────┤
│  Layer 1: CONSTITUTION                      │
│  AGENTS.md — shared rules                   │
└─────────────────────────────────────────────┘
```

## AGENTS.md Integration

ACTS uses the industry-standard `AGENTS.md` file — adopted by 60k+ open source projects and supported by Cursor, Claude Code, OpenCode, Copilot, Gemini CLI, and many other tools.

**One file serves dual purpose:**

1. **Project context** for any AI agent (setup, code style, testing)
2. **ACTS rules** for multi-developer coordination

See [AGENTS.md standard](https://agents.md/) for details.

## Quick Start

### New project (copy full template)

```bash
# 1. Copy this repo's .acts/ directory into your project
cp -r acts-spec/.acts ./.acts/

# 2. Create your AGENTS.md (project context + ACTS rules)
cp acts-spec/docs/templates/agents-minimal.md ./AGENTS.md

# 3. Create state directories
mkdir -p .story/{tasks,sessions,reviews/{active,archive}}

# 4. Install tuicr (for code review)
brew install agavra/tap/tuicr
# Or: cargo install tuicr

# 5. Start your first story
# In your AI coding agent (Cursor, Claude Code, etc.):
"Initialize ACTS tracker for PROJ-XXX, title 'Your Feature'"
```

### Existing project (append to existing AGENTS.md)

```bash
# 1. Copy this repo's .acts/ directory into your project
cp -r acts-spec/.acts ./.acts/

# 2. Append ACTS section to your existing AGENTS.md
./acts-spec/scripts/append-acts.sh ./AGENTS.md

# 3. Create state directories
mkdir -p .story/{tasks,sessions,reviews/{active,archive}}

# 4. Install tuicr (for code review)
brew install agavra/tap/tuicr
# Or: cargo install tuicr
```

### Quick Install (one-liner)

For new or existing projects, use the automated installer:

```bash
curl -sL https://raw.githubusercontent.com/tommasop/acts-spec/master/scripts/install-acts.sh | bash
```

This single command will:

- Download and install the `.acts/` directory
- Create the `.story/` directory structure  
- Create or update `AGENTS.md` with ACTS integration
- Install tuicr (for code review)
- Update `.gitignore` with recommended entries

## How It Works

1. **Initialize a story** — Creates spec, plan, and task breakdown
2. **Before coding** — Preflight validates scope, creates task branch, ingests context
3. **Implement** — Agent codes on task branch, you review via tuicr
4. **Code review gate** — Mandatory review before task completion (hard stop)
5. **End your day** — Session summary captures what happened
6. **Hand off** — Next developer picks up with full context

## What You Get

- ✅ Drift prevention (preflight checks scope)
- ✅ Context persistence (session summaries in git)
- ✅ File ownership tracking (no duplicate work)
- ✅ Human oversight (all gates are hard stops)
- ✅ Code review (mandatory before task completion)
- ✅ Branch-per-task isolation (compatible with all tools)
- ✅ Agent attribution (track what AI did and cost)
- ✅ Industry alignment (AGENTS.md standard)
- ✅ Context optimization (Layer 7: MCP engine eliminates tool call residue)
- ✅ Cross-task learning (Layer 7: rejected approaches shared across tasks)

## What ACTS Is NOT

- ❌ A framework or library to install
- ❌ A specific AI tool or IDE
- ❌ A complex orchestration system
- ❌ Tied to any vendor or platform

## What ACTS IS

- ✅ A protocol defined in markdown files
- ✅ Git-native (everything in your repo)
- ✅ Works with any AI coding agent
- ✅ Incremental (adopt what you need)
- ✅ Industry standard (AGENTS.md)

## Files

| File | Purpose |
|------|---------|
| [acts-v0.5.0.md](acts-v0.5.0.md) | Full specification (includes Layer 7) |
| [.acts/operations/](.acts/operations/) | Workflow definitions (11 operations) |
| [.acts/schemas/](.acts/schemas/) | JSON schemas for validation |
| [.acts/mcp-server/](.acts/mcp-server/) | Layer 7 MCP Context Engine (TypeScript) |
| [.acts/report-protocol.md](.acts/report-protocol.md) | Standard report formats |
| [docs/templates/](docs/templates/) | AGENTS.md templates |
| [docs/slides-acts-v0.4.0.md](docs/slides-acts-v0.4.0.md) | Presentation slides |
| [docs/faq.md](docs/faq.md) | Frequently asked questions |
| [docs/minimal-viable-acts.md](docs/minimal-viable-acts.md) | Absolute minimum to try ACTS |
| [Layer 7 design spec](docs/superpowers/specs/2026-03-31-acts-layer7-mcp-context-engine-design.md) | MCP Context Engine design |

## Design Principles

| Principle | Meaning |
|---|---|
| **Git-native** | All state lives in the repository |
| **Tool-agnostic** | Works with any AI coding agent |
| **Language-agnostic** | No assumptions about your stack |
| **Human-readable** | Every artifact is Markdown or JSON |
| **Machine-readable** | Schemas strict enough for agents to parse |
| **Incremental** | Adopt partially. Each layer adds value |

## License

CC-BY-SA-4.0
