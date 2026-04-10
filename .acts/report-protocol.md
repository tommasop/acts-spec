# ACTS Report Protocol

Standard report formats for human-in-the-loop gates in ACTS operations.

When an operation needs to present information to a human before proceeding, use these formats. The formats are designed for terminal display — readable, aligned, and concise.

---

## Report: Story Board

**Used in:** preflight, handoff, story-review

**Purpose:** Show current story state and task overview.

**Format:**

```
┌─────────────────────────────────────────────────────────┐
│  <STORY_ID> — <Title>                                   │
│  Status: <STATUS>  |  Updated: <timestamp>              │
├──────┬──────────────┬──────────────┬──────┬─────────────┤
│ Task │ Status       │ Assigned     │ Pri  │ Title       │
├──────┼──────────────┼──────────────┼──────┼─────────────┤
│ T1   │ DONE         │ alice        │ 1    │ ...         │
│ T2   │ IN_PROGRESS  │ bob          │ 1    │ ...         │
│ T3   │ TODO         │ —            │ 2    │ ...         │
└──────┴──────────────┴──────────────┴──────┴─────────────┘
```

**Fields:**
- Task: Task ID (T<n>)
- Status: TODO, IN_PROGRESS, BLOCKED, DONE
- Assigned: Developer name or "—" if unassigned
- Pri: Context priority (1-5, where 1=critical)
- Title: First 30 chars of task title

---

## Report: Ownership Map

**Used in:** preflight, handoff

**Purpose:** Show which files are owned by completed tasks to prevent unauthorized modification.

**Format:**

```
File                              → Owner    Status
──────────────────────────────────┼──────────┼──────────
src/routes/totp.ts                → T1       DONE
src/services/totp.ts              → T1       DONE
src/components/TwoFactorSetup.tsx → T3       TODO
```

**Rules:**
- List ALL files from tasks with status DONE
- Include files from IN_PROGRESS tasks by OTHER developers
- Sort alphabetically by file path
- If no files owned: "No completed tasks with file ownership."

---

## Report: Scope Declaration

**Used in:** preflight, task-start

**Purpose:** State what the agent will and will not do for this task.

**Format:**

```
┌─────────────────────────────────────────────────────────┐
│  Scope Declaration: <task_id> — <title>                 │
├─────────────────────────────────────────────────────────┤
│  I WILL do:                                             │
│    • <concrete action 1>                                │
│    • <concrete action 2>                                │
│    • <concrete action 3>                                │
│                                                         │
│  I will NOT do:                                         │
│    • <scope exclusion 1>                                │
│    • <scope exclusion 2>                                │
│                                                         │
│  Files I may modify:                                    │
│    • <file 1> — <reason>                                │
│    • <file 2> — <reason>                                │
└─────────────────────────────────────────────────────────┘
```

**Rules:**
- "I WILL" items from `.story/plan.md` task entry
- "I will NOT" explicitly lists out-of-scope items
- "Files I may modify" only lists files mentioned in the plan OR owned by this task's dependencies (if any)
- If modifying a file owned by a DONE task, note: "(requires explicit approval)"

---

## Report: Session State

**Used in:** session-summary

**Purpose:** Verify and report current repository state.

**Format:**

```
┌─────────────────────────────────────────────────────────┐
│  Session State Verification                             │
├─────────────────────────────────────────────────────────┤
│  Build/Compile:  ✅ <N>/<N> modules compiled            │
│                  ❌ <failures> errors                   │
│                                                         │
│  Tests:          ✅ <passing>/<total> passing           │
│                  ❌ <failing> failing                   │
│                                                         │
│  Lint/Format:    ✅ clean                               │
│                  ❌ <N> issues                          │
│                                                         │
│  Git Status:     ✅ clean (no uncommitted changes)      │
│                  ⚠️  <N> files modified                │
│                  ❌ <N> files staged, <N> untracked    │
└─────────────────────────────────────────────────────────┘
```

