---
operation_id: task-start
layer: 3
required: false
triggers: "none"
context_budget: 20000
execution:
  type: "cli"
  command: "task-start"
  timeout: 600
inputs_schema:
  task_id:
    type: string
    required: true
    validation: "^T\\d+$"
  action:
    type: string
    enum: ["start", "complete"]
    default: "start"
outputs_schema:
  task_id:
    type: string
  status:
    type: string
    enum: ["IN_PROGRESS", "DONE"]
  review_status:
    type: string
    enum: ["approved", "changes_requested"]
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
  - "Code follows AGENTS.md rules"
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

3. **GATE: approve**
   Say: "Ready to implement <task_id>? (yes/no)"

   Agent MUST stop here and wait for explicit "yes".
   Do NOT begin implementation until developer confirms.

4. **IMPLEMENT**
   Determine mode:
   - IF project has test framework configured in AGENTS.md → TDD mode
   - IF project has no tests or is config/docs → Direct mode

   TDD mode:
   a. Write ONE failing test for the behavior you need
   b. Run test, confirm it fails (RED)
   c. Write MINIMAL code to make test pass (GREEN)
   d. Run test, confirm it passes
   e. Refactor if obvious improvement exists
   f. Commit
   g. REPEAT for next behavior

   Direct mode (for configs, docs, untestable code):
   a. Make the change
   b. Verify it works (run command, check output)
   c. Commit
   d. REPEAT for next change

5. **COMMIT AFTER EACH BEHAVIOR**
   After completing one behavior (one test passes OR one change verified):
   `feat(<story_id>): <what you implemented>`

   Every commit must compile and pass existing tests.

   After EVERY commit:
   - Update `.story/tasks/<task_id>/notes.md` with: what changed, why, any decisions

   **In strict mode (conformance_level: "strict"):**
   After completing a logical batch of commits (1-5 commits):
   a. Run `commit-review` operation
   b. Present Commit Batch Report
   c. **GATE: commit-review** — wait for "approved" or "changes_requested"
   d. If "changes_requested": address feedback, then loop back
   e. If "approved": continue implementation

   The agent decides what constitutes a "batch":
   - Completing the model layer
   - Finishing an API endpoint
   - Writing tests for a component

   NOT every single commit (too much friction).
   NOT the entire task (defeats the purpose).

6. **CHECK FILE OWNERSHIP**
   For each file you're about to modify:
   a. Check if file is in `files_owned` by any DONE task
   b. IF yes AND file is in YOUR task's plan entry → you may modify, keep changes minimal
   c. IF yes AND file is NOT in your task → STOP. Say: "File {path} owned by {task_id}, not in my task. Should I proceed?"
   d. IF no (not owned): proceed freely

7. **ARCHITECTURE DECISIONS (strict mode)**
   In strict mode (conformance_level: "strict"):
   
   Before implementing any significant design decision:
   a. Run `architecture-discuss` operation
   b. Present Architecture Decision Report
   c. **GATE: architecture-discuss** — wait for approval
   d. If approved: implement
   e. If rejected: do NOT implement, note in task notes
   
   Trigger for:
   - New dependencies
   - New modules/services
   - API changes
   - Pattern changes (state machine, events, middleware)
   - Refactoring existing architecture
   - Technology switches
   
   Do NOT trigger for:
   - Implementation details within existing patterns
   - Bug fixes
   - Test additions
   - Minor refactorings

8. **MAINTAIN NOTES**
   Keep `.story/tasks/<task_id>/notes.md` updated:
   - Decisions made and rationale
   - Deviations from the plan and why
   - Open questions

9. **VERIFY COMPLETION**
   a. Verify all acceptance criteria from `plan.md` for this task.
   b. Run full test suite.
   c. Run linter/formatter.

10. **STAGE CHANGES**
    Stage all changes for review:
    ```
    git add .
    ```

11. **TASK-REVIEW GATE (HARD STOP)**
    If `code_review.enabled` is true in `.acts/acts.json`:
    a. Invoke task-review operation:
       ```bash
       echo '{"inputs": {"task_id": "T1"}}' | acts run task-review
       ```
    b. Parse output JSON for status field
    c. If status == "approved": proceed to step 12
    d. If status == "changes_requested":
       - Address feedback
       - Loop back to step 10

    If `code_review.enabled` is false:
    - Log: "Code review disabled — skipping task-review gate"
    - Proceed directly to step 12

12. **UPDATE STATE**
    Update `.story/state.json`:
    - Task status → `DONE`
    - `files_touched` → complete list of files created or modified

13. **COMMIT COMPLETION**
    `feat(<story_id>): complete <task_id> — <summary>`
    
    Note: Include reference to review file in commit body if applicable.

14. **SCOPE MONITORING** (run after EVERY commit, not just at end)
    After each commit, check:
    - Did I just implement something NOT in my task's acceptance criteria?
    - Did I add a new file NOT mentioned in the plan?
    - Did I change a pattern that affects other tasks?

    IF yes to any:
    - STOP committing that work
    - Create new task in plan.md and state.json with status TODO
    - Revert the out-of-scope changes
    - Tell developer: "Found out-of-scope work. Created task {new_id}."

## Constraints

- Stay within task boundary. No scope creep.
- Follow `AGENTS.md` patterns. Ask before deviating.
- Every commit must compile and pass tests.
- All gates are HARD STOPS — agent MUST NOT proceed without explicit confirmation.
- The task-review gate MUST be satisfied before task status changes to DONE.
- If code_review is disabled, the gate is skipped but the session summary MUST note this.
- In strict mode: commit-review and architecture-discuss gates are HARD STOPS.
- In strict mode: the agent MUST NOT silently implement architectural decisions.
