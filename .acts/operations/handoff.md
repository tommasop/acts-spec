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

2. **DEEP CONTEXT INGESTION**
   a. Read ALL session summaries in `.story/sessions/` that reference
      this `task_id`, in chronological order.
   b. Read ALL session summaries for dependency tasks.
   c. Read ALL files in `files_touched` for this task (partial work).
   d. Read ALL files in `files_touched` for completed dependency tasks.
   e. Read the git log for task branch `story/<STORY_ID>/<TASK_ID>` to
      show what commits exist.

3. **PRODUCE HANDOFF BRIEFING**
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

4. **PRESENT REPORTS**
   Present **Story Board** per .acts/report-protocol.md
   Present **Ownership Map** showing current file ownership
   Present the handoff briefing from step 3

5. **GATE: approve**
   Say: "Handoff briefing complete. Ready to reassign <task_id> to
   <new_developer>? (yes/no)"
   
   Agent MUST stop here and wait for explicit "yes".
   
   Say: "Want me to start implementing, or do you have questions first?"
   
   Do NOT write code until the new developer explicitly says to proceed.

6. **REASSIGN**
   Update `.story/state.json`:
   - Task `assigned_to` → `new_developer`
   - `updated_at` → now

7. **COMMIT**
   `chore(<story_id>): handoff <task_id> to <new_developer>`

## Constraints

- MUST NOT begin coding until the new developer explicitly confirms.
- The briefing MUST include the "Pitfalls to avoid" section even if
  empty — write "None reported" in that case.
- If there are zero prior sessions (fresh TODO), note "No prior work
  on this task" in the briefing.
