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
│  Your Tool (Cursor, Claude Code, etc.)      │
├─────────────────────────────────────────────┤
│  ACTS Operations                            │
│  (preflight, task-start, handoff, etc.)     │
├─────────────────────────────────────────────┤
│  ACTS State (.story/)                       │
│  (state.json, sessions, reviews)            │
├─────────────────────────────────────────────┤
│  Constitution (AGENTS.md)                    │
└─────────────────────────────────────────────┘
```

## Quick Start

```bash
# 1. Copy this repo's .acts/ directory into your project
cp -r acts-spec/.acts ./.acts/

# 2. Create your constitution
cp acts-spec/docs/templates/agents-minimal.md ./AGENTS.md

# 3. Create state directories
mkdir -p .story/{tasks,sessions,reviews/{active,archive}}

# 4. Install GitHuman (for code review)
npm install -g githuman

# 5. Start your first story
# In your AI coding agent (Cursor, Claude Code, etc.):
"Initialize ACTS tracker for PROJ-XXX, title 'Your Feature'"
```

## How It Works

1. **Initialize a story** — Creates spec, plan, and task breakdown
2. **Before coding** — Preflight validates scope and ingests context
3. **Implement** — Agent codes, you review via GitHuman
4. **End your day** — Session summary captures what happened
5. **Hand off** — Next developer picks up with full context

## What You Get

- ✅ Drift prevention (preflight checks scope)
- ✅ Context persistence (session summaries in git)
- ✅ File ownership tracking (no duplicate work)
- ✅ Human oversight (gates at key decisions)
- ✅ Code review (mandatory before commit)
- ✅ Agent attribution (track what AI did and cost)

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

## Files

| File | Purpose |
|------|---------|
| [acts-v0.4.0.md](acts-v0.4.0.md) | Full specification |
| [.acts/operations/](.acts/operations/) | Workflow definitions (11 operations) |
| [.acts/schemas/](.acts/schemas/) | JSON schemas for validation |
| [.acts/report-protocol.md](.acts/report-protocol.md) | Standard report formats |
| [docs/templates/](docs/templates/) | AGENTS.md templates |
| [docs/slides-acts-v0.4.0.md](docs/slides-acts-v0.4.0.md) | Presentation slides |
| [docs/faq.md](docs/faq.md) | Frequently asked questions |
| [docs/minimal-viable-acts.md](docs/minimal-viable-acts.md) | Absolute minimum to try ACTS |

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
