---
operation_id: story-review
layer: 3
required: true
triggers: "IN_PROGRESS → REVIEW"
context_budget: 50000
required_inputs: []
optional_inputs: []
preconditions:
  - "ALL tasks in state.json MUST have status DONE"
  - "Story status MUST be IN_PROGRESS"
postconditions:
  - "Every acceptance criterion is verified against code"
  - "Tests pass"
  - "Constitution compliance verified"
  - "Story status is REVIEW"
---

# story-review

## Purpose

Final validation when all tasks are complete. Checks every acceptance
criterion against the implementation, runs the test suite, validates
constitution compliance, and prepares a PR description.

## Steps

1. **VERIFY ALL TASKS DONE**
   If any task is not `DONE`, list the incomplete tasks and STOP.
   Say: "Cannot review — incomplete tasks: <list>"

2. **ACCEPTANCE CRITERIA CHECK**
   For each acceptance criterion in `.story/spec.md`:
   a. Search test files for test name matching the AC description
      (e.g., AC "user can log in with email" → look for test named 
      something like "test_user_can_log_in_with_email" or "login")
   b. IF test found: run it, record pass/fail
   c. IF no test found: mark WARNING (not failure), note "No automated test"
   
   Present as table:
   | AC | Test Name | Status |
   |----|-----------|--------|
   | ... | ... | ✅ pass / ❌ fail / ⚠️ no test |
   
   BLOCK story completion IF:
   - Any AC has a test and test FAILS
   
   WARN (don't block) IF:
   - Any AC has no matching test

3. **RUN FULL TEST SUITE**
   Execute all tests. Report exact results (passing/total).

4. **RUN FORMATTER/LINTER**
   Report results.

5. **CONSTITUTION COMPLIANCE CHECK**
   - All public functions have documentation/types?
   - No forbidden patterns (per `AGENTS.md ## Forbidden`)?
   - Commit messages follow conventions (per `AGENTS.md ## Git`)?
   - File length limits respected?

6. **REVIEW VERIFICATION**
   For each task with status `DONE`:
   - Check `.story/reviews/archive/` for a corresponding review file
   - If a review file exists → mark ✅
   - If NO review file AND `code_review.enabled` was true → ❌ STOP.
     Create a new task to retroactively review the code.
   - If NO review file AND `code_review.enabled` was false → ✅ (review was skipped)

7. **AGENT COMPLIANCE AUDIT**
   Read all session summaries. Check Agent Compliance sections.
   Report patterns:
   - "All sessions reported full compliance"
   - "3/7 sessions skipped context protocol step 6"
   - etc.

8. **GENERATE PR DESCRIPTION**

   ```markdown
   ## <story_id> — <title>

   ### Summary
   What this story delivers, user perspective.

   ### Changes
   Per-task summary with key files.

   ### Testing
   Tests added/modified, how to verify manually.

   ### Notes for reviewers
   Key decisions, trade-offs, links to task notes.
   ```

9. **PRESENT REPORTS**
   Present **Story Board** showing all tasks DONE
   Present acceptance criteria checklist (✅/❌ per AC)
   Present review verification results (✅/❌ per task)
   Present PR description
   Present agent compliance audit summary

10. **GATE: approve**
    Say: "Story review complete. <N>/<N> acceptance criteria met.
    Tests: <passing>/<total>. All tasks reviewed: yes/no.
    Ready to transition to REVIEW? (yes/no)"
    
    If ANY criterion is unmet, do NOT offer this gate.
    Instead say: "Fix the gaps above, then re-run story-review."
    
    Agent MUST stop here and wait for explicit "yes".

11. **UPDATE STATE**
    - Story status → `REVIEW`
    - `updated_at` → now

12. **COMMIT**
    `docs(<story_id>): story review complete`

13. **TRIGGER LAYER 4** (optional)
    Suggest running:
    - `changelog` (if configured)
    - `tracker-sync` with full summary
    - `newsletter`

## Constraints

- If ANY criterion is unmet, do NOT transition to `REVIEW`.
- The PR description MUST be written for human reviewers, not agents.
- The agent compliance audit is observational, not blocking.
- The review verification (step 6) is BLOCKING — if code review was enabled and a task has no review file, STOP.
- The gate (step 10) is a HARD STOP — agent MUST wait for explicit "yes".
