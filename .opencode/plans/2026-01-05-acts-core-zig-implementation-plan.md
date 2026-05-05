# Implementation Plan: ACTS Core (Zig Binary + SQLite + OpenCode Plugin)

## Objective

Replace the current ACTS coordination layer -- Python/TypeScript scripts reading JSON/MD files -- with a single, self-contained Zig binary that uses SQLite for structured state and enforces protocol gates at the database level. Provide an OpenCode plugin that injects ACTS awareness and registers the binary as a tool.

## Architecture

### Two Artifacts

1. `acts` -- Zig CLI binary, embedded in `.acts/bin/acts`
2. `acts-opencode-plugin` -- JavaScript plugin for OpenCode, injected via `opencode.json`

### Data Model

SQLite as single source of truth for all structured data. Markdown files preserved for human-readable narratives only.

| Data | Storage | Source of Truth |
|------|---------|-----------------|
| Story state, tasks, dependencies | SQLite | Binary |
| Gate checkpoints | SQLite | Binary (triggers enforce) |
| Decisions, rejected approaches, open questions | SQLite | Binary |
| Operation audit log | SQLite | Binary |
| Plan, spec, session summaries, task notes | Markdown | Agent-authored |
| `.story/state.json` | REMOVED | N/A |

### Key Design Decisions

- SQLite location: `.acts/acts.db` (central project database)
- Gate enforcement: SQLite triggers (impossible to bypass at DB level)
- Schema migrations: Embedded in binary, auto-run on first use
- CLI pattern: All commands read/write JSON to stdout/stdin for composability
- Session validation: Binary parses markdown and validates structure against JSON schema

## Implementation Phases

### Phase 1: Project Scaffolding and SQLite Foundation

Goal: A compilable Zig project with SQLite linked and basic migration system.

Tasks:

1. Create `build.zig`
   - Link sqlite3 (via system package or vendored sqlite3.c)
   - Cross-compilation targets: linux-x86_64, linux-aarch64, macos-x86_64, macos-aarch64
   - Static linking where possible (single binary, no shared lib deps)

2. Set up directory structure:
   ```
   acts-core/
   ├── build.zig
   ├── build.zig.zon
   ├── src/
   │   ├── main.zig          # CLI entrypoint
   │   ├── cli.zig           # Argument parsing
   │   ├── db.zig            # SQLite wrapper + migrations
   │   ├── schema.sql        # Embedded schema (via @embedFile)
   │   ├── state.zig         # Story/task CRUD
   │   ├── gates.zig         # Gate checkpoint logic
   │   ├── decisions.zig     # Decision/approach/question CRUD
   │   ├── sessions.zig      # Markdown session parser/validator
   │   ├── ownership.zig     # Scope checking
   │   ├── init.zig          # `acts init` command
   │   └── validate.zig      # Full validation
   └── tests/
   ```

3. Implement `db.zig`
   - Open `.acts/acts.db` (create if missing)
   - Read `schema_version` table
   - If missing or behind, run embedded migrations transactionally
   - Migrations are SQL scripts embedded at compile time via `@embedFile`

4. Embed `schema.sql`
   - Full schema including all tables, indexes, and enforcement triggers

Deliverable: `zig build` produces `acts` binary that creates `.acts/acts.db` with correct schema.

Estimated effort: 2-3 sessions

---

### Phase 2: Core Commands -- State, Task, Gate

Goal: Binary can read/write story state and tasks, with gate enforcement via SQLite triggers.

Tasks:

1. `acts state read [--story <id>]`
   - Query SQLite, output JSON matching legacy state.json structure
   - Include tasks, dependencies, files

2. `acts state write --story <id>`
   - Read JSON from stdin
   - Upsert story + tasks + dependencies + files transactionally
   - Update `updated_at` automatically

3. `acts task get <task_id>`
   - Single task lookup with joined files and dependencies

4. `acts task update <task_id> --status <status> [--assigned-to <name>]`
   - Update task status
   - SQLite trigger prevents `status = 'DONE'` unless approved task-review gate checkpoint exists
   - Trigger prevents `status = 'IN_PROGRESS'` unless preflight gate checkpoint exists
   - Trigger prevents `status = 'IN_PROGRESS'` if dependencies not DONE

5. `acts gate add --task <id> --type <type> --status <status> --by <name>`
   - Insert gate checkpoint
   - Validates gate_type enum

6. `acts gate list --task <id>`
   - List checkpoints for task

SQLite Triggers for Gate Enforcement:

- `enforce_task_review_gate`: BEFORE UPDATE OF status ON tasks WHEN NEW.status = 'DONE'
- `enforce_preflight_gate`: BEFORE UPDATE OF status ON tasks WHEN NEW.status = 'IN_PROGRESS' AND OLD.status = 'TODO'
- `enforce_dependencies`: BEFORE UPDATE OF status ON tasks WHEN NEW.status = 'IN_PROGRESS'

Deliverable: Agent can run preflight to gate checkpoint to task update to completion, with DB enforcing rules.

