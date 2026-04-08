import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

export interface SessionSummary {
  filename: string;
  developer: string;
  agent?: string;
  date: string;
  task_id: string;
  what_was_done: string;
  decisions_made: string;
  what_was_not_done: string;
  approaches_tried_and_rejected: string;
  open_questions: string;
  current_state: {
    compiles: boolean;
    tests_pass: boolean;
    uncommitted_work: boolean;
  };
  files_touched: string;
  suggested_next_step: string;
  agent_compliance?: {
    read_agent_md: boolean;
    read_state_json: boolean;
    followed_preflight: boolean;
    followed_context_protocol: boolean;
    deviated_from_plan: boolean;
  };
}

export class SessionReader {
  private storyDir: string;

  constructor(storyDir: string) {
    this.storyDir = storyDir;
  }

  async readSession(filename: string): Promise<SessionSummary | null> {
    const path = join(this.storyDir, 'sessions', filename);
    try {
      const raw = await readFile(path, 'utf-8');
      return this.parseSession(filename, raw);
    } catch {
      return null;
    }
  }

  async readLatestSessions(taskId: string, count: number): Promise<SessionSummary[]> {
    const { readdir } = await import('node:fs/promises');
    const sessionsDir = join(this.storyDir, 'sessions');
    try {
      const files = await readdir(sessionsDir);
      const sessionFiles = files
        .filter(f => f.endsWith('.md'))
        .sort()
        .reverse();

      const sessions: SessionSummary[] = [];
      for (const file of sessionFiles) {
        if (sessions.length >= count) break;
        const session = await this.readSession(file);
        if (session && session.task_id === taskId) {
          sessions.push(session);
        }
      }
      return sessions;
    } catch {
      return [];
    }
  }

  async readAllSessionsForTask(taskId: string): Promise<SessionSummary[]> {
    const { readdir } = await import('node:fs/promises');
    const sessionsDir = join(this.storyDir, 'sessions');
    try {
      const files = await readdir(sessionsDir);
      const sessionFiles = files
        .filter(f => f.endsWith('.md'))
        .sort();

      const sessions: SessionSummary[] = [];
      for (const file of sessionFiles) {
        const session = await this.readSession(file);
        if (session && session.task_id === taskId) {
          sessions.push(session);
        }
      }
      return sessions;
    } catch {
      return [];
    }
  }

  async readCompressedSession(taskId: string): Promise<string | null> {
    const path = join(this.storyDir, 'sessions', `compressed-${taskId}.md`);
    try {
      return await readFile(path, 'utf-8');
    } catch {
      return null;
    }
  }

  compactSessions(sessions: SessionSummary[]): string {
    if (sessions.length === 0) return '';

    const decisions: string[] = [];
    const rejected: string[] = [];
    const questions: string[] = [];
    const filesUnion = new Set<string>();

    for (const session of sessions) {
      if (session.decisions_made && session.decisions_made !== 'None') {
        decisions.push(`- ${session.decisions_made}`);
      }
      if (session.approaches_tried_and_rejected && session.approaches_tried_and_rejected !== 'None') {
        rejected.push(`- ${session.approaches_tried_and_rejected}`);
      }
      if (session.open_questions && session.open_questions !== 'None') {
        questions.push(`- ${session.open_questions}`);
      }
      for (const f of session.files_touched.split('\n')) {
        const match = f.match(/^- (.+)/);
        if (match) filesUnion.add(match[1].trim());
      }
    }

    const latest = sessions[sessions.length - 1];
    let result = `# Compressed Sessions for ${latest.task_id}\n\n`;
    result += `## Decisions\n${decisions.length > 0 ? decisions.join('\n') : 'None'}\n\n`;
    result += `## Approaches tried and rejected\n${rejected.length > 0 ? rejected.join('\n') : 'None'}\n\n`;
    result += `## Open questions\n${questions.length > 0 ? questions.join('\n') : 'None'}\n\n`;
    result += `## Files touched\n${filesUnion.size > 0 ? [...filesUnion].map(f => `- ${f}`).join('\n') : 'None'}\n\n`;
    result += `## Last known state\n- Compiles: ${latest.current_state.compiles}\n- Tests pass: ${latest.current_state.tests_pass}\n- Uncommitted work: ${latest.current_state.uncommitted_work}\n`;
    return result;
  }

