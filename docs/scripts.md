# ACTS Scripts Documentation (v0.4.0 — Code Review Gates)

**Major changes:**
1. Scripts reduced to CI/CD only (v0.3.0)
2. All workflow execution done by agents reading `.acts/operations/*.md` directly
3. Human feedback via **GATE steps** in each operation
4. **v0.4.0:** Mandatory code review gates before task completion
5. **v0.4.0:** Generic CLI-based code review interface (GitHuman primary)

---

## What Changed

### Before (script-heavy)
```
User → Script (acts.sh) → Agent → Operation → Work
```

### After (agent-executed with gates)
```
User → Agent → Operation (with GATE) → Work
         ↑
    Human feedback at gates
```

### v0.4.0: Code Review Gate
```
User → Agent → task-start → [task-review GATE] → commit
                              ↑
                        GitHuman interface
                        Human reviews code
                        Approves/requests changes
```

**Scripts removed:** `acts.sh`, `compress-sessions.sh`, 5 adapter scripts  
**Scripts kept:** `validate.sh` (CI/CD only)  
**New v0.3.0:** `.acts/report-protocol.md` defines standard report formats  
**New v0.3.0:** Operations have explicit GATE steps for human approval  
**New v0.4.0:** `.acts/code-review-interface.json` — generic review API  
**New v0.4.0:** `.acts/operations/task-review.md` — mandatory review gate  
**New v0.4.0:** `.story/reviews/` — active and archived review artifacts

---

## Directory Structure

```text
scripts/
└── validate.sh                    # CI/CD conformance validation ONLY

.acts/
├── code-review-interface.json     # v0.4.0: Generic review interface
├── report-protocol.md             # Standard report formats for gates
├── operations/                    # Agent-executed with GATE steps
│   ├── story-init.md             # + GATE: acknowledge
│   ├── preflight.md              # + GATE: approve
│   ├── task-start.md             # + GATE: acknowledge, runs task-review
│   ├── session-summary.md        # + GATE: approve
│   ├── handoff.md                # + GATE: approve
│   ├── story-review.md           # + GATE: approve
│   ├── compress-sessions.md
│   ├── validate.md               # Interactive validation
│   ├── task-review.md            # v0.4.0: + GATE: review (REQUIRED)
│   └── commit-review.md          # v0.4.0: + GATE: review (optional)
├── schemas/                       # JSON schemas for validation
│   ├── state.json
│   ├── manifest.json
│   ├── operation-meta.json
│   ├── session-summary.json
│   └── review.json               # v0.4.0: Review export schema
└── review-providers/              # v0.4.0: Provider configs
    └── githuman.json             # GitHuman CLI configuration
```

---

## Human-in-the-Loop: How It Works

Instead of running scripts, humans interact with agents. The agent
presents **reports** at key moments and waits for **approval**.

### Report Protocol

Standard formats defined in `.acts/report-protocol.md`:

| Report | Used in | Shows |
|---|---|---|
| **Story Board** | preflight, handoff, story-review | Task status table |
| **Ownership Map** | preflight, handoff | Files owned by done tasks |
| **Scope Declaration** | preflight, task-start | What agent will/won't do |
| **Session State** | session-summary | Build, test, lint, git status |
| **Code Review** | task-review, commit-review | Staged changes and review interface |

### Gate Types

| Type | Behavior | Example |
|---|---|---|
| `GATE: approve` | Wait for "yes" | "Ready to proceed with T1?" |
| `GATE: acknowledge` | Show, any response continues | "Plan created. Continue when ready." |
| `GATE: reject` | Continue on silence, abort on "no" | Rarely used |
| `GATE: review` | External tool integration | "Review staged changes at localhost:3847" |

### Gate Locations

| Operation | Gate | Presented |
|---|---|---|
| `preflight` | After context ingestion | Story Board + Ownership Map + Scope |
| `task-start` | Before implementation | Scope reconfirmation |
| `session-summary` | After writing, before commit | Session State |
| `handoff` | After briefing | Full handoff briefing |
| `story-review` | After acceptance check | AC checklist + PR description |
| `story-init` | After plan creation | Spec + plan summary |
| `task-review` | After staging, before commit | Code Review report (GitHuman interface) |
| `commit-review` | On explicit request | Code Review report (informational) |

---

## `validate.sh` — CI/CD Only

**Purpose:** Deterministic conformance validation for pipelines.

**Not for:** Interactive use by developers (use `acts-validate` skill instead).

### Usage

```bash
# Full validation
./scripts/validate.sh

# Single layer
./scripts/validate.sh --layer 1

# Machine-readable (for CI)
./scripts/validate.sh --json
```

### What It Checks

**Layer 1 — Constitution:**
- AGENT.md exists
- Required sections present
- Rules directives present

**Layer 2 — State:**
- `.story/` structure
- `state.json` fields and validity
- Task ID patterns
- Plan consistency
- Session file naming

**Layer 3 — Operations:**
- All required operations exist
- Valid YAML frontmatter
- Required sections present
- Context Protocol where required

### CI/CD Integration

```yaml
# .github/workflows/acts.yml
name: ACTS Validation
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/validate.sh --json
```

---

## Typical Workflow (No Scripts)

### 1. Start a Story

**User:** "Initialize ACTS tracker for PROJ-305, title 'Add 2FA'"

**Agent:**
- Loads `acts-story-init` skill
- Creates `.story/` with spec, plan, state
- Presents spec + plan summary
- **GATE: acknowledge** — "Review with team. Continue when ready."

### 2. Preflight Before Coding

**User:** "Start working on T1"

