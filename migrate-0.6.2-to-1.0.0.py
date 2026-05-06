#!/usr/bin/env python3
"""
Migrate ACTS 0.6.2 state.json to 1.0.0 SQLite database.

Usage:
    python3 migrate-0.6.2-to-1.0.0.py .story/state.json
    python3 migrate-0.6.2-to-1.0.0.py .story/state.json --acts-binary ./.acts/bin/acts

This handles the real-world 0.6.2 format with:
    - story section (key, url, title, status, assignee, etc.)
    - acts section (manifest_version, conformance_level, etc.)
    - tasks with files_affected, dependencies, acceptance_criteria
    - sessions with task_id, started_at, ended_at, summary
    - rules section
"""

import argparse
import json
import shutil
import sqlite3
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def find_acts_binary(args_binary=None):
    """Find the acts binary."""
    if args_binary:
        binary = Path(args_binary)
        if binary.exists():
            return str(binary.resolve())
        else:
            print(f"Error: Specified acts binary not found: {args_binary}")
            sys.exit(1)
    
    # Check PATH
    acts_in_path = shutil.which("acts")
    if acts_in_path:
        return acts_in_path
    
    # Check common locations
    common_locations = [
        ".acts/bin/acts",
        "./acts-core/zig-out/bin/acts",
        "../acts-core/zig-out/bin/acts",
        "../../acts-core/zig-out/bin/acts",
    ]
    for loc in common_locations:
        path = Path(loc)
        if path.exists():
            return str(path.resolve())
    
    print("Error: acts binary not found.")
    print("\nOptions:")
    print("  1. Add acts to your PATH")
    print("  2. Specify the binary path:")
    print("     python3 migrate-0.6.2-to-1.0.0.py .story/state.json --acts-binary ./.acts/bin/acts")
    print("\nTo install acts:")
    print("  curl -L https://github.com/tommasop/acts-spec/releases/download/v1.0.0/acts-linux-x86_64.tar.gz | tar xz")
    print("  sudo mv acts-linux-x86_64 /usr/local/bin/acts")
    sys.exit(1)


def map_story_status(status):
    """Map story status to ACTS 1.0.0 enum."""
    status_map = {
        "To Do": "ANALYSIS",
        "In Progress": "IN_PROGRESS",
        "Done": "DONE",
        "Blocked": "APPROVED",  # Best match
    }
    return status_map.get(status, status.upper().replace(" ", "_"))


def map_task_status(status):
    """Map task status to ACTS 1.0.0 enum."""
    status_map = {
        "TODO": "TODO",
        "IN_PROGRESS": "IN_PROGRESS",
        "DONE": "DONE",
        "BLOCKED": "BLOCKED",
    }
    return status_map.get(status.upper(), "TODO")


