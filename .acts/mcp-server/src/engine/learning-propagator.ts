import { StateReader, DecisionsFile, RejectedApproach } from '../lib/state-reader.js';

export interface LearningMatch {
  source_task: string;
  approach: string;
  reason: string;
  evidence: string;
  tags: string[];
  relevance_score: number;
}

export class LearningPropagator {
  private stateReader: StateReader;

  constructor(stateReader: StateReader) {
    this.stateReader = stateReader;
  }

  async recordRejectedApproach(
    taskId: string,
    session: string,
    approach: string,
    reason: string,
    evidence: string,
    tags: string[] = []
  ): Promise<void> {
    const decisions = await this.stateReader.readDecisions();

    const entry: RejectedApproach = {
      task_id: taskId,
      timestamp: new Date().toISOString(),
      session,
      approach,
      reason,
      evidence,
      tags,
    };

    decisions.rejected_approaches.push(entry);
    await this.stateReader.writeDecisions(decisions);
  }

  async getRelevantLearnings(taskId: string, taskTags: string[] = []): Promise<LearningMatch[]> {
    const decisions = await this.stateReader.readDecisions();

    const matches: LearningMatch[] = [];
    for (const approach of decisions.rejected_approaches) {
      // Skip approaches from the same task
      if (approach.task_id === taskId) continue;

      // Calculate relevance score based on tag overlap
      let relevanceScore = 0.5; // base relevance for all cross-task approaches
      if (taskTags.length > 0 && approach.tags && approach.tags.length > 0) {
        const overlap = approach.tags.filter(t => taskTags.includes(t)).length;
        relevanceScore = 0.3 + (overlap / Math.max(taskTags.length, approach.tags.length)) * 0.7;
      }

      matches.push({
        source_task: approach.task_id,
        approach: approach.approach,
        reason: approach.reason,
        evidence: approach.evidence,
        tags: approach.tags || [],
        relevance_score: Math.round(relevanceScore * 100) / 100,
      });
    }

    // Sort by relevance (highest first)
    matches.sort((a, b) => b.relevance_score - a.relevance_score);
    return matches;
  }

  async getUnresolvedQuestions(taskId?: string): Promise<Array<{
    task_id: string;
    question: string;
    raised_by: string;
    status: string;
  }>> {
    const decisions = await this.stateReader.readDecisions();

    return decisions.open_questions
      .filter(q => q.status === 'unresolved' && (!taskId || q.task_id === taskId))
      .map(q => ({
        task_id: q.task_id,
        question: q.question,
        raised_by: q.raised_by,
        status: q.status,
      }));
  }

  formatLearnings(matches: LearningMatch[]): string {
    if (matches.length === 0) {
      return 'No rejected approaches from other tasks.';
    }

    let output = '## Rejected Approaches from Other Tasks\n\n';
    for (const match of matches) {
      output += `### From ${match.source_task} (relevance: ${match.relevance_score})\n`;
      output += `**Approach**: ${match.approach}\n`;
      output += `**Why rejected**: ${match.reason}\n`;
      output += `**Evidence**: ${match.evidence}\n`;
      if (match.tags.length > 0) {
        output += `**Tags**: ${match.tags.join(', ')}\n`;
      }
      output += '\n';
    }
    return output;
  }
}
