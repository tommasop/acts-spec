-- Migration tracking
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    applied_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Stories
CREATE TABLE IF NOT EXISTS stories (
    id TEXT PRIMARY KEY,
    acts_version TEXT NOT NULL,
    title TEXT NOT NULL,
    status TEXT NOT NULL CHECK(status IN ('ANALYSIS','APPROVED','IN_PROGRESS','REVIEW','DONE')),
    spec_approved INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    context_budget INTEGER NOT NULL DEFAULT 50000,
    session_count INTEGER DEFAULT 0,
    compressed INTEGER DEFAULT 0,
    strict_mode INTEGER DEFAULT 0,
    metadata TEXT
);

-- Tasks
CREATE TABLE IF NOT EXISTS tasks (
    id TEXT PRIMARY KEY,
    story_id TEXT NOT NULL REFERENCES stories(id),
    title TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL CHECK(status IN ('TODO','IN_PROGRESS','BLOCKED','DONE')),
    assigned_to TEXT,
    context_priority INTEGER DEFAULT 3 CHECK(context_priority BETWEEN 1 AND 5),
    review_status TEXT DEFAULT 'pending' CHECK(review_status IN ('pending','approved','changes_requested','skipped')),
    reviewed_at TEXT,
    reviewed_by TEXT
);

-- Task files
CREATE TABLE IF NOT EXISTS task_files (
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    file_path TEXT NOT NULL,
    PRIMARY KEY (task_id, file_path)
);

-- Dependencies
CREATE TABLE IF NOT EXISTS task_dependencies (
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    depends_on TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    PRIMARY KEY (task_id, depends_on)
);

-- Gate checkpoints
CREATE TABLE IF NOT EXISTS gate_checkpoints (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    gate_type TEXT NOT NULL CHECK(gate_type IN ('approve','task-review','commit-review','architecture-discuss')),
    status TEXT NOT NULL CHECK(status IN ('pending','approved','changes_requested')),
    approved_by TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    resolved_at TEXT
);

-- Decisions
CREATE TABLE IF NOT EXISTS decisions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    session TEXT NOT NULL,
    topic TEXT NOT NULL,
    plan_said TEXT,
    decided TEXT NOT NULL,
    reason TEXT NOT NULL,
    evidence TEXT NOT NULL,
    authority TEXT NOT NULL CHECK(authority IN ('developer_approved','agent_decided')),
    tags TEXT
);

-- Rejected approaches
CREATE TABLE IF NOT EXISTS rejected_approaches (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    session TEXT NOT NULL,
    approach TEXT NOT NULL,
    reason TEXT NOT NULL,
    evidence TEXT NOT NULL,
    tags TEXT
);

-- Open questions
CREATE TABLE IF NOT EXISTS open_questions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    question TEXT NOT NULL,
    raised_by TEXT NOT NULL,
    raised_at TEXT DEFAULT (datetime('now')),
    status TEXT DEFAULT 'unresolved' CHECK(status IN ('unresolved','resolved','deferred')),
    resolution TEXT,
    resolved_by TEXT
);

-- Operation audit log
CREATE TABLE IF NOT EXISTS operation_log (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    operation_id TEXT NOT NULL,
    task_id TEXT REFERENCES tasks(id),
    timestamp TEXT NOT NULL DEFAULT (datetime('now')),
    caller TEXT,
    input_json TEXT,
    output_json TEXT,
    exit_code INTEGER
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_tasks_story ON tasks(story_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_gate_task ON gate_checkpoints(task_id);
CREATE INDEX IF NOT EXISTS idx_decisions_task ON decisions(task_id);
CREATE INDEX IF NOT EXISTS idx_approaches_task ON rejected_approaches(task_id);
CREATE INDEX IF NOT EXISTS idx_questions_task ON open_questions(task_id);
CREATE INDEX IF NOT EXISTS idx_oplog_task ON operation_log(task_id);

-- Enforcement triggers
CREATE TRIGGER IF NOT EXISTS enforce_task_review_gate
BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'DONE' AND OLD.status != 'DONE'
BEGIN
  SELECT CASE WHEN (
    SELECT COUNT(*) FROM gate_checkpoints
    WHERE task_id = NEW.id
    AND gate_type = 'task-review'
    AND status = 'approved'
  ) = 0
  THEN RAISE(ABORT, 'Cannot mark task DONE: task-review gate not approved')
  END;
END;

CREATE TRIGGER IF NOT EXISTS enforce_preflight_gate
BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'IN_PROGRESS' AND OLD.status = 'TODO'
BEGIN
  SELECT CASE WHEN (
    SELECT COUNT(*) FROM gate_checkpoints
    WHERE task_id = NEW.id
    AND gate_type = 'approve'
    AND status = 'approved'
  ) = 0
  THEN RAISE(ABORT, 'Cannot start task: preflight gate not approved')
  END;
END;

CREATE TRIGGER IF NOT EXISTS enforce_dependencies
BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'IN_PROGRESS'
BEGIN
  SELECT CASE WHEN EXISTS (
    SELECT 1 FROM task_dependencies td
    JOIN tasks dep ON td.depends_on = dep.id
    WHERE td.task_id = NEW.id AND dep.status != 'DONE'
  )
  THEN RAISE(ABORT, 'Cannot start task: dependencies not met')
  END;
END;

CREATE TRIGGER IF NOT EXISTS update_story_timestamp
AFTER UPDATE ON tasks
BEGIN
  UPDATE stories SET updated_at = datetime('now') WHERE id = NEW.story_id;
END;

-- Insert schema version
INSERT OR REPLACE INTO schema_version (version) VALUES (1);
