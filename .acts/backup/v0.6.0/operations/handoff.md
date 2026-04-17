---
operation_id: handoff
layer: 3
required: true
triggers: "none (reassignment)"
context_budget: 100000
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
  - name: new_developer
    type: string
    required: true
optional_inputs: []
preconditions:
  - ".story/state.json MUST exist"
  - "Task SHOULD be IN_PROGRESS (by someone else) or TODO"
postconditions:
  - "New developer has full context from all prior sessions"
  - "Task is reassigned in state.json"
  - "No code has been written"
---

# handoff

## Purpose

Enable a new developer to take over a task with full context. Combines
preflight validation with deep context ingestion from all prior
sessions.

## Steps

1. **RUN PREFLIGHT**
   Execute the preflight operation (§5.6) for `task_id` with
   `new_developer` as the developer. This validates state and
   performs context ingestion.

2. **DETERMINE HANDOFF MODE**
   IF same team (developer already knows the codebase): use LIGHTWEIGHT
   IF different team OR new developer OR complex task: use FULL
   If unsure, ask: "Lightweight or full handoff?"

3. **CONTEXT INGESTION**

   LIGHTWEIGHT mode:
   - Read: this task's latest session summary (if any)
   - Read: files in `files_touched` for this task
   - Read: git log for this task branch (last 10 commits)
   - Token budget: ~10k

   FULL mode:
   - Read: ALL session summaries for this task (chronological order)
   - Read: ALL session summaries for dependency tasks
   - Read: files in `files_touched` for this task AND dependencies
   - Read: git log for this task branch (all commits)
   - Token budget: ~100k

4. **PRODUCE HANDOFF BRIEFING**
   Create a comprehensive briefing:

   ```markdown
   ## Handoff Briefing: <task_id>

   ### Context
   What this task is about, where it fits in the story.

   ### Previous work
   What was done, by whom, when — per session.

   ### Current code state
   Summary of what exists: files, functions, patterns used.

   ### Remaining work
   Specific items left to implement, derived from plan + sessions.

   ### Pitfalls to avoid
   From "approaches tried and rejected" across all sessions.

   ### Open questions
   Aggregated from all sessions.

   ### Files to review
   Prioritized list: most important first, with reason.

   ### Context ingestion report
   - Sessions read: <count, list>
   - Files read: <count>
   - Estimated tokens used: <count>
   ```

5. **PRESENT REPORTS**
   Present **Story Board** per .acts/report-protocol.md
   Present **Ownership Map** showing current file ownership
   Present the handoff briefing from step 3

6. **GATE: approve**
   Say: "Handoff briefing complete. Ready to reassign <task_id> to
   <new_developer>? (yes/no)"
   
   Agent MUST stop here and wait for explicit "yes".
   
   Say: "Want me to start implementing, or do you have questions first?"
   
   Do NOT write code until the new developer explicitly says to proceed.

7. **REASSIGN**
   Update `.story/state.json`:
   - Task `assigned_to` → `new_developer`
   - `updated_at` → now

8. **COMMIT**
   `chore(<story_id>): handoff <task_id> to <new_developer>`

## Constraints

- MUST NOT begin coding until the new developer explicitly confirms.
- The briefing MUST include the "Pitfalls to avoid" section even if
  empty — write "None reported" in that case.
- If there are zero prior sessions (fresh TODO), note "No prior work
  on this task" in the briefing.
