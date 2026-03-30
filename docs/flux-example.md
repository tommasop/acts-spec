# ACTS Flux Example — "Add User Avatar Upload"

A time-sequenced walkthrough showing how ACTS state evolves as a 2-developer team implements a story.

---

## Phase 0: Story Init (alice, Monday 09:00)

Alice runs `story-init` with source material from Jira ticket `PROJ-217`.

### `.story/state.json` created

```json
{
  "acts_version": "0.3.0",
  "story_id": "PROJ-217",
  "title": "Add User Avatar Upload",
  "status": "ANALYSIS",
  "spec_approved": false,
  "created_at": "2026-03-23T09:00:00Z",
  "updated_at": "2026-03-23T09:00:00Z",
  "context_budget": 50000,
  "tasks": [
    {
      "id": "T1",
      "title": "Create AvatarUpload component with drag-and-drop",
      "status": "TODO",
      "assigned_to": null,
      "files_touched": [],
      "depends_on": [],
      "context_priority": 1
    },
    {
      "id": "T2",
      "title": "Add backend endpoint for avatar upload + S3 integration",
      "status": "TODO",
      "assigned_to": null,
      "files_touched": [],
      "depends_on": [],
      "context_priority": 1
    },
    {
      "id": "T3",
      "title": "Add avatar URL to user profile API response",
      "status": "TODO",
      "assigned_to": null,
      "files_touched": [],
      "depends_on": ["T2"],
      "context_priority": 2
    },
    {
      "id": "T4",
      "title": "Wire AvatarUpload component to backend endpoint",
      "status": "TODO",
      "assigned_to": null,
      "files_touched": [],
      "depends_on": ["T1", "T2"],
      "context_priority": 2
    },
    {
      "id": "T5",
      "title": "Add avatar display to profile page and navbar",
      "status": "TODO",
      "assigned_to": null,
      "files_touched": [],
      "depends_on": ["T3", "T4"],
      "context_priority": 3
    }
  ],
  "session_count": 0,
  "compressed": false,
  "metadata": {
    "jira_epic": "PROJ-100",
    "sprint": "2026-Q1-S6",
    "priority": "high"
  }
}
```

### `.story/spec.md` created

```markdown
# PROJ-217 — Add User Avatar Upload

## Goal
Users can upload a profile avatar image via drag-and-drop or file picker.
The avatar appears in the navbar and profile page.

## Acceptance Criteria
1. User can drag an image onto the upload zone OR click to browse files.
2. Accepted formats: JPEG, PNG, WebP. Max size: 5MB.
3. Image is cropped to a square on the client before upload.
4. Backend stores the image in S3 and returns a public URL.
5. Profile API response includes the `avatar_url` field.
6. Navbar shows the user's avatar (or a default placeholder).
7. Profile page shows a larger avatar with an option to change it.

## Technical Decisions
- Frontend: React component using `react-dropzone` for DnD.
- Cropping: `react-easy-crop` for client-side square crop.
- Backend: New `POST /api/users/:id/avatar` endpoint.
- Storage: S3 bucket `user-avatars-{env}`, public-read ACL.
- Auth: Endpoint requires authentication; user can only upload their own avatar.

## Out of Scope
- Avatar deletion (future story).
- Admin moderation of avatars.
- Animated GIF support.
```

### `.story/plan.md` created

