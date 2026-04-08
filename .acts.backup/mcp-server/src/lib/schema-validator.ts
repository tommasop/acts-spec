import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import Ajv from 'ajv';

// We use a minimal inline validator since we don't want to depend on ajv at runtime
// JSON Schema validation is done structurally

export interface ValidationResult {
  valid: boolean;
  errors: string[];
}

export class SchemaValidator {
  private schemasDir: string;
  private cache: Map<string, Record<string, unknown>> = new Map();

  constructor(schemasDir: string) {
    this.schemasDir = schemasDir;
  }

  async loadSchema(name: string): Promise<Record<string, unknown>> {
    if (this.cache.has(name)) {
      return this.cache.get(name)!;
    }
    const path = join(this.schemasDir, `${name}.json`);
    const raw = await readFile(path, 'utf-8');
    const schema = JSON.parse(raw) as Record<string, unknown>;
    this.cache.set(name, schema);
    return schema;
  }

  validateStateJson(state: Record<string, unknown>): ValidationResult {
    const errors: string[] = [];

    const required = ['acts_version', 'story_id', 'title', 'status', 'spec_approved', 'created_at', 'updated_at', 'context_budget', 'tasks'];
    for (const field of required) {
      if (!(field in state)) {
        errors.push(`Missing required field: ${field}`);
      }
    }

    if (state.status && !['ANALYSIS', 'APPROVED', 'IN_PROGRESS', 'REVIEW', 'DONE'].includes(state.status as string)) {
      errors.push(`Invalid status: ${state.status}`);
    }

    if (state.tasks && Array.isArray(state.tasks)) {
      for (const task of state.tasks) {
        const taskErrors = this.validateTask(task as Record<string, unknown>);
        errors.push(...taskErrors);
      }
    }

    return { valid: errors.length === 0, errors };
  }

  validateTask(task: Record<string, unknown>): string[] {
    const errors: string[] = [];
    const required = ['id', 'title', 'status', 'assigned_to', 'files_touched', 'depends_on'];
    for (const field of required) {
      if (!(field in task)) {
        errors.push(`Task missing required field: ${field}`);
      }
    }

    if (task.id && !/^T\d+$/.test(task.id as string)) {
      errors.push(`Invalid task ID: ${task.id}`);
    }

    if (task.status && !['TODO', 'IN_PROGRESS', 'BLOCKED', 'DONE'].includes(task.status as string)) {
      errors.push(`Invalid task status: ${task.status}`);
    }

    return errors;
  }

  validateDecisions(data: Record<string, unknown>): ValidationResult {
    const errors: string[] = [];

    const required = ['decisions', 'rejected_approaches', 'open_questions'];
    for (const field of required) {
      if (!(field in data)) {
        errors.push(`Missing required field: ${field}`);
      }
    }

    if (data.decisions && Array.isArray(data.decisions)) {
      for (let i = 0; i < data.decisions.length; i++) {
        const d = data.decisions[i] as Record<string, unknown>;
        const dRequired = ['task_id', 'timestamp', 'session', 'topic', 'decided', 'reason', 'evidence', 'authority'];
        for (const field of dRequired) {
          if (!(field in d)) {
            errors.push(`Decision[${i}] missing required field: ${field}`);
          }
        }
        if (d.authority && !['developer_approved', 'agent_decided'].includes(d.authority as string)) {
          errors.push(`Decision[${i}] invalid authority: ${d.authority}`);
        }
      }
    }

    if (data.rejected_approaches && Array.isArray(data.rejected_approaches)) {
      for (let i = 0; i < data.rejected_approaches.length; i++) {
        const r = data.rejected_approaches[i] as Record<string, unknown>;
        const rRequired = ['task_id', 'timestamp', 'session', 'approach', 'reason', 'evidence'];
        for (const field of rRequired) {
          if (!(field in r)) {
            errors.push(`RejectedApproach[${i}] missing required field: ${field}`);
          }
        }
      }
    }

    return { valid: errors.length === 0, errors };
  }
}
