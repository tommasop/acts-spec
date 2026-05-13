import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { execFileSync, execSync } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ─────────────────────────────────────────────
// ACTS OpenCode Plugin v2.0.0
// ─────────────────────────────────────────────

const PLUGIN_VERSION = '2.0.0';
const ACTS_VERSION = '1.0.0';

export const ActsPlugin = async ({ client, directory }) => {
  // ─── Binary Discovery ───────────────────────
  const findActsBinary = () => {
    const localPath = path.join(directory, '.acts', 'bin', 'acts');
    if (fs.existsSync(localPath)) {
      return localPath;
    }
    try {
      const which = execSync('which acts', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
      return which.trim();
    } catch {
      return null;
    }
  };

  const actsBinary = findActsBinary();

  // ─── Safe Command Runner ────────────────────
  const runActs = (args, options = {}) => {
    if (!actsBinary) {
      throw new Error('ACTS binary not found. Run `acts init <story-id>` to initialize.');
    }
    // Validate args are strings to prevent injection
    const safeArgs = args.map(a => String(a));
    return execFileSync(actsBinary, safeArgs, {
      encoding: 'utf8',
      cwd: directory,
      timeout: options.timeout || 30000,
      stdio: ['pipe', 'pipe', 'pipe'],
      ...options
    });
  };

  // ─── Project Validation ─────────────────────
  const isActsProject = () => {
    return fs.existsSync(path.join(directory, '.acts', 'acts.db')) &&
           fs.existsSync(path.join(directory, '.acts', 'acts.json'));
  };

  const actsProject = isActsProject();

  // ─── Plugin State Management ────────────────
  const pluginStatePath = path.join(directory, '.acts', 'plugin-state.json');
  const overrideRequestsPath = path.join(directory, '.acts', 'override-requests.json');
  const overrideApprovalsPath = path.join(directory, '.acts', 'override-approvals.json');

  const loadPluginState = () => {
    try {
      if (fs.existsSync(pluginStatePath)) {
        return JSON.parse(fs.readFileSync(pluginStatePath, 'utf8'));
      }
    } catch { /* ignore */ }
    return { mode: 'on', version: PLUGIN_VERSION };
  };

  const savePluginState = (state) => {
    try {
      fs.writeFileSync(pluginStatePath, JSON.stringify(state, null, 2));
    } catch (e) {
      console.warn('Failed to save plugin state:', e.message);
    }
  };

  const pluginState = loadPluginState();

  // ─── Override Management ────────────────────
  const loadOverrides = () => {
    try {
      if (fs.existsSync(overrideRequestsPath)) {
        return JSON.parse(fs.readFileSync(overrideRequestsPath, 'utf8'));
      }
    } catch { /* ignore */ }
    return { requests: [] };
  };

  const loadApprovals = () => {
    try {
      if (fs.existsSync(overrideApprovalsPath)) {
        return JSON.parse(fs.readFileSync(overrideApprovalsPath, 'utf8'));
      }
    } catch { /* ignore */ }
    return { approvals: [] };
  };

  const saveOverrides = (data) => {
    try {
      fs.writeFileSync(overrideRequestsPath, JSON.stringify(data, null, 2));
    } catch (e) {
      console.warn('Failed to save override requests:', e.message);
    }
  };

  const saveApprovals = (data) => {
    try {
      fs.writeFileSync(overrideApprovalsPath, JSON.stringify(data, null, 2));
    } catch (e) {
      console.warn('Failed to save override approvals:', e.message);
    }
  };

  // ─── Dynamic Bootstrap from AGENTS.md ───────
  const getBootstrapContent = () => {
    const agentsPath = path.join(directory, 'AGENTS.md');
    let baseRules = '';

    if (fs.existsSync(agentsPath)) {
      try {
        const agentsContent = fs.readFileSync(agentsPath, 'utf8');
        // Extract ACTS Integration section if present
        const actsMatch = agentsContent.match(/## ACTS Integration[\s\S]*?(?=\n## |\n---|$)/);
        if (actsMatch) {
          baseRules = actsMatch[0].trim();
        }
      } catch { /* fall through to default */ }
    }

    if (!baseRules) {
      baseRules = `This project uses ACTS (Agent Collaborative Tracking Standard) v${ACTS_VERSION} for multi-developer coordination.

### Rules
- Agent MUST read state before writing code: acts state read
- Agent MUST NOT modify files owned by completed tasks: acts scope check --task <id> --file <path>
- Agent MUST record session summary before ending: acts session validate <file.md>
- Agent MUST stay within assigned task boundary
- Agent MUST get developer approval before committing
- Agent MUST run code review before task completion`;
    }

    return `<EXTREMELY_IMPORTANT>
${baseRules}

ACTS Commands:
- acts init <story-id>              Initialize new ACTS story
- acts state read                   Read current story state
- acts state write --story <id>     Update story state (JSON from stdin)
- acts task get <task-id>           Get task details
- acts task update <id> --status <s> Update task status (enforces gates)
- acts gate add --task <id> --type <t> --status <s>  Add gate checkpoint
- acts ownership map                Show file ownership
- acts scope check --task <id> --file <path> Check if file is safe to modify
- acts validate                     Validate entire ACTS project
- acts migrate                      Force schema migration

Gate Types:
- approve          Preflight approval (required before IN_PROGRESS)
- task-review      Code review approval (required before DONE)
- commit-review    Batch commit approval (strict mode)
- architecture-discuss Architecture decision approval (strict mode)

Status Values:
- TODO, IN_PROGRESS, BLOCKED, DONE (tasks)
- ANALYSIS, APPROVED, IN_PROGRESS, REVIEW, DONE (stories)
- pending, approved, changes_requested (gates)
</EXTREMELY_IMPORTANT>`;
  };

  // ─── Cached State ───────────────────────────
  let cachedState = null;
  let cachedOwnership = null;
  let cachedStateTime = 0;
  const STATE_CACHE_TTL = 60000; // 60 seconds

  const refreshState = () => {
    if (!actsProject || !actsBinary) return null;
    try {
      const now = Date.now();
      if (cachedState && (now - cachedStateTime) < STATE_CACHE_TTL) {
        return cachedState;
      }
      const raw = runActs(['state', 'read']);
      cachedState = JSON.parse(raw);
      cachedStateTime = now;
      return cachedState;
    } catch (e) {
      console.warn('Failed to read ACTS state:', e.message);
      return null;
    }
  };

  const refreshOwnership = () => {
    if (!actsProject || !actsBinary) return null;
    try {
      const raw = runActs(['ownership', 'map']);
      cachedOwnership = JSON.parse(raw);
      return cachedOwnership;
    } catch (e) {
      console.warn('Failed to read ownership map:', e.message);
      return null;
    }
  };

  // Initial load
  if (pluginState.mode !== 'off') {
    refreshState();
    refreshOwnership();
  }

  // ─── Context Builders ───────────────────────
  const buildSystemContext = () => {
    const state = refreshState();
    if (!state) return [];

    const lines = [];
    lines.push(`# ACTS Project Context`);
    lines.push(`- Story: ${state.story_id} (${state.title})`);
    lines.push(`- Story Status: ${state.status}`);
    lines.push(`- ACTS Mode: ${pluginState.mode}`);

    const inProgressTasks = (state.tasks || []).filter(t => t.status === 'IN_PROGRESS');
    if (inProgressTasks.length > 0) {
      lines.push(`## Active Tasks`);
      for (const task of inProgressTasks) {
        lines.push(`- ${task.id}: ${task.title} [${task.status}]`);
        if (task.description) lines.push(`  Description: ${task.description}`);
      }
    }

    // File ownership warnings
    const ownership = cachedOwnership || refreshOwnership();
    if (ownership && Object.keys(ownership).length > 0) {
      const doneOwned = Object.entries(ownership).filter(([, info]) => info.owner_status === 'DONE');
      if (doneOwned.length > 0) {
        lines.push(`## LOCKED Files (owned by DONE tasks — DO NOT MODIFY without override approval)`);
        for (const [file, info] of doneOwned) {
          lines.push(`- ${file} → owned by ${info.task_id}`);
        }
      }
    }

    // Approved overrides
    const approvals = loadApprovals();
    if (approvals.approvals && approvals.approvals.length > 0) {
      const active = approvals.approvals.filter(a => !a.expiresAt || new Date(a.expiresAt) > new Date());
      if (active.length > 0) {
        lines.push(`## Approved Overrides`);
        for (const ov of active) {
          lines.push(`- ${ov.file} (approved for ${ov.task}, reason: ${ov.reason})`);
        }
      }
    }

    if (pluginState.mode === 'strict') {
      lines.push(`## STRICT MODE ACTIVE`);
      lines.push(`- You MUST NOT write any code without a preflight gate approval.`);
      lines.push(`- You MUST NOT mark tasks DONE without task-review gate approval.`);
      lines.push(`- You MUST check acts scope check before modifying ANY file.`);
    }

    return [lines.join('\n')];
  };

  // ─── Hooks ──────────────────────────────────
  return {
    // Inject system-level ACTS context
    'experimental.chat.system.transform': async (_input, output) => {
      if (pluginState.mode === 'off' || !actsProject) return;
      const context = buildSystemContext();
      if (context.length > 0) {
        output.system = [...output.system, ...context];
      }
    },

    // Inject ACTS bootstrap into first user message
    'experimental.chat.messages.transform': async (_input, output) => {
      if (pluginState.mode === 'off' || !actsProject) return;
      if (!output.messages.length) return;

      const firstUser = output.messages.find(m => m.info.role === 'user');
      if (!firstUser || !firstUser.parts.length) return;

      // Only inject once per conversation
      const alreadyInjected = firstUser.parts.some(
        p => p.type === 'text' && p.text.includes('ACTS (Agent Collaborative Tracking Standard)')
      );
      if (alreadyInjected) return;

      const bootstrap = getBootstrapContent();
      firstUser.parts.unshift({ type: 'text', text: bootstrap });
    },

    // Register tools
    tools: async () => {
      if (!actsBinary) {
        return {
          acts_install: {
            description: 'Install ACTS in this project (no binary found)',
            inputSchema: {
              type: 'object',
              properties: {
                story_id: { type: 'string', description: 'Story ID to initialize after install' }
              }
            },
            handler: async ({ story_id }) => {
              return {
                content: [{
                  type: 'text',
                  text: 'ACTS binary not found. Install with:\n' +
                        '  curl -fsSL https://raw.githubusercontent.com/tommasop/acts-spec/main/install.sh | bash\n' +
                        'Then initialize: acts init ' + (story_id || '<story-id>')
                }]
              };
            }
          }
        };
      }

      return {
        // ─── Main ACTS Tool ─────────────────────
        acts: {
          description: 'Execute ACTS (Agent Collaborative Tracking Standard) commands. ' +
            'Common: state read, task get <id>, task update <id> --status <s>, ' +
            'gate add --task <id> --type <t> --status <s>, scope check --task <id> --file <path>, ' +
            'ownership map, validate',
          inputSchema: {
            type: 'object',
            properties: {
              command: {
                type: 'string',
                description: 'ACTS command to execute (e.g., "state read", "task update T1 --status DONE")'
              }
            },
            required: ['command']
          },
          handler: async ({ command }) => {
            try {
              // Parse command safely
              const args = command.trim().split(/\s+/);
              const result = runActs(args);
              return {
                content: [{ type: 'text', text: result }]
              };
            } catch (error) {
              return {
                content: [{ type: 'text', text: `ACTS error: ${error.stderr || error.message}` }],
                isError: true
              };
            }
          }
        },

        // ─── ACTS Mode Tool ─────────────────────
        acts_mode: {
          description: 'Control ACTS plugin mode. Modes: off (disable ACTS context), ' +
            'on (full context injection), strict (enforcement language). ' +
            'Use "enter" to activate, "exit" to deactivate, "status" to check current mode.',
          inputSchema: {
            type: 'object',
            properties: {
              action: {
                type: 'string',
                enum: ['enter', 'exit', 'status'],
                description: 'Action to perform'
              },
              level: {
                type: 'string',
                enum: ['on', 'strict'],
                description: 'Mode level when entering (default: on)'
              }
            },
            required: ['action']
          },
          handler: async ({ action, level = 'on' }) => {
            if (action === 'status') {
              return {
                content: [{
                  type: 'text',
                  text: `ACTS Plugin Mode: ${pluginState.mode}\n` +
                        `Project: ${actsProject ? 'ACTS initialized' : 'Not an ACTS project'}\n` +
                        `Binary: ${actsBinary || 'not found'}\n` +
                        `Plugin Version: ${PLUGIN_VERSION}`
                }]
              };
            }

            if (action === 'enter') {
              if (!actsProject) {
                return {
                  content: [{ type: 'text', text: 'Error: Not an ACTS project. Run `acts init <story-id>` first.' }],
                  isError: true
                };
              }
              const newMode = level === 'strict' ? 'strict' : 'on';
              pluginState.mode = newMode;
              pluginState.modeSetAt = new Date().toISOString();
              savePluginState(pluginState);
              refreshState();
              refreshOwnership();
              return {
                content: [{
                  type: 'text',
                  text: `ACTS mode entered: ${newMode}\n\n` +
                        (newMode === 'strict'
                          ? 'Strict mode active. You MUST follow all gate protocols and scope checks.'
                          : 'ACTS context will now be injected into conversations.')
                }]
              };
            }

            if (action === 'exit') {
              pluginState.mode = 'off';
              pluginState.modeSetAt = new Date().toISOString();
              savePluginState(pluginState);
              return {
                content: [{
                  type: 'text',
                  text: 'ACTS mode exited. Context injection disabled. Run `acts_mode enter` to re-enable.'
                }]
              };
            }
          }
        },

        // ─── Override Tool ──────────────────────
        acts_override: {
          description: 'Request or check file override approvals for files locked by DONE tasks. ' +
            'HUMAN DEVELOPER APPROVAL IS REQUIRED for all overrides. ' +
            'Actions: request (create request), check (check approval status), list (show all).',
          inputSchema: {
            type: 'object',
            properties: {
              action: {
                type: 'string',
                enum: ['request', 'check', 'list', 'approve'],
                description: 'Override action'
              },
              file: {
                type: 'string',
                description: 'File path to request override for (required for request)'
              },
              task: {
                type: 'string',
                description: 'Current task ID requesting override (required for request)'
              },
              reason: {
                type: 'string',
                description: 'Reason for override (required for request)'
              },
              override_id: {
                type: 'string',
                description: 'Override ID to check or approve'
              }
            },
            required: ['action']
          },
          handler: async ({ action, file, task, reason, override_id }) => {
            const requests = loadOverrides();
            const approvals = loadApprovals();

            if (action === 'request') {
              if (!file || !task || !reason) {
                return {
                  content: [{ type: 'text', text: 'Error: file, task, and reason are required for request.' }],
                  isError: true
                };
              }

              // Check scope first
              try {
                const scopeResult = runActs(['scope', 'check', '--task', task, '--file', file]);
                const scope = JSON.parse(scopeResult);
                if (scope.action === 'ok' && !scope.owned_by) {
                  return {
                    content: [{
                      type: 'text',
                      text: `File ${file} is not locked by any task. No override needed.`
                    }]
                  };
                }
              } catch { /* proceed anyway */ }

              const id = 'ovr-' + Date.now().toString(36);
              const request = {
                id,
                file,
                task,
                reason,
                requestedAt: new Date().toISOString(),
                status: 'pending'
              };
              requests.requests = requests.requests || [];
              requests.requests.push(request);
              saveOverrides(requests);

              return {
                content: [{
                  type: 'text',
                  text: `Override requested: ${id}\n` +
                        `File: ${file}\n` +
                        `Task: ${task}\n` +
                        `Reason: ${reason}\n\n` +
                        `⚠️ HUMAN APPROVAL REQUIRED ⚠️\n\n` +
                        `The developer must approve this override before you can modify this file.\n` +
                        `To approve, the developer should run:\n` +
                        `  acts_override approve --override_id ${id}\n` +
                        `Or edit .acts/override-approvals.json manually.\n\n` +
                        `You can check status with:\n` +
                        `  acts_override check --override_id ${id}`
                }]
              };
            }

            if (action === 'check') {
              if (!override_id) {
                return {
                  content: [{ type: 'text', text: 'Error: override_id is required for check.' }],
                  isError: true
                };
              }
              const approved = (approvals.approvals || []).find(a => a.id === override_id);
              if (approved) {
                return {
                  content: [{
                    type: 'text',
                    text: `Override ${override_id}: APPROVED ✅\n` +
                          `File: ${approved.file}\n` +
                          `Approved at: ${approved.approvedAt}\n` +
                          `Approved by: ${approved.approvedBy || 'unknown'}\n` +
                          `Reason: ${approved.reason}\n` +
                          (approved.expiresAt ? `Expires: ${approved.expiresAt}\n` : '') +
                          `\nYou may now modify this file.`
                  }]
                };
              }
              const pending = (requests.requests || []).find(r => r.id === override_id);
              if (pending) {
                return {
                  content: [{
                    type: 'text',
                    text: `Override ${override_id}: PENDING ⏳\n` +
                          `File: ${pending.file}\n` +
                          `Requested at: ${pending.requestedAt}\n` +
                          `Reason: ${pending.reason}\n\n` +
                          `Waiting for human developer approval.`
                  }]
                };
              }
              return {
                content: [{ type: 'text', text: `Override ${override_id}: NOT FOUND` }]
              };
            }

            if (action === 'list') {
              const pending = (requests.requests || []).filter(r => r.status === 'pending');
              const approved = (approvals.approvals || []).filter(a => !a.expiresAt || new Date(a.expiresAt) > new Date());
              let text = '## Override Requests\n\n';
              if (pending.length === 0 && approved.length === 0) {
                text += 'No override requests or approvals.\n';
              } else {
                if (pending.length > 0) {
                  text += '### Pending\n';
                  for (const r of pending) {
                    text += `- ${r.id}: ${r.file} (task: ${r.task}, reason: ${r.reason})\n`;
                  }
                  text += '\n';
                }
                if (approved.length > 0) {
                  text += '### Approved\n';
                  for (const a of approved) {
                    text += `- ${a.id}: ${a.file} (task: ${a.task}, reason: ${a.reason})\n`;
                  }
                }
              }
              return { content: [{ type: 'text', text }] };
            }

            if (action === 'approve') {
              // This action is intended for HUMAN DEVELOPERS, not the agent.
              // The agent should NOT call this. We allow it but warn strongly.
              if (!override_id) {
                return {
                  content: [{ type: 'text', text: 'Error: override_id is required for approve.' }],
                  isError: true
                };
              }
              const request = (requests.requests || []).find(r => r.id === override_id);
              if (!request) {
                return {
                  content: [{ type: 'text', text: `Error: Override request ${override_id} not found.` }],
                  isError: true
                };
              }

              const approval = {
                id: override_id,
                file: request.file,
                task: request.task,
                reason: request.reason,
                requestedAt: request.requestedAt,
                approvedAt: new Date().toISOString(),
                approvedBy: 'developer-via-plugin',
                expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() // 24h expiry
              };

              approvals.approvals = approvals.approvals || [];
              approvals.approvals.push(approval);
              saveApprovals(approvals);

              // Update request status
              request.status = 'approved';
              saveOverrides(requests);

              return {
                content: [{
                  type: 'text',
                  text: `Override ${override_id}: APPROVED ✅\n` +
                        `File: ${approval.file}\n` +
                        `Task: ${approval.task}\n` +
                        `Expires: ${approval.expiresAt}\n\n` +
                        `⚠️ WARNING: This action should only be performed by a human developer. ` +
                        `If you are an AI agent, you MUST NOT have called this. ` +
                        `Approval has been logged for audit.`
                }]
              };
            }
          }
        }
      };
    },

    // ─── Config Hook ──────────────────────────
    config: async (config) => {
      if (!actsBinary) {
        console.warn('[ACTS] Binary not found. Run `acts init <story-id>` to initialize.');
        return;
      }
      if (!actsProject) {
        console.warn('[ACTS] Binary found but no ACTS project detected (.acts/acts.db missing).');
        return;
      }
      console.log(`[ACTS] Plugin v${PLUGIN_VERSION} loaded. Mode: ${pluginState.mode}`);
      if (pluginState.mode !== 'off') {
        try {
          const state = refreshState();
          if (state) {
            console.log(`[ACTS] Story: ${state.story_id} (${state.status})`);
            const activeTasks = (state.tasks || []).filter(t => t.status === 'IN_PROGRESS');
            if (activeTasks.length > 0) {
              console.log(`[ACTS] Active tasks: ${activeTasks.map(t => t.id).join(', ')}`);
            }
          }
        } catch (e) {
          console.warn('[ACTS] Failed to auto-read state:', e.message);
        }
      }
    }
  };
};
