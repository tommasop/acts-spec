import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { execFileSync, execSync } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ─────────────────────────────────────────────
// ACTS v2 OpenCode Plugin (Git-native)
// ─────────────────────────────────────────────

const PLUGIN_VERSION = '2.0.0';

export const ActsPlugin = async ({ directory }) => {
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
      throw new Error('ACTS v2 binary not found. Install it or run `acts stack create <id>` to start.');
    }
    const safeArgs = args.map(a => String(a));
    return execFileSync(actsBinary, safeArgs, {
      encoding: 'utf8',
      cwd: directory,
      timeout: options.timeout || 120000,
      stdio: ['pipe', 'pipe', 'pipe'],
      ...options
    });
  };

  // ─── Project Detection (git-native) ─────────
  const isActsProject = () => {
    return fs.existsSync(path.join(directory, '.acts', 'stack.json'));
  };

  const actsProject = isActsProject();

  // ─── Plugin State ───────────────────────────
  const pluginStatePath = path.join(directory, '.acts', 'plugin-state.json');
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
      console.warn('[ACTS] Failed to save plugin state:', e.message);
    }
  };
  const pluginState = loadPluginState();

  // ─── Cached stack status ────────────────────
  let cachedStatus = null;
  let cachedStatusTime = 0;
  const STATUS_CACHE_TTL = 60000;

  const refreshStackStatus = () => {
    if (!actsProject || !actsBinary) return null;
    try {
      const now = Date.now();
      if (cachedStatus && (now - cachedStatusTime) < STATUS_CACHE_TTL) {
        return cachedStatus;
      }
      const raw = runActs(['stack', 'status', '--json']);
      cachedStatus = JSON.parse(raw);
      cachedStatusTime = now;
      return cachedStatus;
    } catch {
      return null;
    }
  };

  if (pluginState.mode !== 'off') {
    refreshStackStatus();
  }

  // ─── Active change resolution ───────────────
  const resolveActiveChange = () => {
    const status = refreshStackStatus();
    if (!status || !Array.isArray(status.changes)) return null;
    // The active change is the change whose branch matches HEAD (agent resolves via acts context).
    // We expose `acts context` with no args which auto-resolves to the current branch's change.
    return null;
  };

  // ─── Context Builders ───────────────────────
  const getBootstrapContent = () => {
    return `<EXTREMELY_IMPORTANT>
This project uses ACTS v2 (Agent Collaborative Tracking Standard) — a git-native coordination protocol.

### Rules
- Agent MUST read state before writing code: \`acts stack status\`
- Agent MUST load durable context before starting work on a change: \`acts context <change>\`
- Agent MUST NOT submit a change for review until \`acts verify <change>\` passes.
- Agent MUST record a session note (\`acts note <change> -m "..."\`) and checkpoint (\`acts checkpoint <change> -s "..."\`) before ending a session.
- Agent MUST stay within the change's scope; use \`acts scope <change> <file>\` to check ownership.
- Agent MUST get developer approval on the PR before \`acts approve\` / \`acts stack land\`.
- Agent MUST run \`acts validate\` before finishing.

ACTS v2 Commands:
- acts stack create <id> [-t <title>]      Start a new stack (base branch + manifest)
- acts stack status [--json]               Show stack tree + change statuses
- acts stack land                          Merge APPROVED changes bottom-up
- acts change add <id> -t <title> [--accept <criteria>]  Add a change on top of the stack
- acts change status [<id>]                Show change details
- acts verify [<id>] [--all]               Run quality gates; record evidence (GATE for review)
- acts review <id>                         Submit stacked PR (requires verify to pass)
- acts approve <id>                        Mark approved after human PR review
- acts rework <id>                         Reopen for rework (clears approval)
- acts context [<id>]                      Emit scoped context pack (durable task state)
- acts note <id> -m <text>                 Append a session note
- acts checkpoint <id> -s <summary>        Record a status checkpoint
- acts redirect <id> --accept <criteria>   Update scope mid-flight without context loss
- acts scope <id> <file>                   Check file ownership (derived from diffs)
- acts validate                            Validate manifest + branch consistency

Status Values: TODO, IN_PROGRESS, VERIFIED, IN_REVIEW, APPROVED, MERGED

Workflow: plan (spec-kit/superpowers) -> stack create -> change add -> context -> implement ->
verify -> review (PR) -> approve -> stack land -> note + checkpoint + validate.
</EXTREMELY_IMPORTANT>`;
  };

  const buildSystemContext = () => {
    const status = refreshStackStatus();
    if (!status) return [];

    const lines = [];
    lines.push(`# ACTS v2 Stack Context`);
    lines.push(`- Stack: ${status.id} — ${status.title}`);
    lines.push(`- Base branch: ${status.base_branch}`);
    lines.push(`- ACTS Mode: ${pluginState.mode}`);

    if (Array.isArray(status.changes) && status.changes.length > 0) {
      lines.push(`## Changes`);
      for (const c of status.changes) {
        const st = c.status || 'TODO';
        lines.push(`- ${c.id}: ${c.title} [${st}] branch=${c.branch}`);
      }
    }

    return [lines.join('\n')];
  };

  // ─── Hooks ──────────────────────────────────
  return {
    'experimental.chat.system.transform': async (_input, output) => {
      if (pluginState.mode === 'off' || !actsProject) return;
      const context = buildSystemContext();
      if (context.length > 0) {
        output.system = [...output.system, ...context];
      }
    },

    'experimental.chat.messages.transform': async (_input, output) => {
      if (pluginState.mode === 'off' || !actsProject) return;
      if (!output.messages.length) return;

      const firstUser = output.messages.find(m => m.info.role === 'user');
      if (!firstUser || !firstUser.parts.length) return;

      const alreadyInjected = firstUser.parts.some(
        p => p.type === 'text' && p.text.includes('ACTS v2 (Agent Collaborative Tracking Standard)')
      );
      if (alreadyInjected) return;

      const bootstrap = getBootstrapContent();
      firstUser.parts.unshift({ type: 'text', text: bootstrap });
    },

    tools: async () => {
      if (!actsBinary) {
        return {
          acts_install: {
            description: 'Install ACTS v2 in this project (binary not found)',
            inputSchema: {
              type: 'object',
              properties: {
                stack_id: { type: 'string', description: 'Stack ID to create after install' }
              }
            },
            handler: async ({ stack_id }) => {
              return {
                content: [{
                  type: 'text',
                  text: 'ACTS v2 binary not found. Build/install with:\n' +
                        '  cd acts-core && zig build release\n' +
                        '  sudo cp zig-out/bin/acts /usr/local/bin/acts\n' +
                        'Then start a stack: acts stack create ' + (stack_id || '<id>') + ' -t "<title>"'
                }]
              };
            }
          }
        };
      }

      return {
        // ─── Main ACTS Tool ─────────────────────
        acts: {
          description: 'Execute ACTS v2 (git-native coordination protocol) commands. ' +
            'Common: stack status, context <change>, change add <id> -t <title>, ' +
            'verify <change>, review <change>, approve <change>, note <change> -m <text>, ' +
            'checkpoint <change> -s <summary>, redirect <change> --accept <criteria>, ' +
            'scope <change> <file>, validate',
          inputSchema: {
            type: 'object',
            properties: {
              command: {
                type: 'string',
                description: 'ACTS v2 command to execute (e.g., "context c1", "verify c1", "stack status")'
              }
            },
            required: ['command']
          },
          handler: async ({ command }) => {
            try {
              const args = command.trim().split(/\s+/);
              const result = runActs(args);
              cachedStatus = null; // invalidate cache after mutations
              return { content: [{ type: 'text', text: result }] };
            } catch (error) {
              return {
                content: [{ type: 'text', text: `ACTS error: ${error.stderr || error.message}` }],
                isError: true
              };
            }
          }
        },

        // ─── Context Pack Tool ──────────────────
        acts_context: {
          description: 'Load the ACTS v2 scoped context pack for a change (or the current branch\'s change). ' +
            'ALWAYS call this before writing code on a change. Surfaces acceptance criteria, parent chain, ' +
            'verification status, checkpoint, session notes, and changed files.',
          inputSchema: {
            type: 'object',
            properties: {
              change_id: {
                type: 'string',
                description: 'Change ID (e.g., c1). Omit to auto-resolve from the current git branch.'
              }
            }
          },
          handler: async ({ change_id }) => {
            try {
              const args = change_id ? ['context', change_id] : ['context'];
              const result = runActs(args);
              return { content: [{ type: 'text', text: result }] };
            } catch (error) {
              return {
                content: [{ type: 'text', text: `ACTS error: ${error.stderr || error.message}\n\nRun \`acts stack status\` to see active changes.` }],
                isError: true
              };
            }
          }
        },

        // ─── Zeplin Contract Tool ───────────────
        acts_zeplin: {
          description: 'Extract an API contract from a Zeplin flow or scenario link (via acts-zeplin-contract.mjs) ' +
            'for analysis and planning. Use when a design link is given. Detects flow vs scenario URLs.',
          inputSchema: {
            type: 'object',
            properties: {
              url: { type: 'string', description: 'Zeplin link (flow board, scenario, or zpl.io shortlink)' },
              notes: { type: 'boolean', description: 'Include screen notes/annotations (slower)' }
            },
            required: ['url']
          },
          handler: async ({ url, notes = false }) => {
            const script = path.join(__dirname, '..', 'acts-zeplin-contract.mjs');
            if (!fs.existsSync(script)) {
              return {
                content: [{ type: 'text', text: 'acts-zeplin-contract.mjs not found in project root.' }],
                isError: true
              };
            }
            const kind = /\/flow\//i.test(url) ? 'flow' : 'scenario';
            const args = [script, '--' + kind, url, ...(notes ? ['--notes'] : [])];
            try {
              const result = execFileSync('node', args, {
                encoding: 'utf8',
                cwd: directory,
                timeout: 120000,
                stdio: ['pipe', 'pipe', 'pipe']
              });
              return { content: [{ type: 'text', text: result }] };
            } catch (error) {
              return {
                content: [{ type: 'text', text: `acts_zeplin error: ${error.stderr || error.message}\n\nSet ZEPLIN_ACCESS_TOKEN or configure the zeplin MCP server in opencode.json.` }],
                isError: true
              };
            }
          }
        },

        // ─── Mode Tool ──────────────────────────
        acts_mode: {
          description: 'Control ACTS plugin mode. Modes: off (disable ACTS context), ' +
            'on (full context injection), strict (enforcement language). ' +
            'Use "enter" to activate, "exit" to deactivate, "status" to check current mode.',
          inputSchema: {
            type: 'object',
            properties: {
              action: { type: 'string', enum: ['enter', 'exit', 'status'], description: 'Action to perform' },
              level: { type: 'string', enum: ['on', 'strict'], description: 'Mode level when entering (default: on)' }
            },
            required: ['action']
          },
          handler: async ({ action, level = 'on' }) => {
            if (action === 'status') {
              return {
                content: [{
                  type: 'text',
                  text: `ACTS v2 Plugin Mode: ${pluginState.mode}\n` +
                        `Project: ${actsProject ? 'ACTS v2 initialized' : 'Not an ACTS v2 project'}\n` +
                        `Binary: ${actsBinary || 'not found'}\n` +
                        `Plugin Version: ${PLUGIN_VERSION}`
                }]
              };
            }
            if (action === 'enter') {
              if (!actsProject) {
                return {
                  content: [{ type: 'text', text: 'Error: Not an ACTS v2 project. Run `acts stack create <id>` first.' }],
                  isError: true
                };
              }
              const newMode = level === 'strict' ? 'strict' : 'on';
              pluginState.mode = newMode;
              pluginState.modeSetAt = new Date().toISOString();
              savePluginState(pluginState);
              refreshStackStatus();
              return {
                content: [{
                  type: 'text',
                  text: `ACTS mode entered: ${newMode}\n\n` +
                        (newMode === 'strict'
                          ? 'Strict mode active. You MUST follow all verification gates and scope checks.'
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
        }
      };
    },

    config: async () => {
      if (!actsBinary) {
        console.warn('[ACTS] Binary not found. Build it from acts-core or install it.');
        return;
      }
      if (!actsProject) {
        console.warn('[ACTS] No ACTS v2 project detected (.acts/stack.json missing). Run `acts stack create <id>`.');
        return;
      }
      console.log(`[ACTS] Plugin v${PLUGIN_VERSION} loaded. Mode: ${pluginState.mode}`);
      if (pluginState.mode !== 'off') {
        try {
          const status = refreshStackStatus();
          if (status) {
            console.log(`[ACTS] Stack: ${status.id} — ${status.title} (base: ${status.base_branch})`);
          }
        } catch (e) {
          console.warn('[ACTS] Failed to auto-read stack status:', e.message);
        }
      }
    }
  };
};
