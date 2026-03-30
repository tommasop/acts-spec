# ACTS v0.4.0 — Slide Deck

---

# Slide 1: The Problem

## Three failures when developers use AI agents on shared code

**1. Drift**
Agents diverge from the agreed technical design. Code moves in directions nobody planned.

**2. Duplication**
Agents reimplement already-completed work because they don't know what's been done.

**3. Context loss**
When one developer hands off to another, decisions, rationale, and state disappear.

---

# Slide 2: What ACTS Is

## A git-native protocol that sits above your tools

```text
┌─────────────────────────────────────────────┐
│  Layer 6: CODE REVIEW                       │
│  GitHuman, mandatory before commit          │
├─────────────────────────────────────────────┤
│  Layer 5: ADAPTERS (community)              │
│  Tool-specific bridges                      │
├─────────────────────────────────────────────┤
│  Layer 4: COMMUNICATION                     │
│  Changelog, tracker sync                    │
├─────────────────────────────────────────────┤
│  Layer 3: OPERATIONS                        │
│  Portable workflow definitions              │
├─────────────────────────────────────────────┤
│  Layer 2: STATE                             │
│  .story/ directory, sessions                │
├─────────────────────────────────────────────┤
│  Layer 1: CONSTITUTION                      │
│  AGENTS.md — shared rules                   │
└─────────────────────────────────────────────┘
```

**Works with any AI tool.** Cursor, Claude Code, OpenCode, Copilot — all the same.
**Language agnostic.** No assumptions about your stack.
**Git native.** Everything lives in the repo. No external database.

---

# Slide 3: Core Features

## Five capabilities that solve the three problems

| Feature | Solves | How |
|---------|--------|-----|
| **Drift prevention** | Drift | Preflight reads state + constitution before coding |
| **File ownership** | Duplication | `files_touched` tracked per task, protected when DONE |
| **Session summaries** | Context loss | Structured handoff artifacts in git |
| **Human-in-the-loop** | Safety | Gates require explicit approval at key decisions |
| **Code review** | Quality | Mandatory GitHuman review before commit |

**Result:** Multiple developers can use AI agents on the same codebase without stepping on each other.

---

# Slide 4: Operations & Gates

## Workflows defined as operations. Humans approve at gates.

| Operation | When | Gate |
|-----------|------|------|
| `story-init` | New story | acknowledge |
| `preflight` | Before coding | **approve** |
| `task-start` | Implementation | acknowledge |
| `task-review` | Before commit | **review** |
| `session-summary` | End of session | **approve** |
| `handoff` | Takeover | **approve** |
| `story-review` | Before PR | **approve** |

**Gate types:**
- **approve** — Agent waits for "yes" before proceeding
- **acknowledge** — Agent shows report, any response continues
- **review** — GitHuman integration, approval required after code review

**Key insight:** No scripts needed. The agent reads operation files and executes them. Human approves at gates.

---

# Slide 5: Agent Attribution & Cost Tracking

## Know what AI did what, and what it cost

**Session summary header (new in v0.4.0):**
```markdown
- **Developer:** alice
- **Agent:** Cursor v0.45.0 (Claude-3.5-Sonnet)
- **Agent Config:** frontend-ruleset
- **Tokens Used:** 32,000
- **Cost Estimate:** $3.20
```

**Templates for any context:**
- `agents-minimal.md` — Simple project
- `agents-multi-role.md` — Frontend/backend/infra roles
- `agents-budget-aware.md` — Model switching, session budgets

**Track:** Accountability, usage, and cost across freelance, open source, or team contexts.

---

# Slide 6: Monday Morning — Starting Your Day

## "What do I work on today?"

**Alice opens her terminal:**

```
alice: ~$ "What's the current status of PROJ-305?"

Agent: Loading preflight...

┌─────────────────────────────────────────────────────────┐
│  PROJ-305 — Add Two-Factor Authentication               │
│  Status: IN_PROGRESS                                    │
├──────┬──────────────┬──────────────┬────────────────────┤
│ Task │ Status       │ Assigned     │ Title              │
├──────┼──────────────┼──────────────┼────────────────────┤
│ T1   │ DONE         │ bob          │ TOTP backend       │
│ T2   │ TODO         │ —            │ TOTP verify        │
│ T3   │ TODO         │ —            │ 2FA UI setup       │
│ T4   │ TODO         │ —            │ 2FA UI verify      │
│ T5   │ TODO         │ —            │ Login enforcement  │
│ T6   │ TODO         │ —            │ Recovery codes     │
└──────┴──────────────┴──────────────┴────────────────────┘
```

