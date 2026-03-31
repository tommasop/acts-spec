import { StateReader, StoryState } from '../lib/state-reader.js';

export interface ContextAnchor {
  story_id: string;
  current_task: string;
  phase: string;
  goal: string;
  not_goal: string[];
  key_decisions: string[];
  files_owned: Record<string, string[]>;
  constraints: string[];
  updated_at: string;
  turn_count: number;
}

export class AnchorManager {
  private stateReader: StateReader;
  private anchors: Map<string, ContextAnchor> = new Map();

  constructor(stateReader: StateReader) {
    this.stateReader = stateReader;
  }

  async initialize(taskId: string, state: StoryState): Promise<ContextAnchor> {
    const decisions = await this.stateReader.readDecisions();
    const taskDecisions = decisions.decisions
      .filter(d => d.task_id === taskId)
      .map(d => `${d.topic}: ${d.decided}`);

    const ownership: Record<string, string[]> = {};
    for (const task of state.tasks) {
      if (task.status === 'DONE' && task.files_touched.length > 0) {
        ownership[task.id] = task.files_touched;
      }
    }

    const task = state.tasks.find(t => t.id === taskId);
    const deps = task?.depends_on || [];

    const constraints: string[] = [];
    for (const depId of deps) {
      const depTask = state.tasks.find(t => t.id === depId);
      if (depTask?.files_touched.length) {
        constraints.push(`Do not modify ${depId} files: ${depTask.files_touched.join(', ')}`);
      }
    }
    constraints.push('Stay within task scope per plan.md');

    const anchor: ContextAnchor = {
      story_id: state.story_id,
      current_task: taskId,
      phase: state.status === 'IN_PROGRESS' ? 'implementation' : 'unknown',
      goal: task?.title || 'Unknown task',
      not_goal: state.tasks
        .filter(t => t.id !== taskId)
        .map(t => `${t.id}: ${t.title}`),
      key_decisions: taskDecisions,
      files_owned: ownership,
      constraints,
      updated_at: new Date().toISOString(),
      turn_count: 0,
    };

    this.anchors.set(taskId, anchor);
    return anchor;
  }

  async update(taskId: string, updates: Partial<ContextAnchor>): Promise<ContextAnchor> {
    let anchor = this.anchors.get(taskId);
    if (!anchor) {
      const state = await this.stateReader.readState();
      anchor = await this.initialize(taskId, state);
    }

    if (updates.goal !== undefined) anchor.goal = updates.goal;
    if (updates.not_goal !== undefined) anchor.not_goal = updates.not_goal;
    if (updates.constraints !== undefined) anchor.constraints = updates.constraints;
    if (updates.key_decisions !== undefined) anchor.key_decisions = updates.key_decisions;

    anchor.turn_count = (anchor.turn_count || 0) + 1;
    anchor.updated_at = new Date().toISOString();

    // Refresh decisions from file
    const decisions = await this.stateReader.readDecisions();
    anchor.key_decisions = decisions.decisions
      .filter(d => d.task_id === taskId)
      .map(d => `${d.topic}: ${d.decided}`);

    // Refresh ownership from state
    const state = await this.stateReader.readState();
    const ownership: Record<string, string[]> = {};
    for (const task of state.tasks) {
      if (task.status === 'DONE' && task.files_touched.length > 0) {
        ownership[task.id] = task.files_touched;
      }
    }
    anchor.files_owned = ownership;

    this.anchors.set(taskId, anchor);
    return anchor;
  }

  get(taskId: string): ContextAnchor | undefined {
    return this.anchors.get(taskId);
  }

  format(anchor: ContextAnchor): string {
    let output = `## Context Anchor — ${anchor.current_task}\n\n`;
    output += `**Story**: ${anchor.story_id}\n`;
    output += `**Task**: ${anchor.current_task} (${anchor.phase})\n`;
    output += `**Goal**: ${anchor.goal}\n\n`;

    if (anchor.not_goal.length > 0) {
      output += `**NOT this task**:\n`;
      for (const ng of anchor.not_goal) {
        output += `- ${ng}\n`;
      }
      output += '\n';
    }

    if (anchor.constraints.length > 0) {
      output += `**Constraints**:\n`;
      for (const c of anchor.constraints) {
        output += `- ${c}\n`;
      }
      output += '\n';
    }

    if (anchor.key_decisions.length > 0) {
      output += `**Decisions made**:\n`;
      for (const d of anchor.key_decisions) {
        output += `- ${d}\n`;
      }
      output += '\n';
    }

    if (Object.keys(anchor.files_owned).length > 0) {
      output += `**File ownership**:\n`;
      for (const [taskId, files] of Object.entries(anchor.files_owned)) {
        output += `- ${taskId} (DONE): ${files.join(', ')}\n`;
      }
      output += '\n';
    }

    output += `**Turn count**: ${anchor.turn_count} | **Updated**: ${anchor.updated_at}\n`;
    return output;
  }
}