Estimated effort: 3-4 sessions

---

### Phase 3: Decisions, Learnings, Ownership

Goal: Full decision tracking, rejected approaches, open questions, and scope checking.

Tasks:

1. `acts decision add` -- Read JSON from stdin, insert into decisions table
2. `acts decision list --task <id> [--topic <topic>]` -- Query with filters
3. `acts approach add --rejected` -- Read JSON, insert into rejected_approaches
4. `acts question add` -- Read JSON, insert into open_questions
5. `acts question resolve <id> --resolution "..." --by <name>` -- Update status
6. `acts ownership map` -- Query task_files JOIN tasks WHERE status = 'DONE'
7. `acts scope check --task <id> --file <path>` -- Returns ok, warn, or error

Deliverable: Context engine can build full context bundle from binary commands.

Estimated effort: 2 sessions

---

### Phase 4: Session Parsing and Validation

Goal: Binary can parse and validate session summary markdown files.

Tasks:

1. Markdown section extractor
   - Parse `## Section Name` headers
   - Extract standard sections: What was done, Decisions made, What was NOT done, etc.
   - Handle optional sections gracefully

2. Schema validation
   - Required sections must be present (even if content is "None")
   - Validate metadata fields: Developer, Date, Task
   - Validate Current state sub-structure
   - Validate Agent Compliance booleans

3. `acts session parse <file.md>`
   - Output JSON matching session-summary.json schema
   - Useful for MCP context engine to ingest sessions

4. `acts session validate <file.md>`
   - Exit 0 if valid, exit 1 with error messages if invalid
   - Used by agent before committing session files

5. `acts session list --task <id>`
   - Scan `.story/sessions/` for files matching task
   - Parse and sort by date
   - Output JSON array of parsed sessions

Deliverable: Agent can validate session summaries before commit; context engine can ingest sessions via binary.

Estimated effort: 2-3 sessions

---

### Phase 5: Operation Logging and Validation

Goal: Full audit trail and project validation.

Tasks:

1. `acts operation log --id <op_id> --task <id>`
   - Read input JSON from stdin
   - Record to operation_log table with timestamp

2. `acts validate`
   - Check DB schema version
   - Verify all foreign key constraints hold
   - Check for orphaned task files
   - Verify gate consistency
   - Validate all existing session markdown files in `.story/sessions/`
   - Check `.story/plan.md` exists
   - Check `.story/spec.md` exists
   - Exit 0 if all pass, exit 1 with error report

3. `acts migrate`
   - Force re-run migrations (idempotent)
   - Report schema version before and after

4. `acts init --story <id> --title "..."`
   - Create `.story/` directory
   - Create `.acts/acts.db` with schema
   - Insert initial story row with status ANALYSIS
   - Create `.story/plan.md` template
   - Create `.story/spec.md` template
   - Create `.story/sessions/` directory

Deliverable: `acts validate` runs in CI; `acts init` bootstraps new stories.

Estimated effort: 2 sessions

---

### Phase 6: OpenCode Plugin

Goal: OpenCode automatically discovers and uses the ACTS binary.

Tasks:

1. Plugin structure:
   ```
   acts-opencode-plugin/
   ├── package.json
   └── src/
       └── plugin.js
   ```

2. Plugin behavior:
   - Inject ACTS bootstrap context into first user message (like superpowers)
   - Register `acts` tool: OpenCode native tool that wraps the binary
   - Ensure `.acts/bin/acts` is in PATH or resolve absolute path

3. Bootstrap content:
   Injects rules about reading state before writing code, scope checking, session summaries, task boundaries, and code review.

4. `acts` tool registration:
   - Expose as OpenCode tool with schema for command, subcommand, and args
   - Plugin translates to CLI invocation and returns JSON output

5. Auto-discovery:
   - Check if `.acts/bin/acts` exists in project
   - If not found, prompt developer to run `acts init`

Deliverable: Plugin published to npm/git; installed via `opencode.json`.

Estimated effort: 2 sessions

---

### Phase 7: Integration and Testing

Goal: Binary and plugin replace current Python/TypeScript implementation.

Tasks:

1. Migrate existing `.story/state.json`
   - `acts init` or migration script reads legacy JSON, writes to SQLite
   - Handle existing session files (leave as-is)
   - Remove `.story/state.json`

2. Remove legacy code:
   - Remove `.acts/lib/` (Python)
   - Remove `.acts/mcp-server/` (TypeScript)
   - Update `AGENTS.md` to reference new binary commands

3. Test scenarios:
   - Full preflight to task-start to task-review to session-summary flow
   - Gate enforcement: try to mark task DONE without review, expect failure
   - Ownership violation: try to modify DONE-owned file, expect warning
   - Session validation: invalid markdown exits 1
   - Cross-compilation: build for all target platforms

4. CI integration:
   - `acts validate` runs on every PR
   - Binary built and cached for CI runners

Deliverable: Legacy code removed; new binary is sole coordination layer.

