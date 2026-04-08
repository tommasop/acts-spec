import { readFile, readdir, stat } from 'node:fs/promises';
import { join, resolve } from 'node:path';

export interface TaskState {
  id: string;
  title: string;
  status: 'TODO' | 'IN_PROGRESS' | 'BLOCKED' | 'DONE';
  assigned_to: string | null;
  files_touched: string[];
  depends_on: string[];
  context_priority?: number;
}

export interface StoryState {
  acts_version: string;
  story_id: string;
  title: string;
  status: 'ANALYSIS' | 'APPROVED' | 'IN_PROGRESS' | 'REVIEW' | 'DONE';
  spec_approved: boolean;
  created_at: string;
  updated_at: string;
  context_budget: number;
  tasks: TaskState[];
  session_count?: number;
  compressed?: boolean;
  metadata?: Record<string, unknown>;
  mcp_context?: {
    anchor_version?: number;
    decisions_count?: number;
    last_compaction?: string;
    loop_warnings?: number;
  };
}

export interface StoryBoardEntry {
  task_id: string;
  title: string;
  status: string;
  assigned_to: string | null;
  files_count: number;
  depends_on: string[];
}

export interface OwnershipMap {
  [taskId: string]: {
    status: string;
    files: string[];
  };
}

export interface ScopeDeclaration {
  task_id: string;
  will_do: string[];
  will_not_do: string[];
  files_may_modify: string[];
  files_owned_by_others: string[];
}

export class StateReader {
  private repoRoot: string;
  private storyDir: string;

  constructor(repoRoot: string) {
    this.repoRoot = resolve(repoRoot);
    this.storyDir = join(this.repoRoot, '.story');
  }

  async readState(): Promise<StoryState> {
    const path = join(this.storyDir, 'state.json');
    const raw = await readFile(path, 'utf-8');
    return JSON.parse(raw) as StoryState;
  }

  async readPlan(): Promise<string> {
    const path = join(this.storyDir, 'plan.md');
    return readFile(path, 'utf-8');
  }

  async readSpec(): Promise<string> {
    const path = join(this.storyDir, 'spec.md');
    return readFile(path, 'utf-8');
  }

  async readAgentsMd(): Promise<string> {
    const path = join(this.repoRoot, 'AGENTS.md');
    return readFile(path, 'utf-8');
  }

  async readTaskNotes(taskId: string): Promise<string | null> {
    const path = join(this.storyDir, 'tasks', taskId, 'notes.md');
    try {
      return await readFile(path, 'utf-8');
    } catch {
      return null;
    }
  }

  async readDecisions(): Promise<DecisionsFile> {
    const path = join(this.storyDir, 'decisions.json');
    try {
      const raw = await readFile(path, 'utf-8');
      return JSON.parse(raw) as DecisionsFile;
    } catch {
      return { decisions: [], rejected_approaches: [], open_questions: [] };
    }
  }

  async writeDecisions(data: DecisionsFile): Promise<void> {
    const path = join(this.storyDir, 'decisions.json');
    const { writeFile } = await import('node:fs/promises');
    await writeFile(path, JSON.stringify(data, null, 2) + '\n', 'utf-8');
  }

  async writeState(state: StoryState): Promise<void> {
    const path = join(this.storyDir, 'state.json');
    state.updated_at = new Date().toISOString();
    const { writeFile } = await import('node:fs/promises');
    await writeFile(path, JSON.stringify(state, null, 2) + '\n', 'utf-8');
  }

  async readActsManifest(): Promise<Record<string, unknown>> {
    const path = join(this.repoRoot, '.acts', 'acts.json');
    const raw = await readFile(path, 'utf-8');
    return JSON.parse(raw);
  }

  buildStoryboard(state: StoryState): StoryBoardEntry[] {
    return state.tasks.map(t => ({
      task_id: t.id,
      title: t.title,
      status: t.status,
      assigned_to: t.assigned_to,
      files_count: t.files_touched.length,
      depends_on: t.depends_on,
    }));
  }

  buildOwnershipMap(state: StoryState): OwnershipMap {
    const map: OwnershipMap = {};
    for (const task of state.tasks) {
      if (task.status === 'DONE' && task.files_touched.length > 0) {
        map[task.id] = { status: 'DONE', files: task.files_touched };
      }
    }
    return map;
  }

  buildScopeDeclaration(state: StoryState, taskId: string): ScopeDeclaration | null {
    const task = state.tasks.find(t => t.id === taskId);
    if (!task) return null;

    // Parse plan.md to find task's likely files
    const ownership = this.buildOwnershipMap(state);
    const ownedFiles = new Set<string>();
    for (const entry of Object.values(ownership)) {
      for (const f of entry.files) ownedFiles.add(f);
    }

    const filesOwnedByOthers: string[] = [];
    for (const [tId, entry] of Object.entries(ownership)) {
      if (tId !== taskId) {
        filesOwnedByOthers.push(...entry.files);
      }
    }

    return {
      task_id: taskId,
      will_do: [task.title],
      will_not_do: state.tasks
        .filter(t => t.id !== taskId)
        .map(t => t.title),
      files_may_modify: task.files_touched,
      files_owned_by_others: filesOwnedByOthers,
    };
  }

  async listSessions(): Promise<string[]> {
    const sessionsDir = join(this.storyDir, 'sessions');
    try {
      const files = await readdir(sessionsDir);
      return files
        .filter(f => f.endsWith('.md'))
        .sort()
        .reverse(); // newest first
    } catch {
      return [];
    }
  }
}

export interface Decision {
  task_id: string;
  timestamp: string;
  session: string;
  topic: string;
  plan_said?: string;
  decided: string;
  reason: string;
  evidence: string;
  authority: 'developer_approved' | 'agent_decided';
  tags?: string[];
}

export interface RejectedApproach {
  task_id: string;
  timestamp: string;
  session: string;
  approach: string;
  reason: string;
  evidence: string;
  tags?: string[];
}

export interface OpenQuestion {
  task_id: string;
  question: string;
  raised_by: string;
  raised_at?: string;
  status: 'unresolved' | 'resolved' | 'deferred';
  resolution?: string;
  resolved_by?: string;
}

export interface DecisionsFile {
  decisions: Decision[];
  rejected_approaches: RejectedApproach[];
  open_questions: OpenQuestion[];
}