```markdown
# Execution Plan — PROJ-217

## Tasks

### T1 — Create AvatarUpload component with drag-and-drop
- **Depends on:** none
- **Files likely touched:** `src/components/AvatarUpload.tsx`, `src/components/AvatarUpload.test.tsx`
- **Context priority:** 1
- **Acceptance:** Component renders drop zone, accepts files, shows preview, calls `onCropComplete` callback.

### T2 — Add backend endpoint for avatar upload + S3 integration
- **Depends on:** none
- **Files likely touched:** `src/routes/avatar.ts`, `src/services/s3.ts`, `src/routes/avatar.test.ts`
- **Context priority:** 1
- **Acceptance:** `POST /api/users/:id/avatar` accepts multipart upload, stores in S3, returns URL. Tests pass.

### T3 — Add avatar URL to user profile API response
- **Depends on:** T2
- **Files likely touched:** `src/routes/profile.ts`, `src/models/user.ts`
- **Context priority:** 2
- **Acceptance:** `GET /api/users/:id` response includes `avatar_url` field.

### T4 — Wire AvatarUpload component to backend endpoint
- **Depends on:** T1, T2
- **Files likely touched:** `src/components/AvatarUpload.tsx`, `src/hooks/useAvatarUpload.ts`
- **Context priority:** 2
- **Acceptance:** Selecting/cropping an image triggers upload to backend, shows success/error state.

### T5 — Add avatar display to profile page and navbar
- **Depends on:** T3, T4
- **Files likely touched:** `src/pages/Profile.tsx`, `src/components/Navbar.tsx`, `src/components/Avatar.tsx`
- **Context priority:** 3
- **Acceptance:** Navbar shows 32px circular avatar. Profile page shows 128px avatar with change button.
```

**Commit:** `docs(PROJ-217): initialize ACTS tracker`

---

## Phase 1: Team Reviews Spec (Monday 14:00)

The team reviews `spec.md` and `plan.md` in a pull request. Bob flags that T2 needs a file type validation step. Alice updates the plan. Team approves.

**State transition:** Manual — `spec_approved` → `true`, status → `APPROVED`

```json
{
  "status": "APPROVED",
  "spec_approved": true,
  "updated_at": "2026-03-23T14:00:00Z"
}
```

---

## Phase 2: Alice Preflights T1 (Monday 15:00)

Alice runs `preflight` for T1.

### Preflight execution:

1. Reads `AGENT.md` — confirms architecture patterns.
2. Reads `state.json` — validates against `.acts/schemas/state.json`. Story is `APPROVED`, task T1 is `TODO`.
3. Validates story: `APPROVED` → transitions to `IN_PROGRESS` on first preflight.
4. Validates task: `TODO` → OK.
5. Dependencies: T1 has `depends_on: []` → none to check.
6. Context ingestion: reads `AGENT.md`, `state.json`, `plan.md`, T1 plan entry. No completed dependency files yet.
7. Concurrency: no other task is `IN_PROGRESS`.
8. Scope declaration: "I will build AvatarUpload.tsx and its tests. I will NOT touch backend files (T2's scope)."

### `state.json` updated

```json
{
  "status": "IN_PROGRESS",
  "updated_at": "2026-03-23T15:00:00Z",
  "tasks": [
    {
      "id": "T1",
      "title": "Create AvatarUpload component with drag-and-drop",
      "status": "IN_PROGRESS",
      "assigned_to": "alice",
      "files_touched": [],
      "depends_on": [],
      "context_priority": 1
    }
  ]
}
```

**Commit:** `chore(PROJ-217): preflight T1 by alice`

---

## Phase 3: Bob Preflights T2 (Monday 15:30, separate worktree)

Bob works in `../worktrees/PROJ-217/`. Runs `preflight` for T2.

### Preflight execution:

1. Reads `AGENT.md`.
2. Reads `state.json` — story is `IN_PROGRESS`, T2 is `TODO`.
3. Validates: story `IN_PROGRESS` → continue. Task `TODO` → OK.
4. Dependencies: T2 has `depends_on: []` → none.
5. Context ingestion: reads T1's plan entry (no code exists yet).
6. Concurrency: T1 is `IN_PROGRESS` by alice, but Bob is in a **different worktree** → WARN. Bob confirms.
7. Scope: "I will build the avatar upload endpoint and S3 service. I will NOT touch frontend files."

### `state.json` updated (in Bob's worktree)

```json
{
  "tasks": [
    {
      "id": "T2",
      "status": "IN_PROGRESS",
      "assigned_to": "bob"
    }
  ]
}
```

**Commit:** `chore(PROJ-217): preflight T2 by bob`

---

## Phase 4: Alice Implements T1 (Monday 16:00–18:00)

Alice runs `task-start` for T1. Uses TDD:

1. Writes failing test for drop zone rendering.
2. Implements `AvatarUpload.tsx` with `react-dropzone`.
3. Writes test for file validation (format, size).
4. Implements validation logic.
5. Writes test for crop preview.
6. Implements `react-easy-crop` integration.

