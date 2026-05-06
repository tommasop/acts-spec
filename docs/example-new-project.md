# Example: Starting a New Project with ACTS

This document shows a complete agent interaction for bootstrapping a new project with ACTS v1.0.0.

---

## Scenario

**Project:** Build a URL shortener API
**Story:** PROJ-101 — "URL Shortener Service"
**Developer:** alice
**Tool:** OpenCode with ACTS plugin

---

## Step 1: Initialize ACTS

**User:** "Set up ACTS for a new project called 'url-shortener'"

**Agent:**
```
I'll initialize ACTS for your new project.

> acts init PROJ-101 --title "URL Shortener Service"

Initialized ACTS story: PROJ-101
Database: .acts/acts.db
Created: .story/plan.md, .story/spec.md, .story/sessions/
```

**Result:**
- `.acts/acts.db` created with schema and triggers
- `.story/plan.md` created with template
- `.story/spec.md` created with template
- `.story/sessions/` directory created

---

## Step 2: Define the Spec

**User:** "Write the spec for the URL shortener. It should:
- Accept POST /shorten with a URL, return a short code
- Redirect GET /:code to the original URL
- Track click counts
- Expire URLs after 30 days"

**Agent:**
```
I'll create the spec in .story/spec.md:

> Write .story/spec.md

# Specification — URL Shortener Service

## Overview
A simple URL shortening service with analytics.

## Acceptance Criteria
1. POST /shorten accepts {url: string} and returns {shortCode: string}
2. GET /:shortCode redirects (301) to original URL
3. Click count is incremented on each redirect
4. URLs expire after 30 days of inactivity
5. Invalid short codes return 404

## API Endpoints

### POST /shorten
Request: { "url": "https://example.com" }
Response: { "shortCode": "abc123", "url": "https://example.com" }

### GET /:shortCode
Redirects to original URL (301)

## Data Model
- shortCode: string (PK, 6 chars alphanumeric)
- url: string (original URL)
- clicks: integer
- createdAt: datetime
- lastAccessed: datetime

## Tech Stack
- Node.js + Express
- SQLite (for simplicity)
```

---

## Step 3: Create the Plan

**Agent:**
```
Now I'll create the implementation plan in .story/plan.md:

> Write .story/plan.md

# Plan — URL Shortener Service

## Tasks

### T1: Setup project structure
- Initialize Node.js project
- Install Express, SQLite dependencies
- Create basic Express server
- Files: package.json, src/server.js

### T2: Implement URL shortening
- POST /shorten endpoint
- Generate unique short codes
- Store in SQLite
- Files: src/routes/shorten.js, src/db.js

### T3: Implement redirect
- GET /:shortCode endpoint
- Lookup and redirect
- Increment click count
- Files: src/routes/redirect.js

### T4: Add expiration
- Cron job to clean expired URLs
- Files: src/jobs/expiration.js

### T5: Add tests
- Unit tests for all endpoints
- Files: src/**/*.test.js
```

**Agent:**
```
Now I'll create the tasks in the database:

> echo '{"tasks": [
  {"id": "T1", "title": "Setup project structure", "status": "TODO", "files_touched": ["package.json", "src/server.js"], "depends_on": [], "context_priority": 1},
  {"id": "T2", "title": "Implement URL shortening", "status": "TODO", "files_touched": ["src/routes/shorten.js", "src/db.js"], "depends_on": ["T1"], "context_priority": 1},
  {"id": "T3", "title": "Implement redirect", "status": "TODO", "files_touched": ["src/routes/redirect.js"], "depends_on": ["T2"], "context_priority": 1},
  {"id": "T4", "title": "Add expiration", "status": "TODO", "files_touched": ["src/jobs/expiration.js"], "depends_on": ["T3"], "context_priority": 2},
  {"id": "T5", "title": "Add tests", "status": "TODO", "files_touched": ["src/**/*.test.js"], "depends_on": ["T3"], "context_priority": 1}
]}' | acts state write --story PROJ-101
```

---

## Step 4: Start First Task (T1)

**User:** "Start working on T1"

**Agent:**
```
Let me check the current state and start T1.

> acts state read

{
  "story_id": "PROJ-101",
  "status": "ANALYSIS",
  "tasks": [
    {"id": "T1", "title": "Setup project structure", "status": "TODO", ...}
  ]
}

I need to add a preflight gate before starting:

> acts gate add --task T1 --type approve --status approved --by alice
> acts task update T1 --status IN_PROGRESS --assigned-to alice

Task T1 is now IN_PROGRESS.
```

---

## Step 5: Implement T1

**Agent:** [Implements code using Write/Edit tools]

```
Creating package.json...
Creating src/server.js...

> Bash: npm install express sqlite3
> Bash: node src/server.js
Server running on port 3000
```

---

## Step 6: Complete T1

**Agent:**
```
Task T1 is complete. Let me update the state:

> acts gate add --task T1 --type task-review --status approved --by alice
> acts task update T1 --status DONE

Task T1 is now DONE.
```

---

## Step 7: Record Session Summary

**Agent:**
```
Recording session summary:

> Write .story/sessions/20260105-143022-alice.md

# Session Summary
- **Developer:** alice
- **Agent:** OpenCode (GPT-4)
- **Date:** 2026-01-05T14:30:00Z
- **Task:** T1 — Setup project structure

## What was done
- Created package.json with Express and SQLite dependencies
- Created src/server.js with basic Express setup
- Verified server starts successfully

## Decisions made
- Used SQLite for simplicity (single file, no external DB needed)
- Port 3000 for development

## What was NOT done (and why)
- No tests yet (will be done in T5)
- No environment config (keeping it simple for now)

## Approaches tried and rejected
- None

## Open questions
- Should we use TypeScript instead of plain JS?

## Current state
- Compiles: ✅
- Tests pass: N/A (no tests yet)
- Uncommitted work: ✅

## Files touched this session
- package.json — project setup
- src/server.js — Express server

## Suggested next step
Start T2: Implement URL shortening endpoint

## Agent Compliance
- Read state.json before writing code: ✅
- Did not modify files owned by DONE tasks: ✅ (none yet)
- Stayed within assigned task boundary: ✅
- Followed context protocol: ✅
```

---

## Step 8: Validate

**Agent:**
```
> acts session validate .story/sessions/20260105-143022-alice.md
Session validation passed

> acts validate
Schema version: 1
Found: .story/plan.md
Found: .story/spec.md
Session files: 1
Validation PASSED
```

---

## Summary

In this session:
1. ✅ Initialized ACTS with `acts init`
2. ✅ Created spec in `.story/spec.md`
3. ✅ Created plan in `.story/plan.md`
4. ✅ Created 5 tasks via `acts state write`
5. ✅ Completed T1 with gate enforcement
6. ✅ Recorded and validated session summary

**Next:** Start T2 (Implement URL shortening)
