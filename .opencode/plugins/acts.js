import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

export const ActsPlugin = async ({ client, directory }) => {
  // Find acts binary
  const findActsBinary = () => {
    // Check project-local .acts/bin/acts
    const localPath = path.join(directory, '.acts', 'bin', 'acts');
    if (fs.existsSync(localPath)) {
      return localPath;
    }
    
    // Check PATH
    try {
      const which = execSync('which acts', { encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] });
      return which.trim();
    } catch {
      return null;
    }
  };

  const actsBinary = findActsBinary();
  
  // Helper to generate bootstrap content
  const getBootstrapContent = () => {
    return `<EXTREMELY_IMPORTANT>
This project uses ACTS (Agent Collaborative Tracking Standard) v1.0.0.

Rules:
- Read state before writing code: acts state read
- Do not modify files owned by DONE tasks: acts scope check --task <id> --file <path>
- Record session summary before ending: acts session validate <file.md>
- Stay within assigned task boundary
- Run code review before task completion: acts gate add --task <id> --type task-review --status approved
- Follow gate protocol: preflight gate required before starting task

ACTS commands:
- acts init <story-id>              Initialize new story
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

  return {
    // Inject ACTS bootstrap context into first user message
    'experimental.chat.messages.transform': async (_input, output) => {
      const bootstrap = getBootstrapContent();
      if (!bootstrap || !output.messages.length) return;
      const firstUser = output.messages.find(m => m.info.role === 'user');
      if (!firstUser || !firstUser.parts.length) return;
      // Only inject once
      if (firstUser.parts.some(p => p.type === 'text' && p.text.includes('ACTS (Agent Collaborative Tracking Standard)'))) return;
      const ref = firstUser.parts[0];
      firstUser.parts.unshift({ ...ref, type: 'text', text: bootstrap });
    },

    // Register acts tool
    tools: async () => {
      if (!actsBinary) return {};
      
      return {
        acts: {
          description: 'Execute ACTS (Agent Collaborative Tracking Standard) commands for project coordination and gate enforcement',
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
              const result = execSync(`"${actsBinary}" ${command}`, {
                encoding: 'utf8',
                cwd: directory,
                timeout: 30000,
                stdio: ['pipe', 'pipe', 'pipe']
              });
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
        }
      };
    },

    // Provide config hints
    config: async (config) => {
      if (!actsBinary) {
        console.warn('ACTS binary not found. Run `acts init <story-id>` to initialize.');
      }
    }
  };
};
