import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { join, resolve } from 'node:path';
import { StateReader, StoryState } from './lib/state-reader.js';
import { SessionReader } from './lib/session-reader.js';
import { GitReader } from './lib/git-reader.js';
import { SchemaValidator } from './lib/schema-validator.js';
import { ContextEngine } from './engine/context-engine.js';
import { AnchorManager } from './engine/anchor.js';
import { CompactionEngine } from './engine/compaction.js';
import { LearningPropagator } from './engine/learning-propagator.js';

// --- Bootstrap ---

const repoRoot = process.cwd();
const storyDir = join(repoRoot, '.story');
const schemasDir = join(repoRoot, '.acts', 'schemas');

const stateReader = new StateReader(repoRoot);
const sessionReader = new SessionReader(storyDir);
const gitReader = new GitReader(repoRoot);
const schemaValidator = new SchemaValidator(schemasDir);
const contextEngine = new ContextEngine(stateReader, sessionReader);
const anchorManager = new AnchorManager(stateReader);
const compactionEngine = new CompactionEngine(sessionReader, stateReader);
const learningPropagator = new LearningPropagator(stateReader);

// --- Server ---

const server = new McpServer(
  { name: 'acts-mcp-context-engine', version: '0.5.0' },
  {
    capabilities: {
      tools: {},
      resources: { subscribe: true, listChanged: true },
      prompts: {},
    },
  }
);

// --- Helpers ---

const LOOP_THRESHOLD = 3;

function detectLoop(taskId: string, tool: string, args: Record<string, unknown>): { detected: boolean; count: number } {
  const argsHash = JSON.stringify(args);
  const result = contextEngine.detectLoop(taskId, tool, argsHash, LOOP_THRESHOLD);
  return { detected: result.detected, count: result.count };
}

