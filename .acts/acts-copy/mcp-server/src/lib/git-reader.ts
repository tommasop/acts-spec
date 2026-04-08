import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export interface GitDiffStat {
  files_changed: number;
  insertions: number;
  deletions: number;
  files: Array<{ path: string; added: number; deleted: number }>;
}

export interface GitStatus {
  branch: string;
  staged: string[];
  modified: string[];
  untracked: string[];
  clean: boolean;
}

export class GitReader {
  private repoRoot: string;

  constructor(repoRoot: string) {
    this.repoRoot = repoRoot;
  }

  private async git(...args: string[]): Promise<string> {
    try {
      const { stdout } = await execFileAsync('git', args, {
        cwd: this.repoRoot,
        maxBuffer: 10 * 1024 * 1024,
      });
      return stdout.trim();
    } catch (e: unknown) {
      const err = e as Error;
      throw new Error(`git ${args[0]} failed: ${err.message}`);
    }
  }

  async status(): Promise<GitStatus> {
    const branch = await this.git('branch', '--show-current');
    const statusOutput = await this.git('status', '--porcelain');

    const staged: string[] = [];
    const modified: string[] = [];
    const untracked: string[] = [];

    for (const line of statusOutput.split('\n')) {
      if (!line.trim()) continue;
      const index = line[0];
      const worktree = line[1];
      const path = line.slice(3);

      if (index === '?' && worktree === '?') {
        untracked.push(path);
      } else if (index !== ' ' && index !== '?') {
        staged.push(path);
      } else if (worktree !== ' ' && worktree !== '?') {
        modified.push(path);
      }
    }

    return {
      branch,
      staged,
      modified,
      untracked,
      clean: staged.length === 0 && modified.length === 0 && untracked.length === 0,
    };
  }

  async diff(cached = false): Promise<string> {
    const args = ['diff'];
    if (cached) args.push('--cached');
    return this.git(...args);
  }

  async diffStat(cached = false): Promise<GitDiffStat> {
    const args = ['diff', '--stat', '--numstat'];
    if (cached) args.push('--cached');
    const output = await this.git(...args);

    const files: Array<{ path: string; added: number; deleted: number }> = [];
    let insertions = 0;
    let deletions = 0;

    for (const line of output.split('\n')) {
      const match = line.match(/^(\d+)\s+(\d+)\s+(.+)$/);
      if (match) {
        const added = parseInt(match[1], 10);
        const deleted = parseInt(match[2], 10);
        const path = match[3];
        if (!isNaN(added) && !isNaN(deleted)) {
          files.push({ path, added, deleted });
          insertions += added;
          deletions += deleted;
        }
      }
    }

    return {
      files_changed: files.length,
      insertions,
      deletions,
      files,
    };
  }

  async log(count = 10): Promise<string> {
    return this.git('log', `--oneline`, `-n`, String(count));
  }

  async filesChangedSince(base: string): Promise<string[]> {
    const output = await this.git('diff', '--name-only', base);
    return output.split('\n').filter(Boolean);
  }

  async showCommit(hash: string): Promise<string> {
    return this.git('show', hash);
  }

  async getWorktreeId(): Promise<string> {
    try {
      const output = await this.git('rev-parse', '--show-toplevel');
      return output;
    } catch {
      return this.repoRoot;
    }
  }

  async listBranches(): Promise<string[]> {
    const output = await this.git('branch', '--list');
    return output.split('\n').map(b => b.replace(/^[\s*]+/, '').trim()).filter(Boolean);
  }
}
