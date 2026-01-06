#!/usr/bin/env bun
/**
 * Ralph Wiggum - Status Dashboard Generator
 *
 * Generates RALPH_STATUS.md dashboard for monitoring.
 * Updated each iteration with current state.
 *
 * Usage: echo '<input_json>' | bun run update-status.ts [status_path]
 * Input: JSON with state, analysis, strategy
 * Output: Updated status path
 */

import { writeFileSync } from "fs";
import type {
  RalphStatus,
  RalphState,
  TranscriptAnalysis,
  StrategyResult,
  ActivityEntry,
} from "./types";

interface StatusInput {
  state: RalphState;
  analysis: TranscriptAnalysis;
  strategy: StrategyResult;
  previous_activity?: ActivityEntry[];
}

const DEFAULT_STATUS_PATH = ".claude/RALPH_STATUS.md";
const MAX_ACTIVITY_ENTRIES = 10;
const MAX_ERROR_PATTERNS = 5;
const MAX_FILES_SHOWN = 10;

function calculateRuntime(startedAt: string): number {
  const start = new Date(startedAt).getTime();
  const now = Date.now();
  return Math.floor((now - start) / 1000);
}

function calculateNextCheckpoint(
  iteration: number,
  checkpointInterval: number
): number | null {
  if (!checkpointInterval || checkpointInterval <= 0) {
    return null;
  }
  return Math.ceil(iteration / checkpointInterval) * checkpointInterval;
}

function determineActivityStatus(
  analysis: TranscriptAnalysis
): "OK" | "ERROR" | "RETRY" {
  if (analysis.errors.length > 0) {
    return analysis.meaningful_changes ? "RETRY" : "ERROR";
  }
  return "OK";
}

function generateActivityEntry(
  iteration: number,
  analysis: TranscriptAnalysis,
  strategy: StrategyResult
): ActivityEntry {
  let action: string;

  if (analysis.tests_run) {
    if (analysis.tests_passed) {
      action = "Tests passed";
    } else if (analysis.tests_failed) {
      action = "Tests failed";
    } else {
      action = "Tests run";
    }
  } else if (analysis.files_modified.length > 0) {
    action = `Modified ${analysis.files_modified.length} file(s)`;
  } else if (analysis.phase_completions.length > 0) {
    action = `Completed ${analysis.phase_completions.join(", ")}`;
  } else if (strategy.action === "switch") {
    action = `Strategy: ${strategy.strategy}`;
  } else {
    action = "Working...";
  }

  return {
    iteration,
    time: new Date().toISOString().slice(11, 19),
    action,
    status: determineActivityStatus(analysis),
  };
}

function buildStatus(input: StatusInput): RalphStatus {
  const { state, analysis, strategy } = input;

  // Build activity list
  const newActivity = generateActivityEntry(state.iteration, analysis, strategy);
  const activity = [newActivity, ...(input.previous_activity || [])].slice(
    0,
    MAX_ACTIVITY_ENTRIES
  );

  // Collect error patterns
  const errorPatterns = [
    ...new Set(analysis.errors.map((e) => e.pattern)),
  ].slice(0, MAX_ERROR_PATTERNS);

  // Collect files changed
  const filesChanged = analysis.files_modified.slice(0, MAX_FILES_SHOWN);

  return {
    last_updated: new Date().toISOString(),
    status: "running",
    iteration: state.iteration,
    max_iterations: state.max_iterations,
    phase: strategy.strategy,
    started_at: state.started_at,
    runtime_seconds: calculateRuntime(state.started_at),
    next_checkpoint: calculateNextCheckpoint(
      state.iteration,
      state.checkpoint_interval
    ),
    recent_activity: activity,
    error_count: analysis.errors.length,
    error_patterns: errorPatterns,
    files_changed: filesChanged,
  };
}

function formatDuration(seconds: number): string {
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const secs = seconds % 60;

  if (hours > 0) {
    return `${hours}h ${minutes}m ${secs}s`;
  } else if (minutes > 0) {
    return `${minutes}m ${secs}s`;
  }
  return `${secs}s`;
}