**Agent:**
- Loads `acts-preflight`
- Reads AGENT.md, state.json, plan.md
- Ingests context from completed tasks
- Presents reports:
  ```
  ┌─────────────────────────────────────┐
  │ PROJ-305 — Add Two-Factor Auth      │
  │ T1: TODO → I will build TOTP setup  │
  │ T2: TODO                            │
  ├─────────────────────────────────────┤
  │ Files owned by done tasks:          │
  │   (none — T1 is first)              │
  ├─────────────────────────────────────┤
  │ Scope:                              │
  │   I WILL: build TOTP endpoint       │
  │   I will NOT: touch frontend        │
  ├─────────────────────────────────────┤
  │ Ready to proceed? (yes/no)          │
  └─────────────────────────────────────┘
  ```
- **GATE: approve** — waits for "yes"
- Updates state.json, commits

### 3. Implement

**Agent:**
- Loads `acts-task-start`
- Presents scope confirmation
- **GATE: acknowledge** — "Continue when ready"
- Implements with TDD
- Commits regularly

### 4. End Session

**User:** "I'm done for today"

**Agent:**
- Loads `acts-session-summary`
- Runs build, tests, git status (actually)
- Writes session file
- Presents Session State report
- **GATE: approve** — "Commit and push? (yes/no)"
- Commits, pushes

### 5. Handoff

**User:** "Hand off T2 to bob"

**Agent:**
- Loads `acts-handoff`
- Runs preflight for T2 with bob
- Reads all prior sessions for T2
- Produces handoff briefing
- **GATE: approve** — "Reassign to bob? (yes/no)"
- Updates state, commits

### 6. Story Review

**User:** "All tasks done, run story review"

**Agent:**
- Loads `acts-story-review`
- Checks all tasks DONE
- Verifies acceptance criteria
- Runs tests, linter
- Presents AC checklist + PR description
- **GATE: approve** — "Transition to REVIEW? (yes/no)"
- Updates state, commits

---

## Interactive Validation

Instead of `validate.sh`, use the `acts-validate` skill:

**User:** "Run ACTS validation"

**Agent:**
- Loads `acts-validate`
- Runs all 42 checks
- Presents results in table format
- "42 passed, 0 failed. Conformance: FULL."

---

## Adapter Generation

Instead of `./scripts/acts.sh adapter <tool>`, tell the agent:

**User:** "Generate OpenCode configuration for this ACTS project"

**Agent:**
- Reads `.acts/operations/*.md`
- Generates `.opencode/skills/acts-*/SKILL.md`
- Generates `.opencode/plugins/acts.js`
- Updates `.acts/acts.json` adapter field

**No script needed.** The agent does this once during project setup.

---

## Why This Change?

| Before | After |
|---|---|
| 3 layers (script → skill → operation) | 1 layer (agent → operation) |
| Preflight ran twice | Preflight runs once with gate |
| Scripts for status, preflight, etc. | Agent presents reports |
| Human learns script commands | Human just talks to agent |
| 9 scripts to maintain | 1 script (CI only) |
| Redundant validation logic | Single source of truth in operations |

**Human oversight preserved:** Gates ensure approval at every key decision.

---

## Migration from Old Flow

If you have existing ACTS projects with the old scripts:

1. **Remove scripts:**
   ```bash
   rm scripts/acts.sh
   rm scripts/compress-sessions.sh
   rm -rf scripts/adapters
   # Keep: scripts/validate.sh (CI only)
   ```

2. **Add report protocol:**
   ```bash
   curl -o .acts/report-protocol.md \
     https://acts-standard.org/report-protocol.md
   ```

3. **Update operations:** Replace operations with gated versions (or add GATE steps manually)

4. **Regenerate tool config:**
   ```
   User: "Regenerate OpenCode skills"
   Agent: Generates fresh .opencode/skills/ and plugin
   ```

---

## Code Review (v0.4.0+)

**New Layer 6:** Mandatory code review gates before task completion.

### How It Works

1. **Task Implementation** (`task-start`)
   - Agent implements task with TDD
   - Stages all changes (`git add .`)
   - Automatically runs `task-review`

2. **Code Review Gate** (`task-review`)
   - Starts GitHuman review server: `githuman serve --port 3847`
   - Presents **Code Review** report with URL
   - Opens browser with staged changes
   - **GATE: review** — waits for human approval

3. **Human Review**
   - Reviews staged changes in browser
   - Adds inline comments if needed
   - Approves or requests changes

4. **Completion**
   - If approved: exports review, commits completion
   - If changes requested: agent addresses, loops back

### Configuration

Enable/disable in `.acts/acts.json`:

```json
{
  "code_review": {
    "enabled": true,
    "provider": "githuman",
    "required_for_tasks": ["*"],
    "skip_for_tasks": ["docs", "chore"]
  }
}
```

### Review Artifacts

```text
.story/reviews/
├── active/              # Current task reviews
│   └── T1-20260328-101500-alice.md
├── archive/             # Completed task reviews
│   └── 2026/
│       └── 03/
│           └── T1-20260328-143000-alice-final.md
└── index.md             # Review registry
```

### Requirements

- **GitHuman** must be installed: `npm install -g githuman`
- Review happens **before** task completion commit
- All reviews are **preserved** in git for audit
- Archived reviews are **never loaded** during context ingestion

### Backward Compatibility

- **v0.3.0 projects:** Set `code_review.enabled: false` to disable
- **Migration:** Install GitHuman, enable when ready
- **Optional:** Can enable per-story or globally

---

## Summary

**Scripts are for CI/CD only.** Everything else is agent-executed.

**Human feedback** happens via GATE steps in operations, not via script output.

**Single source of truth:** `.acts/operations/*.md` define the workflow,
including when and how to ask humans for approval.

**Result:** Simpler, fewer moving parts, same human oversight.
