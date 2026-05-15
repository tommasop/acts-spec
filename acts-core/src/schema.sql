-- ACTS Core v1.1.0 Schema
-- All tables, indexes, and triggers for multi-story development

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
    status TEXT NOT NULL CHECK(status IN ('ANALYSIS','APPROVED','IN_PROGRESS','REVIEW','DONE','MERGED','ARCHIVED')),
    spec_approved INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    context_budget INTEGER NOT NULL DEFAULT 50000,
    session_count INTEGER DEFAULT 0,
    compressed INTEGER DEFAULT 0,
    strict_mode INTEGER DEFAULT 0,
    metadata TEXT,
    -- Phase 1: story type
    type TEXT DEFAULT 'feature' CHECK(type IN ('feature','maintenance','epic','spike')),
    -- Phase 2: multi-story
    branch TEXT,
    worktree_path TEXT,
    parent_story TEXT REFERENCES stories(id),
    archived_at INTEGER,
    semver TEXT,
    released_at INTEGER
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
    reviewed_by TEXT,
    review_metadata TEXT,
    -- Phase 1: labels for changelog generation
    labels TEXT
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

-- Phase 2: Story-level gates
CREATE TABLE IF NOT EXISTS story_gates (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    story_id TEXT NOT NULL REFERENCES stories(id),
    gate_type TEXT NOT NULL CHECK(gate_type IN ('story-approve','story-merge','architecture-discuss')),
    status TEXT NOT NULL CHECK(status IN ('pending','approved','changes_requested')),
    approved_by TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
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

-- Phase 2: Active story tracking (one at a time)
CREATE TABLE IF NOT EXISTS active_story (
    story_id TEXT PRIMARY KEY REFERENCES stories(id),
    activated_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
);

-- Phase 3: Dependency unblock notifications
CREATE TABLE IF NOT EXISTS unblock_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    unblocked_task_id TEXT NOT NULL REFERENCES tasks(id),
    unblocked_by TEXT NOT NULL REFERENCES tasks(id),
    created_at TEXT DEFAULT (datetime('now')),
    acknowledged INTEGER DEFAULT 0
);

-- Phase 3: Review queue
CREATE TABLE IF NOT EXISTS review_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id TEXT NOT NULL REFERENCES tasks(id),
    requested_by TEXT,
    requested_at TEXT DEFAULT (datetime('now')),
    assigned_to TEXT,
    status TEXT DEFAULT 'pending' CHECK(status IN ('pending','in_review','approved','rejected'))
);

-- Phase 3: Agent presence tracking
CREATE TABLE IF NOT EXISTS agent_presence (
    agent_id TEXT PRIMARY KEY,
    story_id TEXT REFERENCES stories(id),
    task_id TEXT REFERENCES tasks(id),
    current_action TEXT,
    heartbeat INTEGER NOT NULL
);

-- Phase 3: Gate SLA tracking
CREATE TABLE IF NOT EXISTS gate_sla (
    gate_id INTEGER PRIMARY KEY REFERENCES gate_checkpoints(id),
    deadline TEXT NOT NULL,
    breached INTEGER DEFAULT 0
);

-- Phase 2: Cross-story file conflict detection
CREATE TABLE IF NOT EXISTS file_conflicts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    file_path TEXT NOT NULL,
    story_a TEXT NOT NULL,
    story_b TEXT NOT NULL,
    detected_at TEXT DEFAULT (datetime('now')),
    resolved INTEGER DEFAULT 0
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_tasks_story ON tasks(story_id);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_gate_task ON gate_checkpoints(task_id);
CREATE INDEX IF NOT EXISTS idx_decisions_task ON decisions(task_id);
CREATE INDEX IF NOT EXISTS idx_approaches_task ON rejected_approaches(task_id);
CREATE INDEX IF NOT EXISTS idx_questions_task ON open_questions(task_id);
CREATE INDEX IF NOT EXISTS idx_oplog_task ON operation_log(task_id);
CREATE INDEX IF NOT EXISTS idx_story_gates_story ON story_gates(story_id);
CREATE INDEX IF NOT EXISTS idx_unblock_task ON unblock_events(unblocked_task_id);
CREATE INDEX IF NOT EXISTS idx_review_queue_task ON review_queue(task_id);
CREATE INDEX IF NOT EXISTS idx_presence_heartbeat ON agent_presence(heartbeat);
CREATE INDEX IF NOT EXISTS idx_gate_sla_deadline ON gate_sla(deadline);
CREATE INDEX IF NOT EXISTS idx_file_conflicts_path ON file_conflicts(file_path);
CREATE INDEX IF NOT EXISTS idx_task_files_path ON task_files(file_path);

-- ============================================================
-- ENFORCEMENT TRIGGERS
-- ============================================================

-- Preflight gate: cannot start task without approval
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

-- Phase 1: Auto-approve preflight for maintenance tasks
CREATE TRIGGER IF NOT EXISTS auto_approve_maintenance_preflight
BEFORE UPDATE OF status ON tasks
WHEN NEW.status = 'IN_PROGRESS' AND OLD.status = 'TODO'
BEGIN
    INSERT OR IGNORE INTO gate_checkpoints (task_id, gate_type, status, approved_by)
    SELECT NEW.id, 'approve', 'approved', '__system__'
    FROM tasks t WHERE t.id = NEW.id AND t.story_id = '__maintenance__';