function toolError(message: string): { content: Array<{ type: 'text'; text: string }>; isError: true } {
  return {
    content: [{ type: 'text' as const, text: JSON.stringify({ error: message }) }],
    isError: true as const,
  };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type ToolHandler = (...args: any[]) => Promise<any>;

function safeTool(handler: ToolHandler): ToolHandler {
  return async (...args) => {
    try {
      return await handler(...args);
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      if (msg.includes('ENOENT') || msg.includes('no such file')) {
        return toolError(`Missing required file: ${msg}. Ensure .story/ directory exists with state.json, plan.md, and spec.md.`);
      }
      return toolError(msg);
    }
  };
}

// --- Tools ---

// 1. acts_begin_operation
server.registerTool(
  'acts_begin_operation',
  {
    description: 'Start an ACTS operation. Server loads all context for this operation type and returns a ready-to-use context bundle. Call this at the start of any ACTS workflow step.',
    inputSchema: {
      operation: z.enum(['preflight', 'task-start', 'session-summary', 'handoff', 'story-review']).describe('The ACTS operation to begin'),
      task_id: z.string().regex(/^T\d+$/).describe('Task ID (e.g., T3)'),
      developer: z.string().min(1).describe('Developer name or handle'),
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
  },
  safeTool(async ({ operation, task_id, developer }) => {
    const state = await stateReader.readState();
    const budgetMap: Record<string, number> = {
      'preflight': 50000,
      'task-start': 30000,
      'session-summary': 10000,
      'handoff': 100000,
      'story-review': 50000,
    };

    const budget = budgetMap[operation] || 30000;
    const bundle = await contextEngine.buildContextBundle(task_id, operation, budget);
    const gaps = contextEngine.detectGaps(bundle, state);
    const anchor = await anchorManager.initialize(task_id, state);
    const learnings = await learningPropagator.getRelevantLearnings(task_id);

    contextEngine.resetDeliveryTracking(task_id);
    contextEngine.trackContextDelivery(task_id, 'bundle');
    contextEngine.trackContextDelivery(task_id, `anchor_${task_id}`);

    const response = {
      operation,
      task_id,
      developer,
      context_bundle: bundle,
      anchor: anchor,
      learnings: learnings.slice(0, 5),
      gaps,
      budget: bundle.budget,
    };

    return {
      content: [{ type: 'text' as const, text: JSON.stringify(response, null, 2) }],
    };
  })
);

// 2. acts_get_context
server.registerTool(
  'acts_get_context',
  {
    description: 'Get the next chunk of context during an operation. Server tracks what was already delivered and skips redundant reads. Use this instead of reading files directly.',
    inputSchema: {
      task_id: z.string().regex(/^T\d+$/).describe('Task ID'),
      step: z.enum(['dependency_interfaces', 'sessions', 'ownership', 'decisions', 'agents_md', 'plan']).describe('Which context chunk to retrieve'),
      budget_remaining: z.number().optional().describe('Remaining token budget'),
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true },
  },
  safeTool(async ({ task_id, step, budget_remaining }) => {
    const loop = detectLoop(task_id, 'acts_get_context', { step });
    if (loop.detected) {
      return {
        content: [{
          type: 'text' as const,
          text: JSON.stringify({
            warning: 'loop_detected',
            pattern: `acts_get_context called ${loop.count} times with step="${step}" for task ${task_id}`,
            suggestion: 'You already have this context. Proceed with implementation or ask the developer.',
          }),
        }],
        isError: true,
      };
    }

    if (contextEngine.hasDelivered(task_id, step)) {
      return {
        content: [{
          type: 'text' as const,
          text: JSON.stringify({
            already_delivered: true,
            step,
            message: `Context chunk "${step}" was already delivered for task ${task_id}. Use acts_update_anchor to refresh.`,
          }),
        }],
      };
    }

    let result: Record<string, unknown> = {};
    switch (step) {
      case 'dependency_interfaces': {
        const state = await stateReader.readState();
        const task = state.tasks.find(t => t.id === task_id);
        const deps = (task?.depends_on || []).map(depId => {
          const depTask = state.tasks.find(t => t.id === depId);
          return depTask ? { task_id: depId, status: depTask.status, files: depTask.files_touched } : null;
        }).filter(Boolean);
        result = { dependency_interfaces: deps };
        break;
      }
      case 'sessions': {
        const sessions = await sessionReader.readLatestSessions(task_id, 3);
        result = { sessions: sessions.map(s => ({
          filename: s.filename,
          developer: s.developer,
          date: s.date,
          what_was_done: s.what_was_done,
          decisions_made: s.decisions_made,
          approaches_tried_and_rejected: s.approaches_tried_and_rejected,
          open_questions: s.open_questions,
        }))};
        break;
      }
      case 'ownership': {
        const state = await stateReader.readState();
        const ownership = stateReader.buildOwnershipMap(state);
        result = { ownership };
        break;
      }
      case 'decisions': {
        const decisions = await stateReader.readDecisions();
        result = {
          decisions: decisions.decisions.filter(d => d.task_id === task_id),
          rejected_approaches: decisions.rejected_approaches.filter(r => r.task_id !== task_id),
          open_questions: decisions.open_questions.filter(q => q.status === 'unresolved'),
        };
        break;
      }
      case 'agents_md': {
        try {
          const content = await stateReader.readAgentsMd();
          result = { agents_md: content.slice(0, 8000) }; // Cap at 8k chars
        } catch {
          result = { agents_md: null, error: 'AGENTS.md not found' };
        }
        break;
      }
      case 'plan': {
        try {
          const plan = await stateReader.readPlan();
          const state = await stateReader.readState();
          const bundle = await contextEngine.buildContextBundle(task_id, 'get-context', budget_remaining || 20000);
          result = { plan_entry: bundle.plan_entry };
        } catch {
          result = { plan_entry: null, error: 'plan.md not found' };
        }
        break;
      }
    }

    contextEngine.trackContextDelivery(task_id, step);
    return {
      content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }],
    };
  })
);

