/**
 * Tests for strategy-engine.ts
 *
 * Tests the Ralph Wiggum strategy determination logic:
 * - Phase-based strategy (explore -> focused -> cleanup)
 * - Recovery mode triggers
 * - Strategy guidance generation
 */

import { describe, test, expect } from "bun:test";
import type { RalphState, TranscriptAnalysis, StrategyResult } from "../types";

// Since the functions are not exported, we'll test via the CLI interface
// and also extract the pure functions for unit testing

// ===== Helper to create test inputs =====

function createState(overrides: Partial<RalphState> = {}): RalphState {
  return {
    active: true,
    iteration: 1,
    max_iterations: 50,
    completion_promise: null,
    started_at: "2026-01-01T00:00:00Z",
    checkpoint_interval: 0,
    checkpoint_mode: "notify",
    strategy: {
      current: "explore",
      changed_at: 0,
    },
    progress: {
      stuck_count: 0,
      velocity: "normal",
      last_meaningful_change: 0,
    },
    phases: [],
    prompt_text: "Test prompt",
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

// ===== Strategy Determination Logic (extracted for testing) =====

const EXPLORE_END = 10;
const FOCUSED_END = 35;
const REPEATED_ERROR_THRESHOLD = 3;
const STUCK_THRESHOLD = 5;

function determineBaseStrategy(iteration: number): "explore" | "focused" | "cleanup" {
  if (iteration <= EXPLORE_END) {
    return "explore";
  } else if (iteration <= FOCUSED_END) {
    return "focused";
  } else {
    return "cleanup";
  }
}

// ===== Tests =====

describe("Strategy Engine", () => {
  describe("Base Strategy Determination", () => {
    test("returns 'explore' for iterations 1-10", () => {
      expect(determineBaseStrategy(1)).toBe("explore");
      expect(determineBaseStrategy(5)).toBe("explore");
      expect(determineBaseStrategy(10)).toBe("explore");
    });

    test("returns 'focused' for iterations 11-35", () => {
      expect(determineBaseStrategy(11)).toBe("focused");
      expect(determineBaseStrategy(20)).toBe("focused");
      expect(determineBaseStrategy(35)).toBe("focused");
    });

    test("returns 'cleanup' for iterations 36+", () => {
      expect(determineBaseStrategy(36)).toBe("cleanup");
      expect(determineBaseStrategy(50)).toBe("cleanup");
      expect(determineBaseStrategy(100)).toBe("cleanup");
    });

    test("handles edge cases correctly", () => {
      expect(determineBaseStrategy(0)).toBe("explore");
      expect(determineBaseStrategy(-1)).toBe("explore");
    });
  });

  describe("CLI Integration", () => {
    test("outputs explore strategy for iteration 1", async () => {
      const input = {
        state: createState({ iteration: 1 }),
        analysis: createAnalysis(),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("explore");
      expect(result.action).toBe("continue");
      expect(result.guidance).toBeArray();
      expect(result.guidance.length).toBeGreaterThan(0);
    });

    test("outputs focused strategy for iteration 15", async () => {
      const input = {
        state: createState({
          iteration: 15,
          strategy: { current: "explore", changed_at: 0 }
        }),
        analysis: createAnalysis(),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("focused");
      expect(result.action).toBe("switch");
    });

    test("outputs cleanup strategy for iteration 40", async () => {
      const input = {
        state: createState({
          iteration: 40,
          strategy: { current: "focused", changed_at: 11 }
        }),
        analysis: createAnalysis(),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      // Add timeout for reading stdout
      const outputPromise = new Response(proc.stdout).text();
      const timeoutPromise = new Promise<string>((_, reject) =>
        setTimeout(() => reject(new Error("timeout")), 10000)
      );
      const output = await Promise.race([outputPromise, timeoutPromise]);
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("cleanup");
      expect(result.action).toBe("switch");
    }, 15000);

    test("triggers recovery on repeated errors (3+)", async () => {
      const input = {
        state: createState({ iteration: 5 }),
        analysis: createAnalysis({
          repeated_errors: [
            { pattern: "TypeScript compilation error", count: 3 }
          ],
        }),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("recovery");
      expect(result.reason).toContain("repeated");
      expect(result.action).toBe("switch");
    });

    test("triggers recovery when stuck (5+ iterations)", async () => {
      const input = {
        state: createState({
          iteration: 10,
          progress: {
            stuck_count: 5,
            velocity: "stalled",
            last_meaningful_change: 5,
          }
        }),
        analysis: createAnalysis({ meaningful_changes: false }),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("recovery");
      expect(result.reason).toContain("Stuck");
    });

    test("handles empty input gracefully", async () => {
      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("explore");
      expect(result.reason).toContain("Default");
    });

    test("handles invalid JSON gracefully", async () => {
      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write("not valid json");
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("explore");
      expect(result.reason).toContain("Default");
    });

    test("handles missing state/analysis fields gracefully", async () => {
      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify({ foo: "bar" }));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("explore");
    });
  });

  describe("Strategy Guidance", () => {
    test("explore guidance includes exploration tips", async () => {
      const input = {
        state: createState({ iteration: 1 }),
        analysis: createAnalysis(),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.guidance.some(g => g.toLowerCase().includes("explore"))).toBe(true);
    });

    test("focused guidance includes implementation tips", async () => {
      const input = {
        state: createState({
          iteration: 15,
          strategy: { current: "focused", changed_at: 11 }
        }),
        analysis: createAnalysis(),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.guidance.some(g => g.toLowerCase().includes("implement"))).toBe(true);
    });

    test("cleanup guidance includes finishing tips", async () => {
      const input = {
        state: createState({
          iteration: 40,
          strategy: { current: "cleanup", changed_at: 36 }
        }),
        analysis: createAnalysis(),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.guidance.some(g => g.toLowerCase().includes("finish"))).toBe(true);
    });

    test("recovery guidance mentions specific error pattern", async () => {
      const input = {
        state: createState({ iteration: 5 }),
        analysis: createAnalysis({
          repeated_errors: [
            { pattern: "TypeScript compilation error", count: 4 }
          ],
        }),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.guidance.some(g => g.includes("TypeScript"))).toBe(true);
    });
  });

  describe("Progress Context in Reason", () => {
    test("includes 'making progress' when meaningful_changes is true", async () => {
      const input = {
        state: createState({ iteration: 5 }),
        analysis: createAnalysis({ meaningful_changes: true }),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.reason).toContain("making progress");
    });

    test("warns when no meaningful changes after iteration 1", async () => {
      const input = {
        state: createState({ iteration: 3 }),
        analysis: createAnalysis({ meaningful_changes: false }),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.reason).toContain("no meaningful changes");
    });
  });

  describe("Edge Cases", () => {
    test("handles iteration 0", async () => {
      const input = {
        state: createState({ iteration: 0 }),
        analysis: createAnalysis(),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("explore");
    });

    test("handles very high iteration counts", async () => {
      const input = {
        state: createState({
          iteration: 1000,
          strategy: { current: "cleanup", changed_at: 36 }
        }),
        analysis: createAnalysis(),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("cleanup");
    });

    test("recovery takes precedence over phase strategy", async () => {
      // Even in cleanup phase, repeated errors should trigger recovery
      const input = {
        state: createState({
          iteration: 40,
          strategy: { current: "cleanup", changed_at: 36 }
        }),
        analysis: createAnalysis({
          repeated_errors: [
            { pattern: "Test failure", count: 5 }
          ],
        }),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("recovery");
    });

    test("multiple repeated errors - uses first meeting threshold", async () => {
      const input = {
        state: createState({ iteration: 5 }),
        analysis: createAnalysis({
          repeated_errors: [
            { pattern: "Error A", count: 2 },  // Below threshold
            { pattern: "Error B", count: 4 },  // Above threshold - this one
            { pattern: "Error C", count: 3 },  // At threshold
          ],
        }),
      };

      const proc = Bun.spawn(["bun", "run", "strategy-engine.ts"], {
        cwd: "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts",
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      const result: StrategyResult = JSON.parse(output);

      expect(result.strategy).toBe("recovery");
      expect(result.reason).toContain("Error B");
    });
  });
});
