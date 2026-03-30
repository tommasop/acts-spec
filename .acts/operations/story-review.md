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
   Read `.story/spec.md`. For each acceptance criterion:
   - Find the code and/or test that satisfies it.
   - Mark it ✅ with a reference (file + function/test name).
   - If a criterion is NOT met, mark it ❌ and STOP.
     Create a new task in plan.md and state.json for the gap.

3. **RUN FULL TEST SUITE**
   Execute all tests. Report exact results (passing/total).

4. **RUN FORMATTER/LINTER**
   Report results.

5. **CONSTITUTION COMPLIANCE CHECK**
   - All public functions have documentation/types?
   - No forbidden patterns (per `AGENT.md ## Forbidden`)?
   - Commit messages follow conventions (per `AGENT.md ## Git`)?
   - File length limits respected?

6. **AGENT COMPLIANCE AUDIT**
   Read all session summaries. Check Agent Compliance sections.
   Report patterns:
   - "All sessions reported full compliance"
   - "3/7 sessions skipped context protocol step 6"
   - etc.

7. **GENERATE PR DESCRIPTION**

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

8. **PRESENT REPORTS**
   Present **Story Board** showing all tasks DONE
   Present acceptance criteria checklist (✅/❌ per AC)
   Present PR description
   Present agent compliance audit summary

9. **GATE: approve**
   Say: "Story review complete. <N>/<N> acceptance criteria met.
   Tests: <passing>/<total>. Ready to transition to REVIEW? (yes/no)"
   
   If ANY criterion is unmet, do NOT offer this gate.
   Instead say: "Fix the gaps above, then re-run story-review."
   
   Wait for explicit confirmation before proceeding.

10. **UPDATE STATE**
    - Story status → `REVIEW`
    - `updated_at` → now

11. **COMMIT**
    `docs(<story_id>): story review complete`

12. **TRIGGER LAYER 4** (optional)
    Suggest running:
    - `changelog` (if configured)
    - `tracker-sync` with full summary
    - `newsletter`

## Constraints

- If ANY criterion is unmet, do NOT transition to `REVIEW`.
- The PR description MUST be written for human reviewers, not agents.
- The agent compliance audit is observational, not blocking.
- The gate (step 9) MUST be respected.