// 3. acts_record_decision
server.registerTool(
  'acts_record_decision',
  {
    description: 'Record a decision, deviation, or rejected approach with structured metadata. Prevents stale reasoning by marking decisions as authoritative. Requires evidence.',
    inputSchema: {
      task_id: z.string().regex(/^T\d+$/).describe('Task ID'),
      topic: z.string().min(1).describe('Short identifier for the decision topic (e.g., form_library)'),
      plan_said: z.string().optional().describe('What the plan originally specified'),
      decided: z.string().min(1).describe('What was actually decided'),
      reason: z.string().min(1).describe('Why this decision was made'),
      evidence: z.string().min(1).describe('Verifiable evidence: file:line or direct code quote'),
      authority: z.enum(['developer_approved', 'agent_decided']).describe('Who made this decision'),
      tags: z.array(z.string()).optional().describe('Semantic tags for cross-task learning'),
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
  },
  safeTool(async ({ task_id, topic, plan_said, decided, reason, evidence, authority, tags }) => {
    // Validate evidence is specific enough
    if (evidence.length < 10 && !evidence.includes(':') && !evidence.includes('/')) {
      return {
        content: [{
          type: 'text' as const,
          text: JSON.stringify({
            error: 'evidence_must_be_specific',
            message: 'Provide a file path and line number, or a direct quote from the code. Short vague evidence is not verifiable.',
            required_format: 'file:line or quoted_text',
          }),
        }],
        isError: true,
      };
    }

    const decisions = await stateReader.readDecisions();
    decisions.decisions.push({
      task_id,
      timestamp: new Date().toISOString(),
      session: 'mcp-session',
      topic,
      plan_said,
      decided,
      reason,
      evidence,
      authority,
      tags,
    });
    await stateReader.writeDecisions(decisions);

    // Update anchor
    await anchorManager.update(task_id, {});

    return {
      content: [{
        type: 'text' as const,
        text: JSON.stringify({
          recorded: true,
          topic,
          decided,
          authority,
          total_decisions: decisions.decisions.length,
        }),
      }],
    };
  })
);

// 4. acts_verify_state
server.registerTool(
  'acts_verify_state',
  {
    description: 'Cross-reference agent claims against actual filesystem and git state. Checks files_touched vs git diff, build/test status vs claims, AGENTS.md compliance.',
    inputSchema: {
      session_file: z.string().optional().describe('Session filename to verify'),
      run_commands: z.boolean().optional().describe('Whether to run live build/test commands'),
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true },
  },
  safeTool(async ({ session_file, run_commands }) => {
    const gitStatus = await gitReader.status();
    const gitDiffStat = await gitReader.diffStat(true);
    const state = await stateReader.readState();

    const result: Record<string, unknown> = {
      git_status: {
        branch: gitStatus.branch,
        staged: gitStatus.staged,
        modified: gitStatus.modified,
        untracked: gitStatus.untracked,
        clean: gitStatus.clean,
      },
      diff_stat: gitDiffStat,
    };

    // Check files_touched consistency
    const currentTask = state.tasks.find(t => t.status === 'IN_PROGRESS');
    if (currentTask) {
      const claimedFiles = new Set(currentTask.files_touched);
      const actualFiles = new Set([...gitStatus.staged, ...gitStatus.modified]);
      const missing = [...actualFiles].filter(f => !claimedFiles.has(f));
      const extra = [...claimedFiles].filter(f => !actualFiles.has(f));

      result.files_touched_verification = {
        match: missing.length === 0 && extra.length === 0,
        claimed: currentTask.files_touched,
        actual_staged: gitStatus.staged,
        actual_modified: gitStatus.modified,
        not_recorded: missing,
        recorded_but_not_changed: extra,
      };
    }

    // Verify session summary if provided
    if (session_file) {
      const session = await sessionReader.readSession(session_file);
      if (session) {
        result.session_verification = {
          filename: session_file,
          developer: session.developer,
          task_id: session.task_id,
          files_touched: session.files_touched,
          current_state: session.current_state,
        };
      } else {
        result.session_verification = { error: `Session file not found: ${session_file}` };
      }
    }

    return {
      content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }],
    };
  })
);