### `state.json` updated — T1 complete

```json
{
  "tasks": [
    {
      "id": "T1",
      "title": "Create AvatarUpload component with drag-and-drop",
      "status": "DONE",
      "assigned_to": "alice",
      "files_touched": [
        "src/components/AvatarUpload.tsx",
        "src/components/AvatarUpload.test.tsx",
        "src/types/avatar.ts"
      ],
      "depends_on": [],
      "context_priority": 1
    }
  ]
}
```

**Commit:** `feat(PROJ-217): complete T1 — AvatarUpload component`

---

## Phase 5: Alice Writes Session Summary (Monday 18:00)

Alice runs `session-summary`.

### `.story/sessions/20260323-180000-alice.md`

```markdown
# Session Summary
- **Developer:** alice
- **Date:** 2026-03-23T18:00:00Z
- **Task:** T1 — Create AvatarUpload component with drag-and-drop

## What was done
- Created `AvatarUpload.tsx` with react-dropzone integration
- Implemented client-side file validation (JPEG/PNG/WebP, 5MB max)
- Added react-easy-crop for square cropping
- Created comprehensive tests for all component behaviors
- Added shared types in `src/types/avatar.ts`

## Decisions made
- Used react-dropzone v14 for its hooks API (simpler than class-based v12)
- Crop is done client-side before upload to reduce bandwidth
- Component accepts `onCropComplete` callback for T4 to wire up

## What was NOT done (and why)
- Actual file upload is T4's responsibility (depends on T2 backend)
- Avatar display in navbar/profile is T5

## Approaches tried and rejected
- Tried `react-image-crop` first — too complex API, poor TypeScript support. Switched to `react-easy-crop`.

## Open questions
- Should we support image rotation during crop? Not in spec but UX might expect it.

## Current state
- Compiles: ✅
- Tests pass: ✅ (12/12)
- Uncommitted work: ❌

## Files touched this session
- `src/components/AvatarUpload.tsx` — new component with DnD + crop
- `src/components/AvatarUpload.test.tsx` — 12 test cases
- `src/types/avatar.ts` — shared types (CropArea, AvatarUploadProps)

## Suggested next step
- T2 (backend endpoint) can proceed in parallel. T4 should wait for both T1 and T2.

## Agent Compliance
- Read AGENT.md: ✅
  - Sections confirmed: Rules, Architecture, Style, Testing
- Read state.json: ✅
- Followed preflight protocol: ✅
- Followed context protocol: ✅
  - Steps skipped: none
- Deviated from plan: ❌
  - Deviations: none
```

**Commit:** `docs(PROJ-217): session summary by alice for T1`
**Push:** `git push origin story/PROJ-217`

---

## Phase 6: Bob Implements T2 (Monday 15:30–19:00, separate worktree)

Bob runs `task-start` for T2.

1. Creates `src/services/s3.ts` — S3 upload wrapper.
2. Creates `src/routes/avatar.ts` — `POST /api/users/:id/avatar` with multipart parsing.
3. Adds auth middleware check: user can only upload to their own profile.
4. Validates file type and size server-side (defense in depth).
5. Writes integration tests with mocked S3.

### `state.json` updated — T2 complete

```json
{
  "tasks": [
    {
      "id": "T2",
      "status": "DONE",
      "assigned_to": "bob",
      "files_touched": [
        "src/routes/avatar.ts",
        "src/services/s3.ts",
        "src/routes/avatar.test.ts",
        "src/middleware/validate-file.ts"
      ]
    }
  ]
}
```

**Commit:** `feat(PROJ-217): complete T2 — avatar upload endpoint`

### Bob's session summary (`.story/sessions/20260323-190000-bob.md`)

