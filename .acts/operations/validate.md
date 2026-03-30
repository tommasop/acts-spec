---
operation_id: validate
layer: 3
required: false
triggers: "none"
context_budget: 20000
required_inputs: []
optional_inputs:
  - name: layer
    type: integer
    required: false
    description: "Validate specific layer only (1, 2, or 3). Default: all."
postconditions:
  - "Validation results presented to user"
  - "No files modified"
---

# validate

## Purpose

Run ACTS conformance validation interactively. This is the agent-
executed version of `scripts/validate.sh` for use when a developer
wants to check conformance without running CI.

## Steps

1. **CHECK LAYER 1: Constitution**
   - AGENTS.md exists at repo root
   - Contains required sections: ## Rules, ## Architecture, ## Style,
     ## Testing, ## Git, ## Forbidden
   - Rules section contains 4 required directives

2. **CHECK LAYER 2: State**
   - .story/ directory exists
   - state.json exists and is valid JSON
   - spec.md exists
   - plan.md exists
   - sessions/ directory exists
   - State fields: acts_version, story_id, title, status, spec_approved,
     created_at, updated_at, context_budget, tasks
   - Task IDs match pattern T<N>
   - Task statuses valid
   - Task IDs match plan.md
   - No DONE tasks with empty files_touched
   - No IN_PROGRESS tasks without assignee
   - session_count matches actual files
   - Session files follow naming convention

3. **CHECK LAYER 3: Operations**
   - .acts/ directory exists
   - acts.json manifest exists
   - schemas/ directory exists (all 4 schemas)
   - Required operations exist: story-init, preflight, session-summary,
     handoff, story-review
   - Each operation has YAML frontmatter with: operation_id, layer,
     required, triggers, context_budget, preconditions, postconditions
   - operation_id matches filename
   - Each operation has ## Purpose, ## Steps, ## Constraints
   - preflight and handoff have ## Context Protocol

4. **PRESENT RESULTS**
   Show validation checklist with ✅/❌ for each check.
   
   Format:
   ```
   ACTS Conformance Validation
   ═══════════════════════════
   
   Layer 1: Constitution
   ───────────────────────
     ✅ AGENTS.md exists
     ✅ Required sections present
     ...
   
   Layer 2: State
   ─────────────────
     ✅ state.json valid
     ...
   
   ───────────────────────────
   Results: 42 passed, 0 failed
   
   🏆 Conformance: FULL
   ```

5. **SUMMARIZE**
   If all checks pass: "All conformance checks passed."
   If any fail: "Fix the issues above, then re-run validate."

## Constraints

- This is a read-only operation — never modify files.
- Present results in a format similar to scripts/validate.sh.
- If specific layer requested, only check that layer.