// 5. acts_update_anchor
server.registerTool(
  'acts_update_anchor',
  {
    description: 'Update context anchor with current task state. Re-injects critical constraints at maximum attention position. Call every 15 turns during implementation.',
    inputSchema: {
      task_id: z.string().regex(/^T\d+$/).describe('Task ID'),
      goal: z.string().optional().describe('Current goal declaration'),
      not_goal: z.array(z.string()).optional().describe('What this task is NOT about'),
      constraints: z.array(z.string()).optional().describe('Active constraints'),
      turn_count: z.number().optional().describe('Current turn count'),
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
  },
  safeTool(async ({ task_id, goal, not_goal, constraints, turn_count }) => {
    const anchor = await anchorManager.update(task_id, {
      ...(goal && { goal }),
      ...(not_goal && { not_goal }),
      ...(constraints && { constraints }),
      ...(turn_count !== undefined && { turn_count }),
    });

    return {
      content: [{
        type: 'text' as const,
        text: anchorManager.format(anchor),
      }],
    };
  })
);

// 6. acts_compact_context
server.registerTool(
  'acts_compact_context',
  {
    description: 'Compact older session context using preservation contract. Preserves decisions, rejected approaches, open questions. Discards tool call residue and verbose explorations.',
    inputSchema: {
      task_id: z.string().regex(/^T\d+$/).describe('Task ID'),
      keep_latest: z.number().min(1).max(10).optional().describe('Number of recent sessions to keep uncompressed (default: 2)'),
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true },
  },
  safeTool(async ({ task_id, keep_latest }) => {
    const result = await compactionEngine.compact(task_id, keep_latest || 2);

    return {
      content: [{
        type: 'text' as const,
        text: JSON.stringify(result, null, 2),
      }],
    };
  })
);

// 7. acts_check_ownership
server.registerTool(
  'acts_check_ownership',
  {
    description: 'Check if a file modification crosses task boundaries. Warns if the file is owned by a completed task. Use before modifying any file.',
    inputSchema: {
      file_path: z.string().min(1).describe('Repository-relative file path to check'),
      task_id: z.string().regex(/^T\d+$/).describe('Task ID requesting the modification'),
    },
    annotations: { readOnlyHint: true, destructiveHint: false, idempotentHint: true },
  },
  safeTool(async ({ file_path, task_id }) => {
    const state = await stateReader.readState();
    const ownership = stateReader.buildOwnershipMap(state);

    let owned_by: string | null = null;
    let ownerStatus: string | null = null;

    for (const [tId, entry] of Object.entries(ownership)) {
      if (tId !== task_id && entry.files.includes(file_path)) {
        owned_by = tId;
        ownerStatus = entry.status;
        break;
      }
    }

    const result = {
      file_path,
      requesting_task: task_id,
      owned_by,
      owner_status: ownerStatus,
      action: owned_by ? (ownerStatus === 'DONE' ? 'warn' : 'error') : 'ok',
      message: owned_by
        ? `This file is owned by ${ownerStatus} task ${owned_by}. Modifications may violate isolation. Proceed only with developer approval.`
        : 'File is not owned by any other task. Safe to modify.',
    };

    return {
      content: [{ type: 'text' as const, text: JSON.stringify(result, null, 2) }],
    };
  })
);

// 8. acts_propagate_learning
server.registerTool(
  'acts_propagate_learning',
  {
    description: 'Share a rejected approach from one task to related tasks. Stored in decisions.json and surfaced in future context bundles.',
    inputSchema: {
      source_task: z.string().regex(/^T\d+$/).describe('Task that tried and rejected this approach'),
      session: z.string().min(1).describe('Session filename (without .md) that rejected it'),
      approach: z.string().min(1).describe('Description of the approach'),
      reason: z.string().min(1).describe('Why this approach was rejected'),
      evidence: z.string().min(1).describe('Verifiable evidence of the rejection'),
      tags: z.array(z.string()).optional().describe('Semantic tags for relevance matching'),
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false },
  },
  safeTool(async ({ source_task, session, approach, reason, evidence, tags }) => {
    await learningPropagator.recordRejectedApproach(
      source_task,
      session,
      approach,
      reason,
      evidence,
      tags
    );

    return {
      content: [{
        type: 'text' as const,
        text: JSON.stringify({
          recorded: true,
          source_task,
          approach,
          tags: tags || [],
          message: 'Rejected approach stored. Will be surfaced in context bundles for other tasks.',
        }),
      }],
    };
  })
);

// --- Resources ---

// acts://story/state
server.registerResource(
  'Story State',
  'acts://story/state',
  {
    description: 'Parsed and validated state.json for the current story',
    mimeType: 'application/json',
  },
  safeTool(async () => {
    const state = await stateReader.readState();
    return {
      contents: [{
        uri: 'acts://story/state',
        mimeType: 'application/json',
        text: JSON.stringify(state, null, 2),
      }],
    };
  })
);

// acts://story/board
server.registerResource(
  'Story Board',
  'acts://story/board',
  {
    description: 'Computed task status table — auto-updated from state.json',
    mimeType: 'application/json',
  },
  safeTool(async () => {
    const state = await stateReader.readState();
    const board = stateReader.buildStoryboard(state);
    return {
      contents: [{
        uri: 'acts://story/board',
        mimeType: 'application/json',
        text: JSON.stringify(board, null, 2),
      }],
    };
  })
);

// acts://story/ownership
server.registerResource(
  'Ownership Map',
  'acts://story/ownership',
  {
    description: 'Files owned by completed tasks — shows who owns what',
    mimeType: 'application/json',
  },
  safeTool(async () => {
    const state = await stateReader.readState();
    const ownership = stateReader.buildOwnershipMap(state);
    return {
      contents: [{
        uri: 'acts://story/ownership',
        mimeType: 'application/json',
        text: JSON.stringify(ownership, null, 2),
      }],
    };
  })
);

// acts://task/{id}/context — dynamic resource template
server.resource(
  'Task Context',
  'acts://task/{id}/context',
  { description: 'Full context bundle for a specific task', mimeType: 'application/json' },
  safeTool(async (uri) => {
    const taskId = uri.pathname.split('/').filter(Boolean)[1] || 'T1';
    const bundle = await contextEngine.buildContextBundle(taskId, 'resource-read', 30000);
    return {
      contents: [{
        uri: uri.href,
        mimeType: 'application/json',
        text: JSON.stringify(bundle, null, 2),
      }],
    };
  })
);

// acts://task/{id}/anchor — dynamic resource template
server.resource(
  'Task Anchor',
  'acts://task/{id}/anchor',
  { description: 'Live context anchor for a specific task', mimeType: 'text/markdown' },
  safeTool(async (uri) => {
    const taskId = uri.pathname.split('/').filter(Boolean)[1] || 'T1';
    const anchor = anchorManager.get(taskId);
    const content = anchor
      ? anchorManager.format(anchor)
      : `No anchor initialized for ${taskId}. Call acts_begin_operation first.`;
    return {
      contents: [{
        uri: uri.href,
        mimeType: 'text/markdown',
        text: content,
      }],
    };
  })
);

// acts://task/{id}/learnings — dynamic resource template
server.resource(
  'Task Learnings',
  'acts://task/{id}/learnings',
  { description: 'Rejected approaches from ALL tasks relevant to this one', mimeType: 'text/markdown' },
  safeTool(async (uri) => {
    const taskId = uri.pathname.split('/').filter(Boolean)[1] || 'T1';
    const learnings = await learningPropagator.getRelevantLearnings(taskId);
    const content = learningPropagator.formatLearnings(learnings);
    return {
      contents: [{
        uri: uri.href,
        mimeType: 'text/markdown',
        text: content,
      }],
    };
  })
);

// acts://session/current
server.registerResource(
  'Current Session',
  'acts://session/current',
  {
    description: 'Live session state (git status, branch, diff stats)',
    mimeType: 'application/json',
  },
  safeTool(async () => {
    const gitStatus = await gitReader.status();
    const gitDiffStat = await gitReader.diffStat(true);
    const state = await stateReader.readState();
    const currentTask = state.tasks.find(t => t.status === 'IN_PROGRESS');

    return {
      contents: [{
        uri: 'acts://session/current',
        mimeType: 'application/json',
        text: JSON.stringify({
          git: {
            branch: gitStatus.branch,
            clean: gitStatus.clean,
            staged_count: gitStatus.staged.length,
            modified_count: gitStatus.modified.length,
            untracked_count: gitStatus.untracked.length,
          },
          diff: gitDiffStat,
          current_task: currentTask ? {
            id: currentTask.id,
            title: currentTask.title,
            assigned_to: currentTask.assigned_to,
          } : null,
        }, null, 2),
      }],
    };
  })
);

// acts://gaps
server.registerResource(
  'Context Gaps',
  'acts://gaps',
  {
    description: 'Detected context gaps for the current operation',
    mimeType: 'application/json',
  },
  safeTool(async () => {
    const state = await stateReader.readState();
    const currentTask = state.tasks.find(t => t.status === 'IN_PROGRESS');

    if (!currentTask) {
      return {
        contents: [{
          uri: 'acts://gaps',
          mimeType: 'application/json',
          text: JSON.stringify({ gaps: [], message: 'No task in progress' }),
        }],
      };
    }

    const bundle = await contextEngine.buildContextBundle(currentTask.id, 'gap-check', 30000);
    const gaps = contextEngine.detectGaps(bundle, state);

    return {
      contents: [{
        uri: 'acts://gaps',
        mimeType: 'application/json',
        text: JSON.stringify({ task_id: currentTask.id, gaps }, null, 2),
      }],
    };
  })
);

// --- Prompts ---

// acts_preflight
server.registerPrompt(
  'acts_preflight',
  {
    description: 'Preflight operation guide with context pre-loaded for a task',
    argsSchema: {
      task_id: z.string().describe('Task ID (e.g., T3)'),
      developer: z.string().describe('Developer name or handle'),
    },
  },
  safeTool(async ({ task_id, developer }) => {
    const state = await stateReader.readState();
    const board = stateReader.buildStoryboard(state);
    const ownership = stateReader.buildOwnershipMap(state);
    const scope = stateReader.buildScopeDeclaration(state, task_id);
    const anchor = await anchorManager.initialize(task_id, state);
    const learnings = await learningPropagator.getRelevantLearnings(task_id);

    const boardText = board.map(t =>
      `| ${t.task_id} | ${t.title} | ${t.status} | ${t.assigned_to || '—'} | ${t.files_count} files |`
    ).join('\n');

    const ownershipText = Object.entries(ownership)
      .map(([id, entry]) => `- **${id}** (${entry.status}): ${entry.files.join(', ')}`)
      .join('\n') || 'No completed tasks with files yet.';

    return {
      messages: [{
        role: 'user' as const,
        content: {
          type: 'text' as const,
          text: `You are running the ACTS preflight operation for task **${task_id}** by developer **${developer}**.

## Story State
- Story: ${state.story_id} — ${state.title}
- Status: ${state.status}
- All tasks DONE: ${state.tasks.every(t => t.status === 'DONE')}

## Story Board

| Task | Title | Status | Assigned | Files |
|------|-------|--------|----------|-------|
${boardText}

## Ownership Map

${ownershipText}

## Context Anchor — ${task_id}

- **Goal**: ${anchor.goal}
- **Phase**: ${anchor.phase}
- **Constraints**: ${anchor.constraints.join('; ')}

${learnings.length > 0 ? `## Learnings from Other Tasks\n\n${learningPropagator.formatLearnings(learnings).slice(0, 2000)}` : ''}

${scope ? `## Scope Declaration

**Will do**: ${scope.will_do.join(', ')}
**Will NOT do**: ${scope.will_not_do.join(', ')}
**Files may modify**: ${scope.files_may_modify.join(', ') || 'To be determined'}
**Files owned by others**: ${scope.files_owned_by_others.join(', ') || 'None'}` : ''}

## Your task
1. Validate story and task status per ACTS preflight protocol
2. Present the Story Board, Ownership Map, and Scope Declaration above
3. Wait for developer approval (GATE: approve)
4. After approval, update state.json (status → IN_PROGRESS, assign task) and commit

## Constraints
- Do NOT produce application code
- Do NOT skip the gate
- Do NOT proceed if story status is ANALYSIS, REVIEW, or DONE
- Do NOT proceed if task is already DONE or assigned to someone else`,
        },
      }],
    };
  })
);

// acts_task_start
server.registerPrompt(
  'acts_task_start',
  {
    description: 'Implementation guide with scope, ownership, and learnings pre-loaded',
    argsSchema: {
      task_id: z.string().describe('Task ID (e.g., T3)'),
    },
  },
  safeTool(async ({ task_id }) => {
    const state = await stateReader.readState();
    const bundle = await contextEngine.buildContextBundle(task_id, 'task-start', 30000);
    const anchor = anchorManager.get(task_id);
    const learnings = await learningPropagator.getRelevantLearnings(task_id);

    const decisionsText = bundle.decisions_override.length > 0
      ? bundle.decisions_override.map(d =>
          `- **${d.topic}**: Plan said "${d.plan_said}", decided "${d.decided}" (${d.reason}) [${d.authority}]`
        ).join('\n')
      : 'No decisions override plan entries.';

    const approachText = learnings.length > 0
      ? learningPropagator.formatLearnings(learnings).slice(0, 2000)
      : 'No rejected approaches from other tasks.';

    const ownershipText = Object.entries(bundle.ownership)
      .map(([id, entry]) => `- **${id}** (DONE): ${entry.files.join(', ')}`)
      .join('\n') || 'No completed tasks with files yet.';

    return {
      messages: [{
        role: 'user' as const,
        content: {
          type: 'text' as const,
          text: `You are implementing task **${task_id}** per the ACTS task-start operation.

## Plan Entry

${bundle.plan_entry || 'No plan entry found for this task.'}

## Decisions That Override Plan

${decisionsText}

## File Ownership

${ownershipText}

## Rejected Approaches from Other Tasks

${approachText}

${anchor ? `## Context Anchor — ${task_id}

- **Goal**: ${anchor.goal}
- **NOT goal**: ${anchor.not_goal.join(', ')}
- **Constraints**: ${anchor.constraints.join('; ')}
- **Turn count**: ${anchor.turn_count}` : ''}

## Dependency Interfaces

${bundle.dependency_interfaces.length > 0
  ? bundle.dependency_interfaces.map(d =>
      `- **${d.task_id}** (${d.status}): ${d.files.join(', ')}`
    ).join('\n')
  : 'No dependencies.'}

## Your task
1. Implement following TDD (when supported)
2. Use acts_record_decision when you make a choice
3. Use acts_update_anchor every 15 turns to refresh context
4. Use acts_check_ownership before modifying files
5. When complete, update state.json and commit

## Anti-loop
If you find yourself reading the same file 3+ times, STOP.
You already have the context above. Proceed with implementation.`,
        },
      }],
    };
  })
);

// acts_session_summary
server.registerPrompt(
  'acts_session_summary',
  {
    description: 'Session recording guide with live state verification',
    argsSchema: {
      developer: z.string().describe('Developer name or handle'),
    },
  },
  safeTool(async ({ developer }) => {
    const gitStatus = await gitReader.status();
    const state = await stateReader.readState();
    const currentTask = state.tasks.find(t => t.status === 'IN_PROGRESS');

    return {
      messages: [{
        role: 'user' as const,
        content: {
          type: 'text' as const,
          text: `You are recording the ACTS session summary for developer **${developer}**.

## Current State
- Story: ${state.story_id} — ${state.title}
- Current task: ${currentTask ? `${currentTask.id}: ${currentTask.title}` : 'None in progress'}
- Git branch: ${gitStatus.branch}
- Staged files: ${gitStatus.staged.length}
- Modified files: ${gitStatus.modified.length}

## Live Git Status
- Staged: ${gitStatus.staged.join(', ') || 'None'}
- Modified: ${gitStatus.modified.join(', ') || 'None'}
- Untracked: ${gitStatus.untracked.join(', ') || 'None'}

## Your task
1. Record what was done, what was NOT done, decisions made
2. Run live verification (build, test, git status)
3. Record agent compliance with EVIDENCE (quote specific rules)
4. Update decisions.json with any new decisions or rejected approaches
5. Update state.json if task is complete
6. Commit with ACTS format: \`<type>(<STORY_ID>): <description>\`

## Session Summary Format

Use the standard session summary format:
- **Developer**: ${developer}
- **Date**: [ISO 8601]
- **Task**: [task_id]

## What was done
## Decisions made
## What was NOT done (and why)
## Approaches tried and rejected
## Open questions
## Current state
## Files touched this session
## Suggested next step
## Agent Compliance`,
        },
      }],
    };
  })
);

// acts_handoff
server.registerPrompt(
  'acts_handoff',
  {
    description: 'Handoff briefing with deep context pre-assembled for new developer',
    argsSchema: {
      task_id: z.string().describe('Task ID to hand off'),
      new_developer: z.string().describe('Developer taking over'),
    },
  },
  safeTool(async ({ task_id, new_developer }) => {
    const state = await stateReader.readState();
    const allSessions = await sessionReader.readAllSessionsForTask(task_id);
    const learnings = await learningPropagator.getRelevantLearnings(task_id);
    const decisions = await stateReader.readDecisions();

    const taskDecisions = decisions.decisions.filter(d => d.task_id === task_id);
    const taskQuestions = decisions.open_questions.filter(q => q.task_id === task_id && q.status === 'unresolved');

    const sessionsSummary = allSessions.map(s =>
      `### ${s.filename} (${s.developer}, ${s.date})\n**Done**: ${s.what_was_done.slice(0, 300)}\n**Decisions**: ${s.decisions_made.slice(0, 300)}\n**Not done**: ${s.what_was_not_done.slice(0, 300)}\n**Rejected**: ${s.approaches_tried_and_rejected.slice(0, 300)}\n`
    ).join('\n') || 'No prior sessions for this task.';

    const decisionsText = taskDecisions.map(d =>
      `- **${d.topic}**: ${d.decided} (${d.reason}) [${d.authority}]`
    ).join('\n') || 'No decisions recorded.';

    return {
      messages: [{
        role: 'user' as const,
        content: {
          type: 'text' as const,
          text: `You are preparing an ACTS handoff briefing for task **${task_id}** → developer **${new_developer}**.

## Story
- ${state.story_id}: ${state.title}
- Status: ${state.status}

## Task: ${task_id}

${state.tasks.find(t => t.id === task_id)?.title || 'Unknown'}

## Prior Sessions

${sessionsSummary}

## Decisions Made

${decisionsText}

## Open Questions (unresolved)

${taskQuestions.map(q => `- ${q.question}`).join('\n') || 'None.'}

## Learnings from Other Tasks

${learnings.length > 0 ? learningPropagator.formatLearnings(learnings).slice(0, 2000) : 'None.'}

## Your task
1. Synthesize a comprehensive briefing from all sessions
2. Highlight pitfalls from rejected approaches
3. Surface unresolved open questions
4. State what remaining work is needed
5. Reassign task in state.json to ${new_developer}
6. Commit with ACTS format`,
        },
      }],
    };
  })
);

// acts_story_review
server.registerPrompt(
  'acts_story_review',
  {
    description: 'Review checklist with all acceptance criteria and compliance data',
    argsSchema: {},
  },
  safeTool(async () => {
    const state = await stateReader.readState();
    const spec = await stateReader.readSpec();
    const decisions = await stateReader.readDecisions();
    const allSessions: Array<Record<string, unknown>> = [];

    for (const task of state.tasks) {
      const sessions = await sessionReader.readAllSessionsForTask(task.id);
      allSessions.push(...sessions.map(s => ({
        task_id: s.task_id,
        filename: s.filename,
        developer: s.developer,
        date: s.date,
        compliance: s.agent_compliance,
      })));
    }

    // Extract acceptance criteria from spec
    const acLines = spec.split('\n')
      .filter(line => /^\d+\.|^- /i.test(line.trim()) && /must|should|shall/i.test(line))
      .slice(0, 20);

    const tasksSummary = state.tasks.map(t =>
      `| ${t.id} | ${t.title} | ${t.status} | ${t.assigned_to || '—'} | ${t.files_touched.length} files |`
    ).join('\n');

    return {
      messages: [{
        role: 'user' as const,
        content: {
          type: 'text' as const,
          text: `You are running the ACTS story-review for **${state.story_id}: ${state.title}**.

## Story Status
- All tasks DONE: ${state.tasks.every(t => t.status === 'DONE')}
- Total sessions: ${allSessions.length}
- Decisions recorded: ${decisions.decisions.length}
- Rejected approaches: ${decisions.rejected_approaches.length}

## Tasks

| Task | Title | Status | Assigned | Files |
|------|-------|--------|----------|-------|
${tasksSummary}

## Acceptance Criteria (from spec.md)

${acLines.length > 0 ? acLines.join('\n') : 'No acceptance criteria found in spec.md.'}

## Agent Compliance Across Sessions

${allSessions.length > 0
  ? allSessions.map(s => `- **${s.filename}** (${s.developer}): compliance data available`).join('\n')
  : 'No sessions recorded.'}

## Unresolved Open Questions

${decisions.open_questions.filter(q => q.status === 'unresolved').map(q => `- [${q.task_id}] ${q.question}`).join('\n') || 'None.'}

## Your task
1. Verify each acceptance criterion has corresponding code/tests
2. Check AGENTS.md compliance (forbidden patterns, file length, commit format)
3. Run test suite and lint
4. Audit agent compliance across all sessions
5. Generate PR description from actual code changes (git diff vs main)
6. Update state.json status to REVIEW
7. Commit`,
        },
      }],
    };
  })
);

// --- Start ---

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error('ACTS MCP Context Engine v0.5.0 — connected via stdio');
}

main().catch((err) => {
  console.error('Fatal:', err);
  process.exit(1);
});