END;

-- Dependencies: cannot start if deps not done
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

-- Task review gate: cannot mark DONE without approved review
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

-- Phase 2: Cross-story file ownership enforcement
CREATE TRIGGER IF NOT EXISTS enforce_cross_story_ownership
BEFORE INSERT ON task_files
BEGIN
    SELECT CASE WHEN EXISTS(
        SELECT 1 FROM task_files tf
        JOIN tasks t ON t.id = tf.task_id
        WHERE tf.file_path = NEW.file_path
        AND t.story_id != (SELECT story_id FROM tasks WHERE id = NEW.task_id)
        AND t.status = 'DONE'
    ) THEN RAISE(ABORT, 'File already owned by a DONE task in another story')
    END;
END;

-- Phase 2: Story merge enforcement
CREATE TRIGGER IF NOT EXISTS enforce_story_merge
BEFORE UPDATE OF status ON stories
WHEN NEW.status = 'MERGED' AND OLD.status != 'MERGED'
BEGIN
    SELECT CASE WHEN EXISTS(
        SELECT 1 FROM tasks WHERE story_id = NEW.id AND status != 'DONE'
    ) THEN RAISE(ABORT, 'Cannot merge story: open tasks remain')
    END;
    SELECT CASE WHEN EXISTS(
        SELECT 1 FROM tasks t
        WHERE t.story_id = NEW.id AND t.status = 'DONE'
        AND NOT EXISTS (
            SELECT 1 FROM gate_checkpoints gc
            WHERE gc.task_id = t.id AND gc.gate_type = 'task-review'
            AND gc.status = 'approved'
        )
    ) THEN RAISE(ABORT, 'Cannot merge story: tasks without approved review')
    END;
END;

-- Phase 2: Active story singleton enforcement
CREATE TRIGGER IF NOT EXISTS single_active_story
BEFORE INSERT ON active_story
BEGIN
    SELECT CASE WHEN (SELECT COUNT(*) FROM active_story) > 0
    THEN RAISE(ABORT, 'Only one active story. Run: acts story switch <id>')
    END;
END;

-- Update story timestamp on task change
CREATE TRIGGER IF NOT EXISTS update_story_timestamp
AFTER UPDATE ON tasks
BEGIN
    UPDATE stories SET updated_at = datetime('now') WHERE id = NEW.story_id;
END;

-- ============================================================
-- PROACTIVE TRIGGERS (create useful state)
-- ============================================================

-- Phase 3: Auto-fire unblock event when dependency completes
CREATE TRIGGER IF NOT EXISTS notify_dependency_unblock
AFTER UPDATE OF status ON tasks
WHEN NEW.status = 'DONE' AND OLD.status != 'DONE'
BEGIN
    INSERT INTO unblock_events (unblocked_task_id, unblocked_by)
    SELECT td.task_id, NEW.id
    FROM task_dependencies td
    WHERE td.depends_on = NEW.id;
END;

-- Phase 3: Auto-enqueue review when task-review gate is created
CREATE TRIGGER IF NOT EXISTS auto_enqueue_review
AFTER INSERT ON gate_checkpoints
WHEN NEW.gate_type = 'task-review' AND NEW.status = 'pending'
BEGIN
    INSERT INTO review_queue (task_id, requested_by)
    SELECT NEW.task_id, t.assigned_to
    FROM tasks t WHERE t.id = NEW.task_id;
END;

-- Phase 3: Auto-cleanup stale agent presence (>5 min)
CREATE TRIGGER IF NOT EXISTS cleanup_stale_presence
AFTER INSERT ON agent_presence
BEGIN
    DELETE FROM agent_presence
    WHERE heartbeat < (strftime('%s','now') - 300);
END;

-- Phase 3: Set review SLA (24h default)
CREATE TRIGGER IF NOT EXISTS set_review_sla
AFTER INSERT ON gate_checkpoints
WHEN NEW.gate_type = 'task-review' AND NEW.status = 'pending'
BEGIN
    INSERT INTO gate_sla (gate_id, deadline)
    VALUES (NEW.id, datetime('now', '+24 hours'));
END;

-- Phase 2: Detect active file conflicts between stories
CREATE TRIGGER IF NOT EXISTS detect_file_conflict
AFTER INSERT ON task_files
BEGIN
    INSERT INTO file_conflicts (file_path, story_a, story_b)
    SELECT NEW.file_path,
           (SELECT story_id FROM tasks WHERE id = NEW.task_id),
           t.story_id
    FROM task_files tf
    JOIN tasks t ON t.id = tf.task_id
    WHERE tf.file_path = NEW.file_path
    AND t.story_id != (SELECT story_id FROM tasks WHERE id = NEW.task_id)
    AND t.status IN ('IN_PROGRESS', 'TODO')
    AND NOT EXISTS (
        SELECT 1 FROM file_conflicts fc
        WHERE fc.file_path = NEW.file_path AND fc.resolved = 0
    );
END;

-- Insert schema version
INSERT OR REPLACE INTO schema_version (version) VALUES (5);