  private parseSession(filename: string, raw: string): SessionSummary | null {
    const sections = this.extractSections(raw);
    const meta = this.extractMeta(raw);

    return {
      filename,
      developer: meta.developer || 'unknown',
      agent: meta.agent,
      date: meta.date || new Date().toISOString(),
      task_id: meta.task_id || 'T0',
      what_was_done: sections['What was done'] || '',
      decisions_made: sections['Decisions made'] || '',
      what_was_not_done: sections['What was NOT done (and why)'] || '',
      approaches_tried_and_rejected: sections['Approaches tried and rejected'] || '',
      open_questions: sections['Open questions'] || '',
      current_state: this.parseCurrentState(sections['Current state'] || ''),
      files_touched: sections['Files touched this session'] || '',
      suggested_next_step: sections['Suggested next step'] || '',
      agent_compliance: this.parseCompliance(sections['Agent Compliance'] || ''),
    };
  }

  private extractSections(raw: string): Record<string, string> {
    const sections: Record<string, string> = {};
    const lines = raw.split('\n');
    let currentSection = '';
    let currentContent: string[] = [];

    for (const line of lines) {
      const headerMatch = line.match(/^## (.+)/);
      if (headerMatch) {
        if (currentSection) {
          sections[currentSection] = currentContent.join('\n').trim();
        }
        currentSection = headerMatch[1].trim();
        currentContent = [];
      } else if (currentSection) {
        currentContent.push(line);
      }
    }
    if (currentSection) {
      sections[currentSection] = currentContent.join('\n').trim();
    }
    return sections;
  }

  private extractMeta(raw: string): Record<string, string> {
    const meta: Record<string, string> = {};
    const devMatch = raw.match(/\*\*Developer:\*\*\s*(.+)/);
    if (devMatch) meta.developer = devMatch[1].trim();
    const agentMatch = raw.match(/\*\*Agent:\*\*\s*(.+)/);
    if (agentMatch) meta.agent = agentMatch[1].trim();
    const dateMatch = raw.match(/\*\*Date:\*\*\s*(.+)/);
    if (dateMatch) meta.date = dateMatch[1].trim();
    const taskMatch = raw.match(/\*\*Task:\*\*\s*(.+)/);
    if (taskMatch) meta.task_id = taskMatch[1].trim();
    return meta;
  }

  private parseCurrentState(raw: string): { compiles: boolean; tests_pass: boolean; uncommitted_work: boolean } {
    const compiles = /compiles.*(?:true|yes|✅)/i.test(raw) || /compiles: true/i.test(raw);
    const tests = /tests.*(?:pass|true|yes|✅)/i.test(raw) || /tests_pass: true/i.test(raw);
    const uncommitted = /uncommitted.*(?:true|yes)/i.test(raw) || /uncommitted_work: true/i.test(raw);
    return { compiles, tests_pass: tests, uncommitted_work: uncommitted };
  }

  private parseCompliance(raw: string): SessionSummary['agent_compliance'] {
    if (!raw) return undefined;
    return {
      read_agent_md: /read.*AGENTS\.md.*(?:✅|true|yes)/i.test(raw),
      read_state_json: /read.*state\.json.*(?:✅|true|yes)/i.test(raw),
      followed_preflight: /followed.*preflight.*(?:✅|true|yes)/i.test(raw),
      followed_context_protocol: /followed.*context.*(?:✅|true|yes)/i.test(raw),
      deviated_from_plan: /deviated.*(?:✅|true|yes)/i.test(raw),
    };
  }
}
