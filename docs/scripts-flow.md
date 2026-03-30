# ACTS Development Flow — Agent-Executed with Gates

A step-by-step walkthrough of two developers collaborating on a story
using agent-loaded operations with human approval gates. Shows every
interaction from bootstrap to PR merge.

**Story:** PROJ-305 — "Add Two-Factor Authentication"
**Team:** alice (frontend), bob (backend)
**Tool:** OpenCode with ACTS skills

---

## Step 0: Bootstrap ACTS (one-time)

The team bootstraps ACTS. The agent generates configuration:

```
User: Set up ACTS for this project with OpenCode integration

Agent: Generates OpenCode skills and plugin:
  ✅ acts-story-init skill
  ✅ acts-preflight skill
  ✅ acts-task-start skill
  ✅ acts-session-summary skill
  ✅ acts-handoff skill
  ✅ acts-story-review skill
  ✅ acts-compress-sessions skill
  ✅ acts plugin for session lifecycle
  ✅ AGENTS.md with ACTS workflow

User: Run ACTS validation

Agent: Loading acts-validate...
  ACTS Conformance Validation
  ═══════════════════════════
  
  Layer 1: Constitution
  ───────────────────────
    ✅ AGENT.md exists at repo root
    ✅ Required sections present
    ...
  
  Layer 2: State
  ─────────────────
    ❌ .story/ directory exists (expected — no story yet)
  
  Results: 18 passed, 2 failed (expected)
```

---

## Step 1: Initialize Story (alice, Monday 09:00)

Alice starts OpenCode and tells the agent:

```
User: Initialize ACTS tracker for PROJ-305, title "Add Two-Factor 
Authentication", source [pastes Jira description]

Agent: Loading acts-story-init...
  Reading source material...
  Writing spec.md with goal, acceptance criteria, technical decisions...
  Writing plan.md with 6 tasks (T1-T6)...
  Creating state.json...
  
  ### Summary
  Story: PROJ-305 — Add Two-Factor Authentication
  Tasks: 6 (T1: TOTP setup, T2: TOTP verify, T3: 2FA UI setup, 
        T4: 2FA UI verify, T5: Login enforcement, T6: Recovery codes)
  Dependencies: T3→T1, T4→T2, T5→T3+T4, T6→T5
  
  ### Gate: acknowledge
  "Tracker initialized. Review spec.md and plan.md with your team
  before proceeding. Set spec_approved: true when ready.
  Continue when ready."

User: [presses enter]

Agent: Committing: docs(PROJ-305): initialize ACTS tracker
```

---

## Step 2: Team Reviews Spec (Monday 14:00)

Team reviews in PR. Bob suggests changes. Alice updates. Team approves.

Alice (or agent) sets `spec_approved: true` in state.json.

---

## Step 3: Bob Preflights T1 (Monday 15:00)

Bob starts work on backend:

```
User: Start working on T1. I'm bob.

Agent: Loading acts-preflight...
  Reading AGENT.md...
  Reading state.json...
  Validating: Story APPROVED ✓
  Validating: Task T1 TODO ✓
  Validating: No dependencies ✓
  Context ingestion (50000 tokens):
    ✓ AGENT.md
    ✓ state.json
    ✓ plan.md
    ✓ T1 plan entry
    - No completed tasks to read
  
  ### Story Board
  ┌─────────────────────────────────────────────────────────┐
  │  PROJ-305 — Add Two-Factor Authentication               │
  │  Status: APPROVED → will move to IN_PROGRESS            │
  ├──────┬──────────────┬──────────────┬──────┬─────────────┤
  │ Task │ Status       │ Assigned     │ Pri  │ Title       │
  ├──────┼──────────────┼──────────────┼──────┼─────────────┤
  │ T1   │ TODO         │ —            │ 1    │ TOTP setup  │
  │ T2   │ TODO         │ —            │ 1    │ TOTP verify │
  │ T3   │ TODO         │ —            │ 2    │ 2FA UI      │
  └──────┴──────────────┴──────────────┴──────┴─────────────┘
  
  ### Ownership Map
  No completed tasks with file ownership.
  
  ### Scope Declaration
  I WILL do:
    • Build TOTP setup endpoint (src/routes/totp.ts)
    • Implement TOTP secret generation
    • Write integration tests
  
  I will NOT do:
    • Touch frontend files (T3 scope)
    • Build verify endpoint (T2 scope)
  
  Files I may modify:
    • src/routes/totp.ts — new endpoint
    • src/services/totp.ts — TOTP service
    • src/routes/totp.test.ts — tests
  
  Context used: 12,450 / 50,000 tokens
  
  ### Gate: approve
  "Ready to proceed with T1? (yes/no)"

User: yes

Agent: Updating state.json... T1 → IN_PROGRESS, assigned_to: bob
  Committing: chore(PROJ-305): preflight T1 by bob
  Ready to implement T1.
```