**Alice picks T3:**
```
alice: ~$ "I'll take T3"

Agent: Starting preflight for T3...
  Reading state... ✓
  Validating... ✓
  Dependencies: T1 DONE ✓
  
  ### Scope Declaration
  I WILL: Build 2FA setup UI component
  I will NOT: Touch backend (T1/T2 scope)
  
  Ready to proceed? (yes/no)

alice: yes

Agent: ✅ T3 assigned to alice, status → IN_PROGRESS
  Committed: chore(PROJ-305): preflight T3 by alice
```

---

# Slide 7: Monday Afternoon — Coding, Reviewing, Committing

## "Let's write some code"

**Alice implements T3:**

```
alice: ~$ "Let's implement T3"

Agent: Implementing 2FA setup UI...
  [creates components, writes tests, iterates]
  
  Staging changes...
  
  Starting GitHuman server...
  Review interface: http://localhost:3847
  
  ### Code Review Report
  ┌─────────────────────────────────────────────────────────┐
  │  Files Changed: 3                                       │
  │    • src/components/2FASetup.tsx (+45, -0)              │
  │    • src/components/2FASetup.test.tsx (+67, -0)         │
  │    • src/types/2fa.ts (+28, -0)                         │
  │                                                         │
  │  Test Results: ✅ 12/12 passing                         │
  │  Lint Results: ✅ clean                                 │
  │                                                         │
  │  Review interface: http://localhost:3847                │
  └─────────────────────────────────────────────────────────┘
  
  Review staged changes. Approve or request changes.

alice: [reviews in browser, clicks approve]

Agent: ✅ Code review approved
  Exporting review to .story/reviews/active/...
  Committing: feat(PROJ-305): complete T3 — 2FA setup UI
  Done!
```

**That's it.** Agent implemented. You reviewed. Code committed.

---

# Slide 8: Monday End of Day — Session Summary

## "Before you leave, capture what happened"

**Alice wraps up:**

```
alice: ~$ "I'm done for today"

Agent: Running build... ✅ 142 modules compiled
  Running tests... ✅ 12/12 passing
  Running linter... ✅ clean
  Git status: clean
  
  Writing session summary...
  
  ### Session State
  Build:    ✅ 142/142
  Tests:    ✅ 12/12 passing
  Lint:     ✅ clean
  Git:      ✅ clean
  
  Session summary ready. Commit and push? (yes/no)

alice: yes

Agent: ✅ Committed: docs(PROJ-305): session summary by alice for T3
  ✅ Pushed to origin/story/PROJ-305
```

**What's recorded in the session file:**
```markdown
# Session Summary
- **Developer:** alice
- **Agent:** Cursor v0.45.0 (Claude-3.5-Sonnet)
- **Agent Config:** frontend-ruleset
- **Tokens Used:** 32,000
- **Cost Estimate:** $3.20
- **Date:** 2026-03-25T18:00:00Z
- **Task:** T3 — 2FA UI setup

## What was done
- Created 2FASetup component with QR code display
- Added type definitions in types/2fa.ts
- Wrote 12 test cases

## Approaches tried and rejected
- Tried react-qr-code — poor TypeScript support. Used qrcode.react.

## Files touched
- src/components/2FASetup.tsx
- src/components/2FASetup.test.tsx
- src/types/2fa.ts
```

**Next developer knows exactly what happened and why.**

---

# Slide 9: Tuesday — Handing Off Work

## "Alice is pulled to a priority — Bob takes over"

**Alice hands off T5:**

