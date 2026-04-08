import { SessionReader, SessionSummary } from '../lib/session-reader.js';
import { StateReader } from '../lib/state-reader.js';

export interface CompactionResult {
  task_id: string;
  sessions_before: number;
  sessions_after: number;
  compressed_file: string;
  preserved: string[];
  discarded: string[];
}

export class CompactionEngine {
  private sessionReader: SessionReader;
  private stateReader: StateReader;

  constructor(sessionReader: SessionReader, stateReader: StateReader) {
    this.sessionReader = sessionReader;
    this.stateReader = stateReader;
  }

  async compact(taskId: string, keepLatest = 2): Promise<CompactionResult> {
    const sessions = await this.sessionReader.readAllSessionsForTask(taskId);

    if (sessions.length <= keepLatest) {
      return {
        task_id: taskId,
        sessions_before: sessions.length,
        sessions_after: sessions.length,
        compressed_file: '',
        preserved: ['No compaction needed — fewer sessions than keep_latest'],
        discarded: [],
      };
    }

    // Keep the latest N sessions uncompressed
    const toCompress = sessions.slice(0, sessions.length - keepLatest);
    const toKeep = sessions.slice(sessions.length - keepLatest);

    // Apply preservation contract:
    // PRESERVE: decisions, rejected approaches, open questions, files_touched
    // DISCARD: raw tool outputs, verbose explorations, superseded context
    const compacted = this.sessionReader.compactSessions(toCompress);

    const { writeFile } = await import('node:fs/promises');
    const { join } = await import('node:path');
    const state = await this.stateReader.readState();
    const storyDir = join(this.stateReader['storyDir'], 'sessions');
    const compressedPath = join(storyDir, `compressed-${taskId}.md`);

    await writeFile(compressedPath, compacted, 'utf-8');

    // Update state.json
    state.compressed = true;
    await this.stateReader.writeState(state);

    const preserved = [
      'Decisions and rationale (ALL)',
      'Rejected approaches (ALL — never compressed)',
      'Open questions (unresolved only)',
      'Files touched (union of all sessions)',
    ];

    const discarded = [
      'Raw tool outputs (error tracebacks, file reads)',
      'Verbose explorations (keep decision, discard exploration)',
      'Superseded context (annotated, not deleted)',
    ];

    return {
      task_id: taskId,
      sessions_before: sessions.length,
      sessions_after: keepLatest,
      compressed_file: `compressed-${taskId}.md`,
      preserved,
      discarded,
    };
  }

  shouldAutoCompact(taskId: string, threshold: number): Promise<boolean> {
    return this.sessionReader.readAllSessionsForTask(taskId)
      .then(sessions => sessions.length >= threshold);
  }
}