---

## Step 4: Alice Preflights T3 (Monday 15:30)

Alice works on frontend in parallel:

```
User: Start working on T3. I'm alice.

Agent: Loading acts-preflight...
  ...
  Validating: Task T3 TODO ✓
  ⚠️  Dependency T1: IN_PROGRESS (not DONE)
  
  ⚠️  Warning: T1 is in progress by bob. Ensure you're in a 
      separate worktree or confirm with bob.
  
  ### Story Board
  [shows T1 IN_PROGRESS bob, T3 TODO]
  
  ### Scope Declaration
  I WILL: Build 2FA setup UI component
  I will NOT: Touch backend (T1/T2 scope)
  
  ### Gate: approve
  "Ready to proceed with T3? T1 is still in progress. (yes/no)"

User: yes

Agent: [updates state, commits preflight]
```

---

## Step 5: Parallel Implementation (Monday 16:00–18:00)

Both developers work. Agents handle implementation via task-start.

### Bob implements T1:

```
Agent: Loading acts-task-start...
  ### Scope Confirmation
  Building TOTP setup endpoint...
  
  ### Gate: acknowledge
  "Ready to implement T1. Scope confirmed above. Continue?"

User: [presses enter]

Agent: [implements with TDD]
  ✅ src/services/totp.ts created
  ✅ src/routes/totp.ts created
  ✅ Tests written
  ✅ All tests passing
  
  Updating state.json: T1 → DONE
  Committing: feat(PROJ-305): complete T1 — TOTP setup endpoint
```

### Alice implements T3:

```
Agent: [similar flow]
  ✅ src/components/TwoFactorSetup.tsx created
  Updating state.json: T3 → DONE
  Committing: feat(PROJ-305): complete T3 — 2FA setup UI
```

---

## Step 6: Bob Ends Session (Monday 18:00)

```
User: I'm done for today

Agent: Loading acts-session-summary...
  Running build: ✅ 142 modules compiled
  Running tests: ✅ 47/47 passing
  Running linter: ✅ clean
  Git status: 3 files modified, staged
  
  Writing session file: 20260323-180000-bob.md
  
  ### Session State
  - Compiles: ✅
  - Tests pass: ✅ (47/47)
  - Uncommitted work: ❌ (3 files staged, ready to commit)
  
  ### Gate: approve
  "Session summary ready. Commit and push? (yes/no)"

User: yes

Agent: Updating state.json: session_count += 1
  Committing: docs(PROJ-305): session summary by bob for T1
  Pushing to origin/story/PROJ-305
```

---

## Step 7: Alice Ends Session (Monday 18:30)

[Same pattern — agent loads session-summary, verifies state, commits, pushes]

---

## Step 8: Bob Continues with T2 (Tuesday 09:00)

```
User: Start working on T2

Agent: Loading acts-preflight...
  Reading all sessions...
  Dependencies: T1 DONE ✓
  
  ### Story Board
  [shows T1 DONE, T2 TODO]
  
  ### Gate: approve
  "Ready to proceed with T2? (yes/no)"

User: yes

[Bob implements T2 via task-start]
```

---

## Step 9: Alice Takes Over T4 (Tuesday 10:30)

```
User: Start working on T4

Agent: Loading acts-preflight...
  Dependencies: T1 DONE ✓, T2 DONE ✓
  
  ### Story Board
  [shows dependencies met]
  
  ### Gate: approve
  "Ready to proceed with T4? (yes/no)"

User: yes
```

---

## Step 10: Alice Hands Off T5 to Bob (Tuesday 14:00)

Alice pulled to production incident:

