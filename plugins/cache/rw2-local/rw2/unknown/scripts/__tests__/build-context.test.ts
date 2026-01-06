/**
 * Tests for build-context.ts
 *
 * Tests context building logic:
 * - Header generation with iteration info
 * - Strategy guidance inclusion
 * - Mission/objective display
 * - Nudge content handling
 * - Error context handling
 * - Completion promise reminder
 */

import { describe, test, expect } from "bun:test";
import type { RalphState, StrategyResult, TranscriptAnalysis, RalphMemory } from "../types";

const SCRIPT_DIR = "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts";

// ===== Test Fixtures =====

function createState(overrides: Partial<RalphState> = {}): RalphState {
  return {
    active: true,
    iteration: 5,
    max_iterations: 50,
    completion_promise: null,
    started_at: "2026-01-01T00:00:00Z",
    checkpoint_interval: 0,
    checkpoint_mode: "notify",
    strategy: {
      current: "focused",
      changed_at: 11,
    },
    progress: {
      stuck_count: 0,
      velocity: "normal",
      last_meaningful_change: 4,
    },
    phases: [],
    prompt_text: "Build a REST API for user management",
    ...overrides,
  };
}

function createStrategy(overrides: Partial<StrategyResult> = {}): StrategyResult {
  return {
    strategy: "focused",
    reason: "Iteration 15: Focused implementation phase",
    action: "continue",
    guidance: [
      "Commit to the best approach identified during exploration",
      "Implement incrementally with tests",
    ],
    ...overrides,
  };
}

function createAnalysis(overrides: Partial<TranscriptAnalysis> = {}): TranscriptAnalysis {
  return {
    errors: [],
    repeated_errors: [],
    files_modified: [],
    tests_run: false,
    tests_passed: false,
    tests_failed: false,
    phase_completions: [],
    meaningful_changes: true,
    ...overrides,
  };
}

function createMemory(overrides: Partial<RalphMemory> = {}): RalphMemory {
  return {
    session_id: "ralph-test-123",
    started_at: "2026-01-01T00:00:00Z",
    last_updated: "2026-01-01T01:00:00Z",
    current_iteration: 5,
    original_objective: "Build a REST API for user management",
    current_status: "Working on the user endpoints",
    accomplished: [
      { iteration: 1, description: "Set up project structure" },
      { iteration: 3, description: "Created database schema" },
    ],
    failed_attempts: [],
    next_actions: ["Implement user creation endpoint", "Add validation"],
    key_learnings: ["Use TypeScript strict mode", "Always add input validation"],
    ...overrides,
  };
}

// ===== Helper to run context builder =====

async function runContextBuilder(input: any): Promise<string> {
  const proc = Bun.spawn(["bun", "run", "build-context.ts"], {
    cwd: SCRIPT_DIR,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });

  proc.stdin.write(JSON.stringify(input));
  proc.stdin.end();

  return await new Response(proc.stdout).text();
}

// ===== Tests =====

