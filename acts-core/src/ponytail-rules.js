// ponytail-rules.js — ponytail runtime plugin: per-run AGENTS.md project rules.
//
// Installed by `acts ponytail install` (project: .opencode/plugins/,
// global: ~/.config/opencode/plugin/). Resolves the CURRENT project's rules
// file (AGENTS.md, CLAUDE.md fallback) on every turn and appends a binding
// precedence directive + path to the system prompt. Because the plugin is
// global but resolves the rules from the session's working directory at run
// time, one install serves every project without baking anything in.
//
// Honored switches:
//   PONYTAIL_DEFAULT_MODE=off            — disable injection
//   ~/.config/ponytail/config.json       — { "defaultMode": "off" }
//
// The directive is idempotent: the PONYTAIL_PROJECT_RULES marker is checked
// before appending, so it appears once per session regardless of turns.

import fs from 'fs';
import os from 'os';
import path from 'path';

const MARKER = 'PONYTAIL_PROJECT_RULES';

// Walk up from `start` (mirrors opencode's own AGENTS.md resolution) for
// AGENTS.md, falling back to CLAUDE.md at each level. Returns the first hit.
function findProjectRules(start) {
  const names = ['AGENTS.md', 'CLAUDE.md'];
  let dir = start;
  for (let depth = 0; dir && depth < 8; depth++) {
    for (const name of names) {
      const p = path.join(dir, name);
      if (fs.existsSync(p)) return p;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

function isDisabled() {
  if (process.env.PONYTAIL_DEFAULT_MODE === 'off') return true;
  try {
    const cfgPath = path.join(
      process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'),
      'ponytail',
      'config.json',
    );
    return JSON.parse(fs.readFileSync(cfgPath, 'utf8')).defaultMode === 'off';
  } catch {
    return false;
  }
}

export const PonytailRules = async ({ directory, worktree }) => {
  const root = worktree || directory;
  return {
    'experimental.chat.system.transform': async (_input, output) => {
      if (isDisabled()) return;
      if (output.system.some((s) => s.includes(MARKER))) return;

      const rulesPath = findProjectRules(root);
      const base = rulesPath ? path.basename(rulesPath) : 'AGENTS.md';
      const directive =
        '## Ponytail · Project rules\n' +
        (rulesPath
          ? rulesPath +
            ' is this project\'s binding ruleset and takes precedence over the ponytail ladder. ' +
            'The ladder finds the smallest change WITHIN the project\'s constraints (build/lint/test ' +
            'commands, conventions, required checks); it never skips what the project requires. ' +
            'If the ' +
            base +
            ' contents are not already in your context, Read the file before acting.'
          : 'This project has no ' + base + ' — the ponytail ladder applies as-is.') +
        '\n<!-- ' + MARKER + ' -->';
      output.system.push(directive);
    },
  };
};