```markdown
# Session Summary
- **Developer:** bob
- **Date:** 2026-03-23T19:00:00Z
- **Task:** T2 — Add backend endpoint for avatar upload + S3 integration

## What was done
- Created S3 service wrapper (`src/services/s3.ts`)
- Built POST /api/users/:id/avatar endpoint with multipart support
- Added server-side file validation middleware
- Wrote integration tests with mocked S3 client

## Decisions made
- Used `@aws-sdk/client-s3` v3 (not v2) per AGENT.md dependency policy
- Multipart parsing via `multer` with memory storage (buffer to S3, no temp files)
- Validation middleware is reusable — placed in `src/middleware/`

## What was NOT done (and why)
- T3 (avatar_url in profile API) — my task, will do next
- T4/T5 — frontend tasks, depend on T1 + T2

## Approaches tried and rejected
- Considered streaming upload directly to S3 — too complex for MVP, would need presigned URLs

## Open questions
- S3 bucket naming convention: using `user-avatars-{env}` but infra team hasn't confirmed bucket exists in staging

## Current state
- Compiles: ✅
- Tests pass: ✅ (8/8)
- Uncommitted work: ❌

## Files touched this session
- `src/routes/avatar.ts` — new endpoint
- `src/services/s3.ts` — S3 wrapper
- `src/routes/avatar.test.ts` — integration tests
- `src/middleware/validate-file.ts` — reusable file validation

## Suggested next step
- T3: add `avatar_url` to user profile response. Simple — just read from user model and include in serializer.

## Agent Compliance
- Read AGENT.md: ✅
  - Sections confirmed: Rules, Architecture, Testing, Git
- Read state.json: ✅
- Followed preflight protocol: ✅
- Followed context protocol: ✅
  - Steps skipped: none
- Deviated from plan: ✅
  - Deviations: Added `src/middleware/validate-file.ts` not in original plan (discovered during implementation)
```

---

## Phase 7: Bob Implements T3 (Tuesday 09:00)

Bob runs `preflight` for T3.

### Preflight notes:

- Dependencies: T2 is `DONE` → OK.
- Context ingestion: reads T2's files (`src/routes/avatar.ts`, `src/services/s3.ts`, `src/models/user.ts`).
- Scope: "I will add avatar_url to the profile endpoint response."

Bob implements T3: updates `src/routes/profile.ts` to include `avatar_url` from the user model. Updates the user model's `toJSON()` method.

### T3 complete

```json
{
  "id": "T3",
  "status": "DONE",
  "assigned_to": "bob",
  "files_touched": [
    "src/routes/profile.ts",
    "src/models/user.ts"
  ],
  "depends_on": ["T2"]
}
```

**Commit:** `feat(PROJ-217): complete T3 — avatar_url in profile API`

---

## Phase 8: Alice Handoffs T4 to Bob (Tuesday 10:00)

Alice is pulled to another priority. Bob takes over T4. Alice runs `handoff`.

### Handoff briefing displayed:

```markdown
## Handoff Briefing: T4

### Context
T4 wires the AvatarUpload component (T1) to the backend endpoint (T2).
It's the glue between frontend and backend.

### Previous work
- T1 (alice): AvatarUpload component with DnD + crop. Accepts `onCropComplete` callback.
- T2 (bob): POST /api/users/:id/avatar endpoint. Accepts multipart.
- T3 (bob): Profile API now returns avatar_url.

### Current code state
- AvatarUpload component exists but doesn't upload anything — just calls callback with cropped blob.
- Backend endpoint is live and tested.
- No upload hook exists yet.

### Remaining work
- Create `useAvatarUpload` hook that takes cropped blob and POSTs to endpoint.
- Wire hook into AvatarUpload component.
- Handle success/error states in UI.

### Pitfalls to avoid
- react-image-crop has poor TS support (alice tried it, switched to react-easy-crop).

### Open questions
- Should we support image rotation? Not in spec.

### Files to review
1. `src/components/AvatarUpload.tsx` — understand the callback interface
2. `src/routes/avatar.ts` — understand the endpoint contract
3. `src/types/avatar.ts` — shared types

### Context ingestion report
- Sessions read: 3 (alice T1, bob T2, bob T3)
- Compressed briefing used: no
- Files read: 7
- Estimated tokens used: 12,400
```

### `state.json` updated

```json
{
  "id": "T4",
  "status": "IN_PROGRESS",
  "assigned_to": "bob"
}
```

**Commit:** `chore(PROJ-217): handoff T4 to bob`

---

## Phase 9: Bob Implements T4 + T5 (Tuesday 11:00–16:00)

Bob runs `task-start` for T4, then T5 sequentially.

