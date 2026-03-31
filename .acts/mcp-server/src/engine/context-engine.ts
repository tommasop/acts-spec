import { StateReader, StoryState, Decision, RejectedApproach } from '../lib/state-reader.js';
import { SessionReader, SessionSummary } from '../lib/session-reader.js';

export interface ContextBundle {
  task_id: string;
  operation: string;
  plan_entry: string | null;
  decisions_override: Array<{
    topic: string;
    plan_said: string;
    decided: string;
    reason: string;
    authority: string;
  }>;
  rejected_approaches_from_other_tasks: Array<{
    source_task: string;
    approach: string;
    reason: string;
    tags: string[];
  }>;
  dependency_interfaces: Array<{
    task_id: string;
    status: string;
    files: string[];
  }>;
  scope: {
    will_do: string[];
    will_not_do: string[];
    files_may_modify: string[];
    files_owned_by_others: string[];
  };
  ownership: Record<string, { status: string; files: string[] }>;
  latest_sessions: SessionSummary[];
  budget: {
    allocated: number;
    used: number;
    remaining: number;
  };
}

export interface ContextGap {
  type: 'missing_dependency_read' | 'missing_agents_md' | 'missing_decisions' | 'scope_violation';
  message: string;
  severity: 'warning' | 'error';
  suggestion: string;
}

export interface LoopDetection {
  tool: string;
  args_hash: string;
  count: number;
  threshold: number;
  detected: boolean;
}

export class ContextEngine {
  private stateReader: StateReader;
  private sessionReader: SessionReader;
  private callHistory: Map<string, Array<{ tool: string; args_hash: string; timestamp: number }>> = new Map();
  private contextDelivered: Map<string, Set<string>> = new Map();

  constructor(stateReader: StateReader, sessionReader: SessionReader) {
    this.stateReader = stateReader;
    this.sessionReader = sessionReader;
  }

  async buildContextBundle(
    taskId: string,
    operation: string,
    budgetAllocated: number
  ): Promise<ContextBundle> {
    const state = await this.stateReader.readState();
    const decisions = await this.stateReader.readDecisions();
    const plan = await this.stateReader.readPlan();

    // Extract plan entry for this task
    const planEntry = this.extractPlanEntry(plan, taskId);

    // Find decisions that override plan
    const decisionsOverride = decisions.decisions
      .filter(d => d.task_id === taskId && d.plan_said)
      .map(d => ({
        topic: d.topic,
        plan_said: d.plan_said!,
        decided: d.decided,
        reason: d.reason,
        authority: d.authority,
      }));

    // Find rejected approaches from OTHER tasks
    const otherApproaches = decisions.rejected_approaches
      .filter(r => r.task_id !== taskId)
      .map(r => ({
        source_task: r.task_id,
        approach: r.approach,
        reason: r.reason,
        tags: r.tags || [],
      }));

    // Build dependency interfaces
    const task = state.tasks.find(t => t.id === taskId);
    const depInterfaces = (task?.depends_on || [])
      .map(depId => {
        const depTask = state.tasks.find(t => t.id === depId);
        return depTask ? {
          task_id: depId,
          status: depTask.status,
          files: depTask.files_touched,
        } : null;
      })
      .filter(Boolean) as Array<{ task_id: string; status: string; files: string[] }>;

    // Build scope
    const ownership: Record<string, { status: string; files: string[] }> = {};
    for (const t of state.tasks) {
      if (t.status === 'DONE' && t.files_touched.length > 0) {
        ownership[t.id] = { status: 'DONE', files: t.files_touched };
      }
    }

    const filesOwnedByOthers = Object.entries(ownership)
      .filter(([id]) => id !== taskId)
      .flatMap(([, entry]) => entry.files);

    // Read latest sessions
    const latestSessions = await this.sessionReader.readLatestSessions(taskId, 3);

    // Budget tracking
    const estimatedUsed = 4000 + (planEntry?.length || 0) * 2 + decisionsOverride.length * 200;
    const budgetUsed = Math.min(estimatedUsed, budgetAllocated);

    return {
      task_id: taskId,
      operation,
      plan_entry: planEntry,
      decisions_override: decisionsOverride,
      rejected_approaches_from_other_tasks: otherApproaches,
      dependency_interfaces: depInterfaces,
      scope: {
        will_do: [task?.title || ''],
        will_not_do: state.tasks.filter(t => t.id !== taskId).map(t => t.title),
        files_may_modify: task?.files_touched || [],
        files_owned_by_others: filesOwnedByOthers,
      },
      ownership,
      latest_sessions: latestSessions,
      budget: {
        allocated: budgetAllocated,
        used: budgetUsed,
        remaining: budgetAllocated - budgetUsed,
      },
    };
  }