Estimated effort: 2-3 sessions

## SQLite Schema

### Tables

- `schema_version` -- migration tracking
- `stories` -- story state (id, acts_version, title, status, spec_approved, timestamps, context_budget, session_count, compressed, strict_mode, metadata)
- `tasks` -- tasks (id, story_id, title, description, status, assigned_to, context_priority, review_status, reviewed_at, reviewed_by)
- `task_files` -- many-to-many tasks to files (task_id, file_path)
- `task_dependencies` -- dependency graph (task_id, depends_on)
- `gate_checkpoints` -- gate enforcement (id, task_id, gate_type, status, approved_by, created_at, resolved_at)
- `decisions` -- recorded decisions (id, task_id, timestamp, session, topic, plan_said, decided, reason, evidence, authority, tags)
- `rejected_approaches` -- rejected approaches (id, task_id, timestamp, session, approach, reason, evidence, tags)
- `open_questions` -- open questions (id, task_id, question, raised_by, raised_at, status, resolution, resolved_by)
- `operation_log` -- audit trail (id, operation_id, task_id, timestamp, caller, input_json, output_json, exit_code)

### Indexes

- idx_tasks_story, idx_tasks_status
- idx_gate_task
- idx_decisions_task
- idx_approaches_task
- idx_questions_task
- idx_oplog_task

### Enforcement Triggers

1. `enforce_task_review_gate` -- BEFORE UPDATE OF status ON tasks WHEN NEW.status = 'DONE'
   - Abort if no approved task-review gate checkpoint exists

2. `enforce_preflight_gate` -- BEFORE UPDATE OF status ON tasks WHEN NEW.status = 'IN_PROGRESS' AND OLD.status = 'TODO'
   - Abort if no approved preflight gate checkpoint exists

3. `enforce_dependencies` -- BEFORE UPDATE OF status ON tasks WHEN NEW.status = 'IN_PROGRESS'
   - Abort if any dependency task status is not DONE

4. `update_story_timestamp` -- AFTER UPDATE ON tasks
   - Update stories.updated_at to current timestamp

## CLI Command Reference

| Command | Description | Input | Output |
|---------|-------------|-------|--------|
| `acts init --story <id> --title "..."` | Bootstrap new story | - | Creates files |
| `acts state read [--story <id>]` | Read full story state | - | JSON |
| `acts state write --story <id>` | Write story state | stdin JSON | - |
| `acts task get <id>` | Get single task | - | JSON |
| `acts task update <id> --status <s>` | Update task status | - | - or error |
| `acts gate add --task <id> --type <t>` | Add gate checkpoint | - | - |
| `acts gate list --task <id>` | List gates | - | JSON |
| `acts decision add` | Record decision | stdin JSON | - |
| `acts decision list --task <id>` | List decisions | - | JSON |
| `acts approach add --rejected` | Record rejected approach | stdin JSON | - |
| `acts question add` | Add open question | stdin JSON | - |
| `acts question resolve <id>` | Resolve question | - | - |
| `acts ownership map` | Show file ownership | - | JSON |
| `acts scope check --task <id> --file <p>` | Check file scope | - | ok/warn/error |
| `acts session parse <file.md>` | Parse session to JSON | - | JSON |
| `acts session validate <file.md>` | Validate session | - | exit 0/1 |
| `acts session list --task <id>` | List parsed sessions | - | JSON |
| `acts operation log --id <op>` | Log operation | stdin JSON | - |
| `acts validate` | Full validation | - | exit 0/1 + report |
| `acts migrate` | Force migration | - | version report |

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Zig ecosystem immaturity | Medium | Medium | Use C sqlite3 bindings, keep dependencies minimal |
| Cross-compilation issues | Low | High | CI builds for all targets; vendor sqlite3.c |
| Agent bypasses binary | Medium | High | Triggers enforce at DB level; CI runs acts validate |
| Binary size too large | Low | Low | Strip symbols; SQLite is ~1MB; expect 2-5MB total |
| Markdown parsing edge cases | Medium | Medium | Extensive test cases; fuzzy testing on session files |
| Backward compatibility | Medium | Medium | Provide migration command; keep old files during transition |

## Success Criteria

1. `zig build` produces a single static binary for linux-x86_64
2. Binary can run full preflight to task-start to task-review to session-summary flow
3. SQLite triggers prevent invalid state transitions (tested)
4. `acts validate` passes on a migrated project
5. OpenCode plugin injects bootstrap and registers acts tool
6. All legacy Python/TypeScript code removed from `.acts/`
7. CI passes `acts validate` on every PR

## Total Estimated Effort

- Phase 1-5 (binary): 11-15 sessions
- Phase 6 (plugin): 2 sessions
- Phase 7 (integration): 2-3 sessions
- Total: ~15-20 sessions

## Next Steps

1. Approve this plan
2. Create design spec for the Zig binary architecture (memory management, error handling, JSON serialization)
3. Bootstrap the Zig project and implement Phase 1
4. Iterate through phases with verification after each