**T4:** Creates `src/hooks/useAvatarUpload.ts`, wires it into `AvatarUpload.tsx`. Adds upload progress indicator.

**T5:** Creates `src/components/Avatar.tsx` (reusable avatar display), updates `Navbar.tsx` and `Profile.tsx`.

### Final `state.json`

```json
{
  "acts_version": "0.3.0",
  "story_id": "PROJ-217",
  "title": "Add User Avatar Upload",
  "status": "IN_PROGRESS",
  "spec_approved": true,
  "created_at": "2026-03-23T09:00:00Z",
  "updated_at": "2026-03-24T16:00:00Z",
  "context_budget": 50000,
  "tasks": [
    { "id": "T1", "status": "DONE", "assigned_to": "alice" },
    { "id": "T2", "status": "DONE", "assigned_to": "bob" },
    { "id": "T3", "status": "DONE", "assigned_to": "bob" },
    { "id": "T4", "status": "DONE", "assigned_to": "bob" },
    { "id": "T5", "status": "DONE", "assigned_to": "bob" }
  ],
  "session_count": 5,
  "compressed": false
}
```

---

## Phase 10: Story Review (Tuesday 16:30)

Bob runs `story-review`.

### Review execution:

1. **All tasks DONE** ✅
2. **Acceptance criteria check:**
   - AC1 (drag-and-drop): ✅ `AvatarUpload.tsx:34`
   - AC2 (formats + 5MB): ✅ `AvatarUpload.tsx:18`, `validate-file.ts:5`
   - AC3 (client crop): ✅ `AvatarUpload.tsx:52`
   - AC4 (S3 storage + URL): ✅ `avatar.ts:28`, `s3.ts:12`
   - AC5 (avatar_url in API): ✅ `profile.ts:15`, `user.ts:42`
   - AC6 (navbar avatar): ✅ `Navbar.tsx:22`
   - AC7 (profile page avatar): ✅ `Profile.tsx:38`
3. **Test suite:** 34/34 passing
4. **Linter:** clean
5. **Constitution compliance:** all public functions typed, no forbidden patterns, commits follow convention
6. **Agent compliance audit:** 5 sessions — all reported full compliance. 1 deviation (bob added middleware file in T2, noted in plan).

### `state.json` updated

```json
{
  "status": "REVIEW",
  "updated_at": "2026-03-24T16:30:00Z"
}
```

**Commit:** `docs(PROJ-217): story review complete`

---

## Phase 11: PR Merged (Wednesday 10:00)

Team reviews the PR, approves, merges to main.

**State transition:** `REVIEW` → `DONE`

```json
{
  "status": "DONE",
  "updated_at": "2026-03-25T10:00:00Z"
}
```

---

## Flux Summary — Timeline

```
Monday 09:00  ─ story-init          ── (none) → ANALYSIS
Monday 14:00  ─ team approves spec  ── ANALYSIS → APPROVED
Monday 15:00  ─ preflight T1 (alice)── APPROVED → IN_PROGRESS
Monday 15:30  ─ preflight T2 (bob)  ── (parallel worktree)
Monday 18:00  ─ T1 DONE (alice)
Monday 19:00  ─ T2 DONE (bob)
Tuesday 09:00 ─ T3 DONE (bob)
Tuesday 10:00 ─ handoff T4 → bob
Tuesday 13:00 ─ T4 DONE (bob)
Tuesday 16:00 ─ T5 DONE (bob)
Tuesday 16:30 ─ story-review        ── IN_PROGRESS → REVIEW
Wednesday 10  ─ PR merged           ── REVIEW → DONE
```

## Key ACTS Patterns Demonstrated

| Pattern | Where |
|---|---|
| Drift prevention | Preflight scope declarations kept T1/T2 boundaries clean |
| Parallel development | Alice + Bob in separate worktrees, T1/T2 concurrent |
| Context loss prevention | Session summaries enabled Bob to take over T4 seamlessly |
| File ownership | `files_touched` prevented cross-task interference |
| Agent compliance | Self-reported compliance in every session summary |
| State machine | Every transition followed valid paths |
| Context protocol | Preflight ingestion of prior work before coding |