```
alice: ~$ "Hand off T5 to bob"

Agent: Running preflight for T5 with bob...
  Reading all sessions for T5...
  Reading dependency sessions (T3, T4)...
  
  ### Handoff Briefing: T5
  
  Context:
    T5 adds 2FA enforcement to login flow.
    Depends on T3 (UI) + T4 (verify endpoint).
  
  Previous work:
    20260324-160000-alice: Started login flow analysis, no code yet.
  
  Remaining work:
    - Modify login endpoint to check 2FA requirement
    - Integrate TOTP verification into auth flow
    - Add session flags for 2FA verified
  
  Pitfalls to avoid:
    - Don't break existing login (graceful fallback)
  
  Open questions:
    - Should we enforce 2FA immediately or grace period?
  
  Ready to reassign T5 to bob? (yes/no)

alice: yes

Agent: ✅ T5 reassigned to bob
  Committed: chore(PROJ-305): handoff T5 to bob
```

**Bob picks up the next morning:**

```
bob: ~$ "Start working on T5"

Agent: Loading handoff briefing from Alice...
  
  [shows full context, pitfalls, remaining work]
  
  Ready to implement? (yes/no)

bob: yes

Agent: ✅ T5 assigned to bob
  [Bob continues implementing with full context]
```

**No knowledge lost. No meetings needed.**

---

# Slide 10: Wrapping Up the Story

## "All tasks done — generate PR description"

**Bob runs story review:**

```
bob: ~$ "All tasks done, run story review"

Agent: Verifying all tasks...
  T1 DONE ✓  T2 DONE ✓  T3 DONE ✓
  T4 DONE ✓  T5 DONE ✓  T6 DONE ✓

  Checking acceptance criteria...
  ✅ AC1: TOTP setup endpoint
  ✅ AC2: TOTP verify endpoint
  ✅ AC3: 2FA setup UI
  ✅ AC4: 2FA verify UI
  ✅ AC5: Login enforcement
  ✅ AC6: Recovery codes

  Tests: ✅ 89/89 passing
  Lint: ✅ clean

  ### PR Description
  ## PROJ-305 — Add Two-Factor Authentication
  ### Summary
  Users can enable 2FA with TOTP authenticator apps.
  ### Changes
  - T1-T2: Backend endpoints (bob)
  - T3-T4: Frontend components (alice)
  - T5-T6: Integration + recovery (bob)
  ### Testing
  89 tests added. Run `npm test` to verify.
  
  Transition to REVIEW? (yes/no)

bob: yes

Agent: ✅ Story status → REVIEW
  Committed: docs(PROJ-305): story review complete
```

**PR is ready for human review. Merge when approved.**

---

# Slide 11: The Daily Loop

## Your day with ACTS — five interactions

**Morning:**
```
"What's the status?"
"I'll take T3"
→ preflight gate: approve
```

**Working:**
```
"Let's implement T3"
→ code → stage → GitHuman review → commit
```

**End of day:**
```
"I'm done"
→ session summary → commit → push
```

**Handoff (when needed):**
```
"Hand off T5 to bob"
→ handoff briefing → reassign
```

**Story done:**
```
"All tasks done, run story review"
→ validate ACs → PR description → merge
```

**That's it. No scripts. No complex commands. Just talk to your agent.**

---

# Summary: What ACTS Gives You

| Before ACTS | After ACTS |
|-------------|------------|
| Agent writes code, you hope for the best | Preflight validates scope before coding |
| "What did Alice work on yesterday?" | Session summaries in git |
| "Can someone take over T5?" | Handoff briefing with full context |
| PR review discovers issues | GitHuman review before commit |
| No idea what AI did vs what you did | Agent attribution + cost tracking |

**ACTS = Structured coordination for AI-assisted development.**

---

## Quick Start

```bash
# 1. Copy the standard into your project
cp -r acts-spec/.acts ./.acts/

# 2. Create your constitution
cp acts-spec/templates/agents-minimal.md ./AGENTS.md

# 3. Install GitHuman (required for v0.4.0)
npm install -g githuman

# 4. Start your first story
"Initialize ACTS tracker for PROJ-XXX, title '...'"

# 5. Work the story
"I'll take T1" → preflight → code → review → commit

# 6. End your day
"I'm done" → session summary
```

---

## Resources

- **Spec:** `acts-v0.4.0.md`
- **Operations:** `.acts/operations/*.md`
- **Templates:** `docs/templates/`
- **Flow examples:** `docs/scripts-flow.md`
- **GitHuman:** https://githuman.dev

---

*ACTS v0.4.0 — The protocol for developers using AI agents on shared code.*