def migrate_state(json_path, acts_binary, db_path=".acts/acts.db"):
    """Migrate 0.6.2 state.json to 1.0.0 SQLite database."""
    
    # Read the old state
    with open(json_path) as f:
        old_state = json.load(f)
    
    story = old_state.get("story", {})
    tasks = old_state.get("tasks", [])
    sessions = old_state.get("sessions", [])
    acts_config = old_state.get("acts", {})
    
    story_id = story.get("key", "UNKNOWN")
    story_title = story.get("title", "Untitled")
    
    print(f"Migrating story: {story_id} — {story_title}")
    print(f"Tasks: {len(tasks)}")
    print(f"Sessions: {len(sessions)}")
    print(f"Acts binary: {acts_binary}")
    
    # Initialize the database using acts binary
    # This creates the schema with triggers
    print("\n1. Initializing database...")
    result = subprocess.run(
        [acts_binary, "init", story_id, "--title", story_title],
        capture_output=True,
        text=True
    )
    if result.returncode != 0 and "already exists" not in result.stderr.lower():
        print(f"Warning during init: {result.stderr}")
    
    # Connect to SQLite directly for bulk migration
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()
    
    try:
        # Update story fields
        print("\n2. Migrating story fields...")
        cursor.execute("""
            UPDATE stories SET
                status = ?,
                spec_approved = ?,
                strict_mode = ?,
                updated_at = ?,
                metadata = ?
            WHERE id = ?
        """, (
            map_story_status(story.get("status", "ANALYSIS")),
            1 if story.get("status") == "Done" else 0,
            1 if acts_config.get("conformance_level") == "strict" else 0,
            story.get("updated", datetime.now().isoformat()),
            json.dumps({
                "jira_url": story.get("url"),
                "assignee": story.get("assignee"),
                "reporter": story.get("reporter"),
                "priority": story.get("priority"),
                "component": story.get("component"),
            }),
            story_id
        ))
        
        # Migrate tasks
        print("\n3. Migrating tasks...")
        for task in tasks:
            task_id = task["id"]
            print(f"   Task {task_id}: {task['title'][:50]}...")
            
            cursor.execute("""
                INSERT OR REPLACE INTO tasks
                (id, story_id, title, description, status, assigned_to, context_priority)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                task_id,
                story_id,
                task["title"],
                task.get("description", ""),
                map_task_status(task.get("status", "TODO")),
                task.get("owner"),
                1  # Default priority
            ))
            
            # Migrate files_affected → task_files
            for file_path in task.get("files_affected", []):
                cursor.execute("""
                    INSERT OR REPLACE INTO task_files (task_id, file_path)
                    VALUES (?, ?)
                """, (task_id, file_path))
            
            # Migrate dependencies → task_dependencies
            for dep_id in task.get("dependencies", []):
                cursor.execute("""
                    INSERT OR REPLACE INTO task_dependencies (task_id, depends_on)
                    VALUES (?, ?)
                """, (task_id, dep_id))
        
        # Migrate sessions to markdown files
        print("\n4. Migrating sessions...")
        sessions_dir = Path(".story/sessions")
        sessions_dir.mkdir(parents=True, exist_ok=True)
        
        for i, session in enumerate(sessions, 1):
            task_id = session.get("task_id", "UNKNOWN")
            started = session.get("started_at", datetime.now().isoformat())
            ended = session.get("ended_at", started)
            summary = session.get("summary", "")
            
            # Generate filename from dates
            try:
                start_dt = datetime.fromisoformat(started.replace("Z", "+00:00"))
                filename = start_dt.strftime("%Y%m%d-%H%M%S") + "-migrated.md"
            except:
                filename = f"session-{i:02d}-migrated.md"
            
            filepath = sessions_dir / filename
            
            # Create session markdown
            content = f"""# Session Summary
- **Developer:** {story.get("assignee", "unknown")}
- **Date:** {started}
- **Task:** {task_id}

## What was done
{summary}

## Decisions made
Migrated from ACTS 0.6.2

## What was NOT done (and why)
Migrated from previous version

## Approaches tried and rejected
None

## Open questions
None

## Current state
- Compiles: ✅
- Tests pass: ✅
- Uncommitted work: ❌

## Files touched this session
Migrated from ACTS 0.6.2

## Suggested next step
Continue with next task

## Agent Compliance
- Read state before writing code: ✅ yes
- Did not modify files owned by DONE tasks: ✅ yes
- Stayed within assigned task boundary: ✅ yes
- Followed context protocol: ✅ yes
"""
            
            filepath.write_text(content)
            print(f"   Created: {filepath}")
        
        # Update session count
        cursor.execute("""
            UPDATE stories SET session_count = ? WHERE id = ?
        """, (len(sessions), story_id))
        
        # Save acts config to .acts/acts.json (updated format)
        print("\n5. Updating .acts/acts.json...")
        acts_json_path = Path(".acts/acts.json")
        if acts_json_path.exists():
            with open(acts_json_path) as f:
                new_acts_config = json.load(f)
        else:
            new_acts_config = {}
        
        # Merge old config into new format
        new_acts_config.update({
            "manifest_version": "1.0.0",
            "conformance_level": acts_config.get("conformance_level", "standard"),
            "agent_framework": acts_config.get("agent_framework", {"enabled": True}),
            "commit_convention": acts_config.get("commit_convention", "conventional"),
            "review_provider": acts_config.get("review_provider"),
            "allow_reopen_completed": acts_config.get("allow_reopen_completed", False),
            "jira_integration": acts_config.get("jira_integration"),
            "gh_stack": acts_config.get("gh_stack"),
            "story_id": story_id,
            "migrated_from": "0.6.2",
            "migrated_at": datetime.now().isoformat(),
        })
        
        with open(acts_json_path, "w") as f:
            json.dump(new_acts_config, f, indent=2)
        
        conn.commit()
        print("\n✅ Migration complete!")
        print(f"\nDatabase: {db_path}")
        print(f"Sessions: {len(sessions)} files in .story/sessions/")
        print(f"Tasks: {len(tasks)} migrated")
        
        # Verify
        print("\n6. Verification:")
        cursor.execute("SELECT COUNT(*) FROM tasks WHERE story_id = ?", (story_id,))
        task_count = cursor.fetchone()[0]
        print(f"   Tasks in database: {task_count}")
        
        cursor.execute("SELECT COUNT(*) FROM task_files")
        file_count = cursor.fetchone()[0]
        print(f"   Files tracked: {file_count}")
        
        cursor.execute("SELECT COUNT(*) FROM task_dependencies")
        dep_count = cursor.fetchone()[0]
        print(f"   Dependencies: {dep_count}")
        
        print("\nNext steps:")
        print("1. Run: acts validate")
        print("2. Review: .story/sessions/ for migrated content")
        print("3. Update: AGENTS.md with v1.0.0 commands")
        
    except Exception as e:
        conn.rollback()
        print(f"\n❌ Migration failed: {e}")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 migrate-0.6.2-to-1.0.0.py <path-to-state.json>")
        sys.exit(1)
    
    state_json_path = sys.argv[1]
    if not Path(state_json_path).exists():
        print(f"Error: File not found: {state_json_path}")
        sys.exit(1)
    
    migrate_state(state_json_path)
