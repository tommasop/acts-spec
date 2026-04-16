---
operation_id: architecture-discuss
layer: 3
required: true
required_for: "strict"
triggers: "before implementing a significant design decision"
context_budget: 10000
required_inputs:
  - name: task_id
    type: string
    required: true
    validation: "^T\\d+$"
  - name: decision
    type: string
    required: true
    description: "Summary of the architectural decision"
optional_inputs: []
preconditions:
  - "Task status MUST be IN_PROGRESS"
  - "Agent has identified a design decision that affects architecture"
postconditions:
  - "Decision is approved, rejected, or alternative is agreed upon"
  - "If approved: agent implements the decision"
  - "If rejected: agent does NOT implement, notes in task notes"
---

# architecture-discuss

## Purpose

Before implementing a significant design decision, the agent presents
its reasoning and gets explicit human approval. The agent self-declares
what counts as "architectural."

**This operation is REQUIRED for ACTS Strict conformance.**

## Pre-check

If conformance level is NOT `strict` in `.acts/acts.json`:
- Skip this entire operation
- Agent implements without discussion gate

## What Counts as Architectural

The agent SHOULD trigger this gate for decisions like:
- Adding a new dependency (npm package, library, framework)
- Creating a new module or service layer
- Changing the public API of an existing module
- Introducing a new pattern (state machine, event system, middleware)
- Refactoring existing architecture
- Switching technologies (e.g., REST to GraphQL, polling to WebSockets)
- Database schema changes
- Authentication/authorization approach changes

The agent SHOULD NOT trigger this gate for:
- Implementation details within existing patterns
- Bug fixes
- Test additions
- Formatting/linting changes
- Minor refactorings that don't change public APIs

When in doubt, the agent SHOULD ask the developer: "This might be
architectural — should we discuss it first?"

## Steps

1. **IDENTIFY DECISION**
   Recognize that the current implementation step involves a design
   choice that affects project architecture.

2. **CLASSIFY SEVERITY**
   Based on impact, choose one:

   MINOR (add utility library, rename internal function):
   - Impact: 1-2 files
   - Reversible: yes
   - Risk: low
   - Gate: `acknowledge` (inform developer, proceed unless they stop you)

   MAJOR (new module, API change, pattern change):
   - Impact: 3-10 files
   - Reversible: difficult
   - Risk: medium
   - Gate: `architecture-discuss` (hard stop, wait for yes/no/different)

   CRITICAL (switch framework, DB migration, security change):
   - Impact: 10+ files or security-critical
   - Reversible: no
   - Risk: high
   - Gate: `architecture-discuss` (hard stop) + require written rationale

3. **PRESENT ARCHITECTURE DECISION REPORT**
   Include severity classification in the report.

   If MINOR: say "This is a minor decision — I'll proceed unless you object."
   If MAJOR: present full report, wait for approval.
   If CRITICAL: present full report + detailed rationale, wait for written approval.

4. **GATE**
   If MINOR: inform developer of the minor decision via `.acts/report-protocol.md`.
   Say: "Minor decision: <decision>. I'll proceed unless you object."
   Agent MAY proceed after brief notification unless developer objects.

   If MAJOR: present full report per .acts/report-protocol.md.
   Say: "I want to discuss: <decision>. Approve? (yes/no/different)"
   Agent MUST stop here and wait for explicit response.

   If CRITICAL: present full report + written rationale.
   Say: "CRITICAL decision: <decision>. Rationale: <details>. Written approval required."
   Agent MUST stop here and wait for explicit written approval.

5. **HANDLE RESPONSE**
   If "yes":
   - Proceed with implementation
   - Note the approved decision in `.story/tasks/<task_id>/notes.md`

   If "no":
   - Do NOT implement the proposed approach
   - Note the rejection in `.story/tasks/<task_id>/notes.md`
   - Ask developer what they'd prefer instead

   If "different" or alternative proposed:
   - Discuss the alternative
   - If agreeable, update approach and LOOP back to step 3
   - If not agreeable, continue discussion

## Constraints

- MINOR decisions: inform and proceed — no hard gate, but developer may stop you.
- MAJOR/CRITICAL decisions: HARD GATE — agent MUST stop and wait.
- CRITICAL decisions require written rationale and written approval.
- There are no timeouts.
- The agent MUST classify severity BEFORE implementing.
- The agent SHOULD err on the side of discussing rather than implementing silently.
- Rejected decisions MUST be documented in task notes.
- This gate is about DESIGN decisions, not implementation details.
