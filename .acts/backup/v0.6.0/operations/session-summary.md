---
operation_id: session-summary
layer: 3
required: true
triggers: "none"
context_budget: 10000
required_inputs:
  - name: developer
    type: string
    required: true
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
optional_inputs: []
preconditions:
  - ".story/state.json MUST exist"
  - "At least one task MUST be IN_PROGRESS or recently completed"
postconditions:
  - "Session file contains all required sections"
  - "Current state section reflects actual verified state"
  - "All work is committed and pushed"
---

# session-summary

## Purpose

Create a structured snapshot of the current session for handoff to
another developer or for your own future context. This is the primary
mechanism that prevents context loss.

## Steps

1. **Generate filename**
   `<YYYYMMdd-HHmmss>-<developer>.md`

2. **Create session file**
   Create `.story/sessions/<filename>` with ALL sections defined below.

3. **VERIFY Current State**
   Actually run these commands — do NOT fabricate results:
   - Run the build/compile command (from AGENTS.md ## Testing)
   - Run the test suite
   - Check `git status`
   
   Record EXACT output in the "Current state" section.

4. **RECORD Agent Attribution**
   Record which AI tool, version, and model made the changes.
   If available, record token usage and cost estimate.
   This enables accountability tracking and usage analysis.

5. **VERIFY Agent Compliance**
   Cross-check each rule in AGENTS.md Rules section against actual evidence:
   - Check git log: did I commit all state changes? (yes/no + evidence)
   - Check files: did I modify any files owned by DONE tasks? (yes/no + which files)
   - Check scope: did I stay within task boundary? (yes/no + deviations)
   - Check context: did I follow the context protocol? (yes/no + what was skipped)
   
   Be HONEST. Report violations. A violation + honest report is better than a fabricated claim.

6. **PRESENT REPORT**
   Present **Session State** per .acts/report-protocol.md
   Show the session summary sections you've written.

7. **VERIFY CLAIMS**
   Cross-check your session claims against actual work:
   - `git log --oneline` — do commits match "What was done"?
   - `git diff HEAD~N` — do changes match claimed work?
   - If discrepancy: correct the session file before committing

8. **GATE: approve**
   Say: "Session summary ready. Commit and push? (yes/no)"
   
   Wait for explicit confirmation before proceeding.
   If "no", address any concerns about the summary.

9. **Update state.json**
   - `updated_at` → now (ISO 8601)
   - `session_count` → increment by 1

10. **Commit**
    Stage all changes including the new session file.
    `docs(<story_id>): session summary by <developer> for <task_id>`

11. **Push**
    Push the branch to remote.

## Session File Format

```markdown
# Session Summary
- **Developer:** <developer>
- **Agent:** <tool + version + model> (e.g., "Cursor v0.45.0 (Claude-3.5-Sonnet)")
- **Agent Config:** <configuration preset> (e.g., "default-ruleset", "strict-mode")
- **Agent Model:** <model identifier> (optional, e.g., "claude-3.5-sonnet", "gpt-4-turbo")
- **Tokens Used:** <integer> (optional, if trackable)
- **Cost Estimate:** $<amount> (optional, if calculable)
- **Date:** <ISO 8601 datetime>
- **Task:** <task_id> — <title>

## What was done
- Concrete change 1
- Concrete change 2
...

## Decisions made
Rationale for architectural choices, trade-offs accepted.

## What was NOT done (and why)
Remaining work, blocked items, deferred to other tasks.

## Approaches tried and rejected
What was attempted, why it didn't work. (Critical for next developer)

## Open questions
Unresolved items for next developer to clarify.

## Current state
- Compiles: ✅/❌ <details if fail>
- Tests pass: ✅/❌ <passing/total>
- Uncommitted work: ✅/❌ <description>

## Files touched this session
- `path/to/file` — brief description of change

## Suggested next step
The single most useful thing to do when resuming.

## Agent Compliance (verified against actual work, don't just claim)
For each rule in AGENTS.md Rules section:
- Read state.json before writing code: ✅/❌ <evidence>
- Did not modify files owned by DONE tasks: ✅/❌ <which files if violated>
- Stayed within assigned task boundary: ✅/❌ <deviations if any>
- Followed context protocol: ✅/❌ <what was skipped if any>

Be HONEST. Report violations. A violation + honest report is better than a fabricated claim.
```

## Constraints

- Every section is REQUIRED. If empty, write "None".
- Never fabricate test results or build status.
- The agent compliance section must reflect reality.
- Always get approval via GATE before committing.
