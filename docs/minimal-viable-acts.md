# Minimal Viable ACTS

The absolute minimum to try ACTS. Three files, no dependencies.

---

## The 3 Files You Need

### 1. AGENTS.md (Project Context + ACTS Rules)

Create at repo root. This is the industry-standard file supported by Cursor, Claude Code, OpenCode, Copilot, and 60k+ projects.

```markdown
# [Your Project Name]

## Setup
- Install: `[your install command]`
- Dev: `[your dev command]`
- Test: `[your test command]`

## Code Style
[Your style conventions]

## Testing
[Your testing conventions]

## PR Instructions
- Title format: `[format]`
- Run lint and test before committing

---

## ACTS Integration

This project uses ACTS for multi-developer coordination.

### Rules
- Agent MUST read `.story/state.json` before writing code
- Agent MUST NOT modify files owned by completed tasks
- Agent MUST record session summary before ending
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing

### Architecture
[Your project architecture]

### Forbidden
[What your agent must never do]
```

### 2. .acts/acts.json (Manifest)

```json
{
  "acts_version": "0.4.0",
  "conformance_level": "basic",
  "constitution": "AGENTS.md",
  "tracker_dir": ".story",
  "operations_dir": ".acts/operations",
  "code_review": {
    "enabled": false
  }
}
```

### 3. .story/state.json (Initial State)

```json
{
  "acts_version": "0.4.0",
  "story_id": "TEST-1",
  "title": "My First ACTS Story",
  "status": "ANALYSIS",
  "spec_approved": false,
  "created_at": "2026-03-28T10:00:00Z",
  "updated_at": "2026-03-28T10:00:00Z",
  "context_budget": 50000,
  "tasks": [
    {
      "id": "T1",
      "title": "Implement the feature",
      "status": "TODO",
      "assigned_to": null,
      "files_touched": [],
      "depends_on": [],
      "context_priority": 1
    }
  ],
  "session_count": 0,
  "compressed": false
}
```

---

## How to Test

1. Create the 3 files above
2. Tell your AI agent:

```
Read AGENTS.md. Before writing any code, read .story/state.json.
After writing code, record a session summary.
```

3. See if the agent follows the rules

---

## What You Can Skip Initially

- ❌ Schemas (skip for basic conformance)
- ❌ Templates (write your own AGENTS.md)
- ❌ Operations directory (your agent reads spec directly)
- ❌ GitHuman (skip code review for now)
- ❌ Validation scripts (run later)

---

## Adding Features Gradually

Once basics work, add:

1. **Operations** — Copy from `.acts/operations/` for structured workflows
2. **Schemas** — Copy from `.acts/schemas/` for validation
3. **GitHuman** — Install for code review gates
4. **Templates** — Use for team coordination

---

## What ACTS Actually Does

**Without ACTS:**
- Agent writes code without checking what's been done
- No record of what happened between sessions
- No way to know what AI did vs what you did
- No review before code is committed

**With ACTS:**
- Agent reads state before coding (preflight)
- Session summaries capture decisions and context
- Agent attribution tracks what AI made
- Code review gates ensure quality

---

## Next Steps

Once you've tested with 3 files:

1. Read the full [spec](../acts-v0.4.0.md)
2. Copy the [operations](../.acts/operations/) for structured workflows
3. Install GitHuman for code review
4. Use [templates](./templates/) for team coordination
5. For existing projects: use `append-acts.sh` to add ACTS to your AGENTS.md