**Rules:**
- Run ACTUAL commands — do not fabricate
- Report exact output (pass/fail counts, not just ✅)
- If any check fails, note it explicitly in "What was NOT done"
- Use project-specific commands from AGENTS.md ## Testing section

---

## Report: Code Review

**Used in:** task-review, commit-review

**Purpose:** Show staged changes and review interface status before task completion.

**Format:**

```
┌─────────────────────────────────────────────────────────┐
│  Code Review: T1 — Add TOTP setup endpoint              │
├─────────────────────────────────────────────────────────┤
│  Files Changed: 3                                       │
│    • src/services/totp.ts (+45, -0)                     │
│    • src/routes/totp.ts (+28, -0)                       │
│    • src/routes/totp.test.ts (+67, -0)                  │
│                                                         │
│  Test Results: ✅ 12/12 passing                         │
│  Lint Results: ✅ clean                                 │
│                                                         │
│  Review Interface: critique                              │
│  Command: bunx critique --staged                        │
│                                                         │
│  ⚠️  Action Required: Review staged changes             │
│      Add inline comments if needed                      │
│      Then approve or request changes                    │
└─────────────────────────────────────────────────────────┘
```

**Fields:**
- Files Changed: List of staged files with line stats
- Test Results: Pass/fail count
- Lint Results: Clean or issues count
- Review Interface: Provider name (critique)
- Command: CLI command to launch review

---

## Gate Types

All gates in ACTS are **HARD STOPS**. The agent MUST stop execution and wait for explicit human confirmation. There are no timeouts — the agent waits indefinitely.

When presenting reports, use these gate patterns:

### GATE: approve

**Use when:** State will change, significant action about to happen

**Agent behavior:**
1. Present all relevant reports
2. Say: "Ready to proceed? (yes/no)"
3. **STOP ALL EXECUTION** — do not take any further action
4. Wait for explicit "yes" or "proceed"
5. If "no" or silence: address concerns, re-present
6. Only proceed after receiving the expected confirmation

**Used in:** preflight (after context), session-summary (before commit), handoff (before reassignment), story-review (before transition)

### GATE: task-review

**Use when:** Code review via external tool (e.g., critique) required before task completion

**Agent behavior:**
1. Check if `code_review.enabled` is true in `.acts/acts.json`
2. If disabled: skip this gate entirely, log in session summary
3. If enabled:
   - Run the review tool (e.g., `bunx critique --staged`)
   - The tool opens in the terminal — human reviews diffs interactively
   - **STOP ALL EXECUTION** — do not take any further action
   - Wait for the tool to exit and capture structured Markdown output
4. If output indicates `approved`:
   - Save output to `.story/reviews/active/`
   - Proceed
5. If output indicates `changes_requested`:
   - Parse comments from the output
   - Present comments to developer
   - Agent addresses concerns
   - Re-stage changes
   - LOOP back to step 1
6. If other response: ask for clarification, keep waiting

**Used in:** task-review (implicit at task completion)

---

## Implementation Notes

**For agents:**
- Always use the exact format specified — humans recognize these reports
- Never skip a gate when the operation specifies one
- Present reports in the order defined in the operation
- Keep terminal width ≤ 80 chars for compatibility

**For operations:**
- Reference this file: "Present Story Board per .acts/report-protocol.md"
- Don't invent new report formats — extend this file if needed
- Gate type must be explicit: "GATE: approve" or "GATE: task-review"

---

## Example Operation Integration

```markdown
## Steps

6. **CONTEXT INGESTION**
   Follow the Context Protocol (§5.2).

   ### Report
   Present **Story Board** per .acts/report-protocol.md
   Present **Ownership Map** showing files owned by DONE tasks
   Present **Scope Declaration** for this task

   ### Gate
   GATE: approve
   "Ready to proceed with <task_id>? (yes/no)"
   Do NOT update state.json until developer confirms.
```