  detectGaps(bundle: ContextBundle, state: StoryState): ContextGap[] {
    const gaps: ContextGap[] = [];

    // Check if dependency interfaces were loaded but dependencies aren't DONE
    for (const dep of bundle.dependency_interfaces) {
      if (dep.status !== 'DONE') {
        gaps.push({
          type: 'missing_dependency_read',
          message: `Dependency ${dep.task_id} is ${dep.status} (not DONE)`,
          severity: 'warning',
          suggestion: `Verify ${dep.task_id} status before proceeding. Check if interfaces have changed.`,
        });
      }
    }

    // Check if there are decisions from other tasks that might be relevant
    if (bundle.rejected_approaches_from_other_tasks.length > 0) {
      gaps.push({
        type: 'missing_decisions',
        message: `${bundle.rejected_approaches_from_other_tasks.length} rejected approaches from other tasks available`,
        severity: 'warning',
        suggestion: 'Review rejected approaches before implementing — similar patterns may apply to your task.',
      });
    }

    // Check scope violations
    if (bundle.scope.files_owned_by_others.length > 0) {
      gaps.push({
        type: 'scope_violation',
        message: `${bundle.scope.files_owned_by_others.length} files owned by completed tasks`,
        severity: 'warning',
        suggestion: 'Use acts_check_ownership before modifying any file.',
      });
    }

    return gaps;
  }

  detectLoop(taskId: string, tool: string, argsHash: string, threshold: number): LoopDetection {
    const key = taskId;
    if (!this.callHistory.has(key)) {
      this.callHistory.set(key, []);
    }

    const history = this.callHistory.get(key)!;
    const now = Date.now();

    // Clean old entries (> 5 minutes)
    const recent = history.filter(h => now - h.timestamp < 5 * 60 * 1000);
    this.callHistory.set(key, recent);

    // Count identical calls
    const sameCalls = recent.filter(h => h.tool === tool && h.args_hash === argsHash);
    sameCalls.push({ tool, args_hash: argsHash, timestamp: now });

    return {
      tool,
      args_hash: argsHash,
      count: sameCalls.length,
      threshold,
      detected: sameCalls.length >= threshold,
    };
  }

  trackContextDelivery(taskId: string, delivered: string): void {
    if (!this.contextDelivered.has(taskId)) {
      this.contextDelivered.set(taskId, new Set());
    }
    this.contextDelivered.get(taskId)!.add(delivered);
  }

  hasDelivered(taskId: string, item: string): boolean {
    return this.contextDelivered.get(taskId)?.has(item) ?? false;
  }

  getDeliveredItems(taskId: string): string[] {
    return [...(this.contextDelivered.get(taskId) || [])];
  }

  resetDeliveryTracking(taskId: string): void {
    this.contextDelivered.delete(taskId);
  }

  private extractPlanEntry(plan: string, taskId: string): string | null {
    const lines = plan.split('\n');
    let capturing = false;
    let entry: string[] = [];

    for (const line of lines) {
      // Match task header like "### T3" or "## T3:"
      const headerMatch = line.match(/^#{2,3}\s+T(\d+)/);
      if (headerMatch) {
        if (capturing) break;
        if (`T${headerMatch[1]}` === taskId) {
          capturing = true;
          entry.push(line);
          continue;
        }
      } else if (capturing) {
        entry.push(line);
      }
    }

    return entry.length > 0 ? entry.join('\n').trim() : null;
  }
}
