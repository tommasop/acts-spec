---
operation_id: task-start
layer: 3
required: false
triggers: "none"
context_budget: 20000
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
optional_inputs: []
preconditions:
  - "preflight MUST have been run in this session for the target task"
  - "Task status MUST be IN_PROGRESS assigned to the current developer"
postconditions:
  - "Task acceptance criteria are met"
  - "All new public functions have documentation/types"
  - "Tests pass"
  - "Code follows AGENT.md rules"
  - "files_touched accurately reflects all modified files"
---

# task-start

## Purpose

Execute the implementation of a task following the plan, the
constitution, and TDD principles.

## Steps

1. **RE-READ TASK**
   Read this task's entry from `.story/plan.md`.

2. **PRESENT SCOPE**
   Present **Scope Declaration** per .acts/report-protocol.md
   Re-state what you will do from the plan.

3. **GATE: acknowledge**
   Say: "Ready to implement <task_id>. Scope confirmed above.
   Continue when ready."
   
   Wait for any response, then proceed.

4. **IMPLEMENT (TDD loop)**
   When the language/framework supports it:
   a. Write a failing test.
   b. Write the minimal code to make it pass.
   c. Refactor.
   d. Repeat.

5. **COMMIT REGULARLY**
   After each meaningful unit of work:
   `feat(<story_id>): <description>`
   
   Every commit must compile and pass existing tests.

6. **CHECK FILE OWNERSHIP**
   If you need to modify a file owned by a DONE task:
   - Check the plan — does your task explicitly mention this file?
   - If yes: proceed surgically.
   - If no: STOP. Ask the developer. If approved, note the deviation
     in `.story/tasks/<task_id>/notes.md`.

7. **MAINTAIN NOTES**
   Keep `.story/tasks/<task_id>/notes.md` updated:
   - Decisions made and rationale
   - Deviations from the plan and why
   - Open questions

8. **VERIFY COMPLETION**
   a. Verify all acceptance criteria from `plan.md` for this task.
   b. Run full test suite.
   c. Run linter/formatter.

9. **STAGE CHANGES**
   Stage all changes for review:
   ```
   git add .
   ```

10. **CODE REVIEW GATE (task-review)**
    If code review is enabled:
    - Run `task-review` operation
    - Present Code Review report
    - Start review server (GitHuman)
    - Wait for approval
    - If changes_requested: address and loop back
    - Export review to `.story/reviews/active/`
    
    If code review is disabled:
    - Log: "Code review disabled — proceeding without review"

11. **UPDATE STATE**
    Update `.story/state.json`:
    - Task status → `DONE`
    - `files_touched` → complete list of files created or modified

12. **COMMIT COMPLETION**
    `feat(<story_id>): complete <task_id> — <summary>`
    
    Note: Include reference to review file in commit body if applicable.

11. **SCOPE ESCAPE CHECK**
    If you discovered work outside your task scope:
    - Do NOT do it.
    - Add a new task to `plan.md` and `state.json` with status `TODO`.
    - Tell the developer.

## Constraints

- Stay within task boundary. No scope creep.
- Follow `AGENT.md` patterns. Ask before deviating.
- Every commit must compile and pass tests.
- Use the gate before starting implementation.