function formatStatusFile(status: RalphStatus): string {
  const lines: string[] = [];

  // Header with status
  const statusEmoji =
    status.status === "running"
      ? "🔄"
      : status.status === "paused"
        ? "⏸️"
        : status.status === "completed"
          ? "✅"
          : "❌";

  lines.push(`# Ralph Status ${statusEmoji}`);
  lines.push("");
  lines.push(`_Last updated: ${status.last_updated}_`);
  lines.push("");

  // Quick stats table
  lines.push("## Overview");
  lines.push("");
  lines.push("| Metric | Value |");
  lines.push("|--------|-------|");
  lines.push(`| Status | **${status.status.toUpperCase()}** |`);
  lines.push(
    `| Iteration | ${status.iteration}${status.max_iterations > 0 ? ` / ${status.max_iterations}` : ""} |`
  );
  lines.push(`| Phase | ${status.phase} |`);
  lines.push(`| Runtime | ${formatDuration(status.runtime_seconds)} |`);
  if (status.next_checkpoint) {
    lines.push(`| Next Checkpoint | Iteration ${status.next_checkpoint} |`);
  }
  lines.push(`| Errors | ${status.error_count} |`);
  lines.push("");

  // Progress bar (visual representation)
  if (status.max_iterations > 0) {
    const progress = Math.min(status.iteration / status.max_iterations, 1);
    const filled = Math.round(progress * 20);
    const empty = 20 - filled;
    const bar = "█".repeat(filled) + "░".repeat(empty);
    const percent = Math.round(progress * 100);
    lines.push(`## Progress: ${bar} ${percent}%`);
    lines.push("");
  }

  // Recent activity
  lines.push("## Recent Activity");
  lines.push("");
  if (status.recent_activity.length === 0) {
    lines.push("_No activity yet_");
  } else {
    lines.push("| Iter | Time | Action | Status |");
    lines.push("|------|------|--------|--------|");
    for (const entry of status.recent_activity) {
      const statusIcon =
        entry.status === "OK" ? "✅" : entry.status === "RETRY" ? "🔄" : "❌";
      lines.push(
        `| ${entry.iteration} | ${entry.time} | ${entry.action} | ${statusIcon} |`
      );
    }
  }
  lines.push("");

  // Error patterns (if any)
  if (status.error_patterns.length > 0) {
    lines.push("## Error Patterns");
    lines.push("");
    for (const pattern of status.error_patterns) {
      lines.push(`- ${pattern}`);
    }
    lines.push("");
  }

  // Files changed
  if (status.files_changed.length > 0) {
    lines.push("## Files Changed");
    lines.push("");
    for (const file of status.files_changed) {
      lines.push(`- \`${file}\``);
    }
    lines.push("");
  }

  // Footer with commands
  lines.push("---");
  lines.push("");
  lines.push("**Commands:**");
  lines.push("- `/ralph-status` - Refresh this view");
  lines.push("- `/ralph-nudge <instruction>` - Send guidance");
  lines.push("- `/cancel-ralph` - Stop the loop");
  lines.push("");

  return lines.join("\n");
}

async function main() {
  const statusPath = process.argv[2] || DEFAULT_STATUS_PATH;

  // Read input from stdin
  const chunks: Buffer[] = [];
  for await (const chunk of Bun.stdin.stream()) {
    chunks.push(chunk);
  }
  const inputText = Buffer.concat(chunks).toString("utf-8").trim();

  if (!inputText) {
    console.error(
      "Usage: echo '<input_json>' | bun run update-status.ts [status_path]"
    );
    process.exit(1);
  }

  try {
    const input: StatusInput = JSON.parse(inputText);

    if (!input.state || !input.analysis || !input.strategy) {
      console.error(
        "Input must contain 'state', 'analysis', and 'strategy' fields"
      );
      process.exit(1);
    }

    const status = buildStatus(input);
    writeFileSync(statusPath, formatStatusFile(status));

    console.log(
      JSON.stringify({
        path: statusPath,
        iteration: status.iteration,
        phase: status.phase,
        error_count: status.error_count,
      })
    );
  } catch (error) {
    console.error("Error updating status:", error);
    process.exit(1);
  }
}

main();
