---
operation_id: story-discover
layer: 3
required: false
triggers: "story-init with no story_id or source"
context_budget: 15000
required_inputs: []
optional_inputs:
  - name: initial_idea
    type: string
    description: "Optional seed idea from developer (e.g., 'user authentication')"
preconditions:
  - ".story/ directory MUST NOT exist"
  - "No story currently in ANALYSIS or later"
postconditions:
  - ".story/draft-spec.md exists with proposed specification"
  - "No state.json created (not a real story yet)"
  - "draft-spec is ephemeral (not committed)"
---

# story-discover

## Purpose

Interactive discovery phase that runs when no story is given. Through
structured interview, the agent helps the developer clarify what needs
to be built, then drafts a specification for team review.

The draft spec is ephemeral — it lives only in `.story/draft-spec.md`
and is not tracked in git or state.json. Once the team approves it,
a real story is created via `story-init --from-draft`.

## Pre-check

IF `.story/state.json` exists:
- Say: "A story already exists. Use `story-init --from-draft` to create
  a story from an existing draft, or delete .story/ to start fresh."
- STOP.

## Steps

1. **ACKNOWLEDGE BLANK SLATE**
   Say: "No story_id or source material provided. Starting discovery mode.
   I'll help you clarify what needs to be built through a few questions."

2. **PROBLEM EXPLORATION**
   Ask (one at a time, wait for response):
   
   a. "What problem are you trying to solve?"
      - Listen for: pain point, opportunity, constraint
   
   b. "Who has this problem?"
      - Listen for: users, systems, stakeholders
   
   c. "Why is this important now?"
      - Listen for: urgency, dependencies, business value
   
   d. "What does success look like?"
      - Listen for: outcomes, metrics, done criteria

3. **CONTEXT GATHERING**
   Based on the problem description:
   - Search codebase for related files/modules
   - Read relevant existing code
   - Check for existing issues, TODOs, or similar features
   - Look at AGENTS.md for relevant architecture patterns
   
   Summarize: "Based on the codebase, I see..."

4. **CONSTRAINT IDENTIFICATION**
   Ask:
   
   a. "What must be included? (hard requirements)"
   b. "What should definitely NOT be included? (out of scope)"
   c. "Are there any technical constraints or preferences?"
   d. "What are you unsure about? (open questions)"

5. **DRAFT SPECIFICATION**
   Create `.story/` directory structure (but NOT state.json):
   ```
   .story/
   └── draft-spec.md
   ```
   
   Write `.story/draft-spec.md`:
   
   ```markdown
   # Draft Specification
   
   > **Status:** Draft — awaiting team review
   > **Created:** <ISO 8601 timestamp>
   > **Source:** Discovery interview
   
   ## Problem Statement
   
   <What problem, who has it, why now — from step 2>
   
   ## Proposed Solution
   
   <What should be built at a high level>
   
   ## Acceptance Criteria (Draft)
   
   1. <Criterion 1 — testable>
   2. <Criterion 2 — testable>
   3. <Criterion 3 — testable>
   
   ## Technical Notes
   
   <Relevant architecture from AGENTS.md>
   <Existing code that might be affected>
   <Technical constraints from step 4>
   
   ## Out of Scope
   
   - <Item 1>
   - <Item 2>
   
   ## Open Questions
   
   - <Question 1>?
   - <Question 2>?
   
   ## Suggested Story ID
   
   <PROJ-XXX or other suggested identifier>
   ```

6. **PRESENT DRAFT**
   Present the draft spec:
   - Goal summary (1 sentence)
   - Key acceptance criteria (3-5 items)
   - Out of scope items
   - Open questions needing answers
   
   Say: "This is a DRAFT for team review. It has NOT been committed
   and is NOT a real ACTS story yet."

7. **GATE: approve-for-review**
   Say: "Ready to share this draft with your team for review?
   (yes/no/iterate)"
   
   Agent MUST stop here and wait for response.
   
   IF "no" or "iterate":
   - Ask: "What should change?"
   - Update `.story/draft-spec.md` with changes
   - Loop back to step 6
   
   IF "yes":
   - Say: "Draft saved to .story/draft-spec.md"
   - Give instructions for next steps (step 8)

8. **INSTRUCT TEAM REVIEW**
   Say:
   """
   Next steps:
   
   1. Share .story/draft-spec.md with your team
   2. Iterate on the draft (edit directly or re-run discovery)
   3. When ready, create the real story:
   
      story-init <story_id> --from-draft
   
   This will:
   - Move draft-spec.md → spec.md
   - Initialize state.json
   - Create plan.md
   - Commit to git
   
   The draft is ephemeral — if you delete .story/, it's gone.
   """

## Constraints

- Do NOT create state.json during discovery.
- Do NOT commit draft-spec.md to git.
- Do NOT write any application code.
- The draft is a PROPOSAL, not a contract.
- Team must explicitly approve before it becomes a real story.
- This is a HARD GATE at step 7 — agent MUST wait for response.
- If developer abandons discovery (says "cancel"), clean up .story/ draft.