describe("Build Context", () => {
  describe("Header Generation", () => {
    test("includes iteration number in header", async () => {
      const input = {
        state: createState({ iteration: 7 }),
        strategy: createStrategy(),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("RALPH ITERATION 7");
    });

    test("includes strategy name in header", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy({ strategy: "cleanup" }),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("CLEANUP");
    });

    test("uses dividers for visual separation", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("═");
    });
  });

  describe("Mission/Objective Display", () => {
    test("includes YOUR MISSION section", async () => {
      const input = {
        state: createState({ prompt_text: "Build a chat application" }),
        strategy: createStrategy(),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("## YOUR MISSION");
      expect(output).toContain("Build a chat application");
    });

    test("uses memory objective when available", async () => {
      const input = {
        state: createState({ prompt_text: "Simple prompt" }),
        strategy: createStrategy(),
        memory: createMemory({ original_objective: "Complex objective from memory" }),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("Complex objective from memory");
    });

    test("shows placeholder when no objective", async () => {
      const input = {
        state: createState({ prompt_text: "" }),
        strategy: createStrategy(),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("_No objective recorded_");
    });
  });

  describe("Strategy Guidance", () => {
    test("includes STRATEGY GUIDANCE section", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy({
          guidance: ["First guidance", "Second guidance"],
        }),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("## STRATEGY GUIDANCE");
      expect(output).toContain("First guidance");
      expect(output).toContain("Second guidance");
    });

    test("includes strategy reason", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy({ reason: "Custom reason for strategy" }),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("Custom reason for strategy");
    });
  });

  describe("Current Status and Next Actions", () => {
    test("includes CURRENT STATUS when in memory", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        memory: createMemory({ current_status: "Implementing the login feature" }),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("## CURRENT STATUS");
      expect(output).toContain("Implementing the login feature");
    });

    test("includes NEXT ACTIONS when in memory", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        memory: createMemory({
          next_actions: ["Add error handling", "Write tests"],
        }),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("## NEXT ACTIONS");
      expect(output).toContain("Add error handling");
      expect(output).toContain("Write tests");
    });

    test("limits next actions to 5", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        memory: createMemory({
          next_actions: ["Action 1", "Action 2", "Action 3", "Action 4", "Action 5", "Action 6", "Action 7"],
        }),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("Action 5");
      expect(output).not.toContain("Action 6");
    });
  });

  describe("Key Learnings", () => {
    test("includes KEY LEARNINGS section when present", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        memory: createMemory({
          key_learnings: ["Learning 1", "Learning 2"],
        }),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("## KEY LEARNINGS");
      expect(output).toContain("Learning 1");
    });

    test("omits KEY LEARNINGS when empty", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        memory: createMemory({ key_learnings: [] }),
      };

      const output = await runContextBuilder(input);

      expect(output).not.toContain("## KEY LEARNINGS");
    });

    test("limits learnings to last 5", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        memory: createMemory({
          key_learnings: ["Old 1", "Old 2", "Recent 1", "Recent 2", "Recent 3", "Recent 4", "Recent 5"],
        }),
      };

      const output = await runContextBuilder(input);

      // Should show last 5, not first ones
      expect(output).toContain("Recent 5");
      expect(output).not.toContain("Old 1");
    });
  });

  describe("Nudge Content", () => {
    test("includes PRIORITY INSTRUCTION for nudges", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        nudge_content: "Focus on the authentication bug first!",
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("## PRIORITY INSTRUCTION");
      expect(output).toContain("Focus on the authentication bug first!");
    });

    test("marks nudge as ONE-TIME", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        nudge_content: "Any nudge content",
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("ONE-TIME");
    });

    test("omits nudge section when not present", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
      };

      const output = await runContextBuilder(input);

      expect(output).not.toContain("PRIORITY INSTRUCTION");
    });
  });

  describe("Error Context", () => {
    test("includes RECENT ERRORS when present", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        analysis: createAnalysis({
          errors: [
            { pattern: "TypeScript compilation error", sample: "error TS2345" },
          ],
        }),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("## RECENT ERRORS");
      expect(output).toContain("TypeScript compilation error");
      expect(output).toContain("error TS2345");
    });

    test("deduplicates error patterns", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        analysis: createAnalysis({
          errors: [
            { pattern: "Same error", sample: "sample 1" },
            { pattern: "Same error", sample: "sample 2" },
            { pattern: "Same error", sample: "sample 3" },
          ],
        }),
      };

      const output = await runContextBuilder(input);

      // Should only show the pattern once
      const matches = output.match(/Same error/g);
      expect(matches?.length).toBe(1);
    });

    test("limits errors to 3", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        analysis: createAnalysis({
          errors: [
            { pattern: "Error 1", sample: "s1" },
            { pattern: "Error 2", sample: "s2" },
            { pattern: "Error 3", sample: "s3" },
            { pattern: "Error 4", sample: "s4" },
            { pattern: "Error 5", sample: "s5" },
          ],
        }),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("Error 3");
      expect(output).not.toContain("Error 4");
    });

    test("omits errors section when no errors", async () => {
      const input = {
        state: createState(),
        strategy: createStrategy(),
        analysis: createAnalysis({ errors: [] }),
      };

      const output = await runContextBuilder(input);

      expect(output).not.toContain("RECENT ERRORS");
    });
  });

  describe("Completion Promise", () => {
    test("includes completion reminder when promise set", async () => {
      const input = {
        state: createState({ completion_promise: "DONE" }),
        strategy: createStrategy(),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("COMPLETION");
      expect(output).toContain("<promise>DONE</promise>");
    });

    test("warns to only output when TRUE", async () => {
      const input = {
        state: createState({ completion_promise: "Task completed" }),
        strategy: createStrategy(),
      };

      const output = await runContextBuilder(input);

      expect(output).toContain("TRUE");
    });

    test("omits completion section when no promise", async () => {
      const input = {
        state: createState({ completion_promise: null }),
        strategy: createStrategy(),
      };

      const output = await runContextBuilder(input);

      expect(output).not.toContain("COMPLETION:");
    });
  });

  describe("Original Prompt", () => {
    test("includes original prompt at end", async () => {
      const input = {
        state: createState({ prompt_text: "Build a TODO app" }),
        strategy: createStrategy(),
      };

      const output = await runContextBuilder(input);

      // The prompt should appear at the end (after the last divider)
      const lastDividerIndex = output.lastIndexOf("═");
      const afterDivider = output.slice(lastDividerIndex);
      expect(afterDivider).toContain("Build a TODO app");
    });
  });

  describe("Error Handling", () => {
    test("exits with error for empty input", async () => {
      const proc = Bun.spawn(["bun", "run", "build-context.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.end();

      const exitCode = await proc.exited;
      expect(exitCode).not.toBe(0);
    });

    test("exits with error for missing state", async () => {
      const proc = Bun.spawn(["bun", "run", "build-context.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify({ strategy: createStrategy() }));
      proc.stdin.end();

      const exitCode = await proc.exited;
      expect(exitCode).not.toBe(0);
    });

    test("exits with error for missing strategy", async () => {
      const proc = Bun.spawn(["bun", "run", "build-context.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify({ state: createState() }));
      proc.stdin.end();

      const exitCode = await proc.exited;
      expect(exitCode).not.toBe(0);
    });

    test("exits with error for invalid JSON", async () => {
      const proc = Bun.spawn(["bun", "run", "build-context.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write("not valid json");
      proc.stdin.end();

      const exitCode = await proc.exited;
      expect(exitCode).not.toBe(0);
    });
  });
});
