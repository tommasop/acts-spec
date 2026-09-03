// ponytail-rules.js — ponytail runtime plugin: per-run AGENTS.md project rules
// + Magic usage rules (core subset) for Elixir magic consumers.
//
// Installed by `acts ponytail install` (project: .opencode/plugins/,
// global: ~/.config/opencode/plugin/). Resolves the CURRENT project's rules
// file (AGENTS.md, CLAUDE.md fallback) on every turn and appends a binding
// precedence directive + path to the system prompt. When the session is in an
// Elixir magic consumer (or the magic library source), it also injects the
// magic usage-rules core subset (coding-practices + error-handling) so the
// conventions are ALWAYS in context. Because the plugin is global but resolves
// from the session's working directory at run time, one install serves every
// project without baking anything in.
//
// Honored switches:
//   PONYTAIL_DEFAULT_MODE=off            — disable injection entirely
//   PONYTAIL_MAGIC_RULES=off             — disable only the magic rules block
//   ~/.config/ponytail/config.json       — { "defaultMode": "off", "magicRules": false }
//
// The directives are idempotent: each marker is checked before appending, so
// every block appears once per session regardless of turns.

import fs from 'fs';
import os from 'os';
import path from 'path';

const MARKER = 'PONYTAIL_PROJECT_RULES';
const MAGIC_MARKER = 'PONYTAIL_MAGIC_RULES';

// Core subset of the magic usage rules that gate every PR.
const MAGIC_RULES = ['coding-practices.md', 'error-handling.md'];

// Walk up from `start` (mirrors opencode's own AGENTS.md resolution),
// calling fn(dir) at each level; returns the first non-null hit.
function walkUp(start, fn) {
  let dir = start;
  for (let depth = 0; dir && depth < 8; depth++) {
    const hit = fn(dir);
    if (hit) return hit;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return null;
}

// First AGENTS.md (CLAUDE.md fallback) walking up from `start`.
function findProjectRules(start) {
  const names = ['AGENTS.md', 'CLAUDE.md'];
  return walkUp(start, (dir) => {
    for (const name of names) {
      const p = path.join(dir, name);
      if (fs.existsSync(p)) return p;
    }
    return null;
  });
}

// Magic usage-rules dir: `usage-rules/` (magic library source) or
// `deps/magic/usage-rules/` (compiled dep in Elixir consumers), walking up.
function findMagicRulesDir(start) {
  return walkUp(start, (dir) => {
    for (const rel of ['usage-rules', 'deps/magic/usage-rules']) {
      const p = path.join(dir, rel);
      if (fs.existsSync(path.join(p, 'coding-practices.md'))) return p;
    }
    return null;
  });
}

// Fallback: resolve the `magic` reference from the nearest opencode.json
// (references.magic.path) and look for usage-rules/ under it.
function magicRulesFromReference(start) {
  return walkUp(start, (dir) => {
    for (const name of ['opencode.json', 'opencode.jsonc']) {
      const p = path.join(dir, name);
      if (!fs.existsSync(p)) continue;
      try {
        let raw = fs.readFileSync(p, 'utf8');
        let json;
        try {
          json = JSON.parse(raw);
        } catch {
          json = JSON.parse(raw.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, ''));
        }
        const magic = json?.references?.magic;
        if (!magic) continue;
        const refPath = typeof magic === 'string' ? magic : magic.path;
        if (!refPath) continue;
        const rulesDir = path.join(path.resolve(dir, refPath), 'usage-rules');
        if (fs.existsSync(path.join(rulesDir, 'coding-practices.md'))) return rulesDir;
      } catch {
        // unreadable config — treat as absent
      }
    }
    return null;
  });
}

function readPonytailConfig() {
  try {
    const cfgPath = path.join(
      process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'),
      'ponytail',
      'config.json',
    );
    return JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  } catch {
    return {};
  }
}

function isDisabled(cfg) {
  if (process.env.PONYTAIL_DEFAULT_MODE === 'off') return true;
  return cfg.defaultMode === 'off';
}

function isMagicRulesDisabled(cfg) {
  if (process.env.PONYTAIL_MAGIC_RULES === 'off') return true;
  return cfg.magicRules === false;
}

export const PonytailRules = async ({ directory, worktree }) => {
  const root = worktree || directory;
  return {
    'experimental.chat.system.transform': async (_input, output) => {
      const cfg = readPonytailConfig();
      if (isDisabled(cfg)) return;

      // 1. Project rules directive (existing behavior).
      if (!output.system.some((s) => s.includes(MARKER))) {
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
      }

      // 2. Magic usage rules (core subset) — only where a source resolves.
      if (!output.system.some((s) => s.includes(MAGIC_MARKER))) {
        if (!isMagicRulesDisabled(cfg)) {
          const rulesDir = findMagicRulesDir(root) || magicRulesFromReference(root);
          if (rulesDir) {
            const content = MAGIC_RULES.map((f) => {
              const p = path.join(rulesDir, f);
              return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : '';
            })
              .filter(Boolean)
              .join('\n\n');
            if (content) {
              output.system.push(
                '## Magic Usage Rules (binding)\n' +
                  'Magic platform conventions for this Elixir project — apply them to all work here.\n\n' +
                  content +
                  '\n<!-- ' + MAGIC_MARKER + ' -->',
              );
            }
          }
        }
      }
    },
  };
};