```
User: Hand off T5 to bob

Agent: Loading acts-handoff...
  Running preflight for T5 with bob...
  Reading ALL sessions for T5...
  Reading dependency sessions (T3, T4)...
  Reading files touched by T5...
  
  ### Handoff Briefing: T5
  
  Context:
    T5 adds 2FA enforcement to login flow. Depends on T3 (UI) and 
    T4 (verify endpoint).
  
  Previous work:
    - 20260323-180000-alice: Started login flow analysis
    - No implementation yet
  
  Current code state:
    - Login flow: src/routes/login.ts (not yet modified)
    - T3 provides: TwoFactorVerify component
    - T4 provides: POST /api/totp/verify endpoint
  
  Remaining work:
    - Modify login endpoint to check 2FA requirement
    - Integrate TOTP verification into auth flow
    - Add session flags for 2FA verified
  
  Pitfalls to avoid:
    - Don't break existing login (graceful fallback)
  
  Open questions:
    - Should we enforce 2FA immediately or grace period?
  
  ### Gate: approve
  "Handoff briefing complete. Ready to reassign T5 to bob? (yes/no)"

User: yes

Agent: "Want me to start implementing, or do you have questions first?"

User: Start implementing

Agent: [updates state, commits handoff]
```

---

## Step 11: Bob Implements T5 + T6 (Tuesday 15:00–17:00)

[Standard task-start flow with gates]

---

## Step 12: Story Review (Tuesday 17:30)

```
User: All tasks done, run story review

Agent: Loading acts-story-review...
  Checking: All 6 tasks DONE ✓
  
  Checking acceptance criteria:
    ✅ AC1: TOTP setup endpoint — src/routes/totp.ts:28
    ✅ AC2: TOTP verify endpoint — src/routes/totp.ts:45
    ✅ AC3: 2FA setup UI — src/components/TwoFactorSetup.tsx:34
    ✅ AC4: 2FA verify UI — src/components/TwoFactorVerify.tsx:22
    ✅ AC5: Login enforcement — src/routes/login.ts:67
    ✅ AC6: Recovery codes — src/services/recovery.ts:15
  
  Running tests: ✅ 89/89 passing
  Running linter: ✅ clean
  
  Checking constitution compliance...
  Checking agent compliance across sessions...
    All sessions reported full compliance ✓
  
  ### PR Description Generated
  ## PROJ-305 — Add Two-Factor Authentication
  
  ### Summary
  Users can enable 2FA with TOTP authenticator apps.
  
  ### Changes
  - T1: TOTP setup endpoint
  - T2: TOTP verify endpoint
  - T3: 2FA setup UI
  - T4: 2FA verify UI
  - T5: Login enforcement
  - T6: Recovery codes
  
  ### Testing
  89 tests added. Run `npm test` to verify.
  
  ### Gate: approve
  "Story review complete. All 6 AC met. Tests: 89/89 passing.
   Ready to transition to REVIEW? (yes/no)"

User: yes

Agent: Updating state.json: status → REVIEW
  Committing: docs(PROJ-305): story review complete
```

---

## Step 13: PR Merged (Wednesday 10:00)

Team reviews PR, approves, merges. Story transitions to DONE.

---

## Key Differences from Script-Based Flow

| Before (Scripts) | After (Agent + Gates) |
|---|---|
| `./scripts/acts.sh status` | Agent presents Story Board in gate |
| `./scripts/acts.sh preflight T1 bob` | Agent loads skill, presents gate |
| `./scripts/acts.sh worktree PROJ-305` | Agent runs `git worktree add` |
| `./scripts/acts.sh validate` | `acts-validate` skill or CI script |
| Human reads script output | Human sees formatted report in gate |
| Human tells agent to proceed | Human approves gate, agent continues |

## What the Human Does

```
"Start working on T1"
[see report]
"yes"

"I'm done"
[see session state]
"yes"

"Hand off T5 to bob"
[see briefing]
"yes"
"Start implementing"
```

No script commands to remember. Just natural language + approval gates.

---

## What the Agent Does

1. Load appropriate skill based on context
2. Read all required files per Context Protocol
3. Present Report per Report Protocol
4. Wait at Gate for human approval
5. Execute steps only after approval
6. Update state and commit changes

---

## Human-in-the-Loop Preserved

Every key decision has a gate:
- **preflight**: Approve scope before coding
- **task-start**: Acknowledge scope before implementing
- **session-summary**: Approve session before committing
- **handoff**: Approve reassignment before takeover
- **story-review**: Approve transition to REVIEW

The human sees everything and approves every state change.
