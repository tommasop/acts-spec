# ACTS FAQ

## What is ACTS?

ACTS is a protocol that coordinates how developers use AI coding agents on shared codebases. It prevents drift, duplication, and context loss.

## What does ACTS actually do?

ACTS defines:

1. **Operations** — Workflows your agent executes (preflight, handoff, etc.)
2. **State** — A `.story/` directory tracking what's been done
3. **Gates** — Points where humans must approve before proceeding
4. **Sessions** — Records of what happened each time someone worked

Your AI agent reads these files and follows the rules. You approve at gates.

## What is AGENTS.md?

[AGENTS.md](https://agents.md/) is an industry-standard file adopted by 60k+ open source projects. It provides context and instructions for AI coding agents.

ACTS uses AGENTS.md as its constitution file — a single file that serves both:
- **Project context** for any AI agent (setup, code style, testing)
- **ACTS rules** for multi-developer coordination

See the [AGENTS.md standard](https://agents.md/) for details.

## Do I need ACTS if I work alone?

**Yes, for two reasons:**

1. **Session summaries** — Remember what you did and why, even months later
2. **Code review** — GitHuman (or lazygit) catches issues before commit

## Do I need ACTS if I already have agent rules (Cursor Rules, CLAUDE.md)?

**Yes, because ACTS is above that layer:**

- Cursor Rules tell your agent HOW to write code
- ACTS tells your agent WHAT to check before writing, WHEN to stop, and HOW to hand off to others
- ACTS uses AGENTS.md (the industry standard) while Cursor Rules use tool-specific formats

## Is this just for teams?

No. Freelancers and open source maintainers benefit from:

- Context persistence (session summaries)
- Cost tracking (agent attribution)
- Quality assurance (code review gates)

## What AI tools does ACTS work with?

Any tool that can read markdown files, including those that support AGENTS.md:

- Cursor
- Claude Code
- OpenCode
- Copilot
- Gemini CLI
- Codex
- Aider
- Windsurf
- Devin
- Any custom agent

## Do I need a code review tool?

For v0.6.2+ code review: GitHuman is the default (npm install -g githuman).
For basic ACTS: no, you can disable code review in `.acts/acts.json`.
Alternative: lazygit is also supported (brew install lazygit).

## What's the minimum to try ACTS?

3 files: `AGENTS.md`, `.acts/acts.json`, `.story/state.json`

See [Minimal Viable ACTS](minimal-viable-acts.md).

## Is this a framework I need to install?

No. ACTS is markdown files in your repo. Your agent reads them. Nothing to install except optionally GitHuman (or lazygit) for code review.

## How does ACTS compare to Cursor Rules / CLAUDE.md?

| | Cursor Rules | ACTS |
|---|---|---|
| Scope | One tool | Any tool |
| Purpose | How to write code | How to coordinate work |
| State | None | `.story/` directory |
| Human oversight | None | Gates at key decisions |
| Multi-developer | Not addressed | First-class handoffs |
| Industry standard | No (tool-specific) | Yes (AGENTS.md) |

## Can I use ACTS without git?

No. ACTS is git-native. All state lives in the repository.

## What happens if my agent doesn't follow ACTS?

The agent will report non-compliance in the session summary's "Agent Compliance" section. This enables you to identify patterns and adjust agent configuration.

## How much does ACTS cost?

ACTS itself is free (CC-BY-SA-4.0).
Your AI agent tool may have costs.
ACTS tracks token usage so you can see what you're spending.

## What is Layer 7 (MCP Context Engine)?

Layer 7 is an optional MCP server that provides intelligent context delivery. Instead of agents reading files ad-hoc, the server delivers pre-assembled context bundles optimized for each ACTS operation. It solves 10 standard context problems including instruction drift, tool call residue, and context degradation.

Layer 7 is optional — it accelerates existing layers but doesn't replace them. The file-based system remains the source of truth.

## Should I use Layer 7?

**If you're starting out:** No. Begin with Layers 1-3.

**If you experience context issues:** Yes. Symptoms include: agent forgets AGENTS.md rules mid-session, agent repeats rejected approaches, session summaries contain fabricated claims, agent drifts from scope on long tasks.

**If you work on large stories (6+ tasks):** Recommended. Context management becomes critical at scale.

See the [Layer 7 design spec](superpowers/specs/2026-03-31-acts-layer7-mcp-context-engine-design.md) for details.

## What is strict mode?

ACTS Strict (`conformance_level: "strict"`) adds two extra gates:

1. **Per-batch commit review** — Agent groups commits into batches (1-5) and gets your approval before continuing.
2. **Architecture discussion** — Before making significant design decisions (new dependencies, API changes, pattern changes), agent presents its reasoning and gets your approval.

Both gates are hard stops — agent waits for your explicit confirmation. This gives you much more control over AI-generated code at the cost of more interaction.

## Do I need superpowers?

No. ACTS works without superpowers. But superpowers improves the quality of individual agent sessions with TDD, systematic planning, subagent-driven development, and code review workflows.

ACTS handles multi-developer coordination (state, handoffs, file ownership).
Superpowers handles single-developer agent quality (TDD, planning, code review, debugging).

Install at: https://github.com/obra/superpowers

## What is gh-stack integration?

gh-stack (GitHub Stacked PRs) turns ACTS task branches into stacked PRs on GitHub.
Each task gets its own focused PR with independent CI and stack navigation.

**Benefits:** Each task reviewed as focused PR, GitHub stack map for dependency navigation, ordered merge.

**Requires:** `gh extension install github/gh-stack` + private preview access ([sign up](https://gh.io/stacksbeta))

**Enable in `.acts/acts.json`:**
```json
{
  "gh_stack": {
    "enabled": true,
    "prefix": "story/<STORY_ID>",
    "numbered": true,
    "draft_prs": true
  }
}
```

**Limitation:** GitHub only. Not portable to GitLab, Bitbucket, etc.
