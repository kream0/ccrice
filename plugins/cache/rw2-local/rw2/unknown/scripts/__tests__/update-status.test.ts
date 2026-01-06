/**
 * Tests for update-status.ts
 *
 * Tests status file update logic:
 * - Status values (RUNNING, PAUSED, etc.)
 * - Activity logging
 * - Runtime calculation
 * - Error tracking
 */

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { writeFileSync, readFileSync, unlinkSync, mkdirSync, rmdirSync, existsSync } from "fs";
import { join } from "path";

const TEST_DIR = "/tmp/ralph-status-tests";
const SCRIPT_DIR = "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts";

// ===== Setup/Teardown =====

beforeAll(() => {
  try {
    mkdirSync(TEST_DIR, { recursive: true });
    mkdirSync(join(TEST_DIR, ".claude"), { recursive: true });
  } catch {
    // Directory might exist
  }
});

afterAll(() => {
  try {
    const cleanup = (dir: string) => {
      if (existsSync(dir)) {
        const files = require("fs").readdirSync(dir);
        for (const file of files) {
          const path = join(dir, file);
          if (require("fs").statSync(path).isDirectory()) {
            cleanup(path);
          } else {
            unlinkSync(path);
          }
        }
        rmdirSync(dir);
      }
    };
    cleanup(TEST_DIR);
  } catch {
    // Cleanup might fail
  }
});

// ===== Helper to run status updater =====

async function runStatusUpdater(
  statusPath: string,
  input: any
): Promise<{ exitCode: number; output: string }> {
  const proc = Bun.spawn(["bun", "run", "update-status.ts", statusPath], {
    cwd: SCRIPT_DIR,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });

  proc.stdin.write(JSON.stringify(input));
  proc.stdin.end();

  const [output, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    proc.exited,
  ]);

  return { exitCode, output };
}

// ===== Test Fixtures =====

function createState(overrides: any = {}): any {
  return {
    active: true,
    iteration: 5,
    max_iterations: 50,
    completion_promise: null,
    started_at: new Date(Date.now() - 60000).toISOString(), // Started 1 minute ago
    checkpoint_interval: 0,
    checkpoint_mode: "notify",
    strategy: { current: "focused", changed_at: 0 },
    progress: { stuck_count: 0, velocity: "normal", last_meaningful_change: 0 },
    phases: [],
    prompt_text: "Test prompt",
    ...overrides,
  };
}

function createAnalysis(overrides: any = {}): any {
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

function createStrategy(overrides: any = {}): any {
  return {
    strategy: "focused",
    reason: "Focused implementation phase",
    action: "continue",
    guidance: ["Implement incrementally"],
    ...overrides,
  };
}

function createStatusInput(overrides: any = {}): any {
  const { state: stateOverrides, analysis: analysisOverrides, strategy: strategyOverrides, ...rest } = overrides;
  return {
    state: createState(stateOverrides),
    analysis: createAnalysis(analysisOverrides),
    strategy: createStrategy(strategyOverrides),
    ...rest,
  };
}

// ===== Tests =====

describe("Update Status", () => {
  describe("Status File Creation", () => {
    test("creates status file at specified path", async () => {
      const statusPath = join(TEST_DIR, ".claude", "RALPH_STATUS_1.md");
      const input = createStatusInput();

      await runStatusUpdater(statusPath, input);

      expect(existsSync(statusPath)).toBe(true);
    });

    test("creates markdown with header", async () => {
      const statusPath = join(TEST_DIR, ".claude", "RALPH_STATUS_2.md");
      const input = createStatusInput();

      await runStatusUpdater(statusPath, input);

      const content = readFileSync(statusPath, "utf-8");
      expect(content).toContain("# Ralph");
    });
  });

  describe("Status Values", () => {
    test("shows RUNNING status by default", async () => {
      const statusPath = join(TEST_DIR, ".claude", "status_running.md");
      const input = createStatusInput();

      await runStatusUpdater(statusPath, input);

      const content = readFileSync(statusPath, "utf-8");
      expect(content).toContain("RUNNING");
    });

    test("includes status emoji", async () => {
      const statusPath = join(TEST_DIR, ".claude", "status_emoji.md");
      const input = createStatusInput();

      await runStatusUpdater(statusPath, input);

      const content = readFileSync(statusPath, "utf-8");
      // Should contain the running emoji
      expect(content).toContain("🔄");
    });
  });

  describe("Iteration Info", () => {
    test("shows current iteration", async () => {
      const statusPath = join(TEST_DIR, ".claude", "status_iter.md");
      const input = createStatusInput({ state: { iteration: 15 } });

      await runStatusUpdater(statusPath, input);

      const content = readFileSync(statusPath, "utf-8");
      expect(content).toContain("15");
    });

    test("shows max iterations", async () => {
      const statusPath = join(TEST_DIR, ".claude", "status_max.md");
      const input = createStatusInput({ state: { max_iterations: 100 } });

      await runStatusUpdater(statusPath, input);

      const content = readFileSync(statusPath, "utf-8");
      expect(content).toContain("100");
    });
  });

  describe("Strategy Display", () => {
    test("shows current strategy phase", async () => {
      const statusPath = join(TEST_DIR, ".claude", "status_strategy.md");
      const input = createStatusInput({ strategy: { strategy: "cleanup" } });

      await runStatusUpdater(statusPath, input);

      const content = readFileSync(statusPath, "utf-8");
      expect(content.toLowerCase()).toContain("cleanup");
    });
  });

  describe("Error Tracking", () => {
    test("shows error count", async () => {
      const statusPath = join(TEST_DIR, ".claude", "status_errors.md");
      const input = createStatusInput({
        analysis: {
          errors: [
            { pattern: "Error 1", sample: "sample" },
            { pattern: "Error 2", sample: "sample" },
          ],
        },
      });

      await runStatusUpdater(statusPath, input);

      const content = readFileSync(statusPath, "utf-8");
      expect(content).toContain("2");
    });

    test("shows zero errors when none", async () => {
      const statusPath = join(TEST_DIR, ".claude", "status_no_errors.md");
      const input = createStatusInput({ analysis: { errors: [] } });

      await runStatusUpdater(statusPath, input);

      const content = readFileSync(statusPath, "utf-8");
      // Should show 0 errors somewhere
      expect(content).toMatch(/error.*0|0.*error/i);
    });
  });

  describe("Files Modified", () => {
    test("shows modified files", async () => {
      const statusPath = join(TEST_DIR, ".claude", "status_files.md");
      const input = createStatusInput({
        analysis: {
          files_modified: ["/src/index.ts", "/src/utils.ts"],
        },
      });

      await runStatusUpdater(statusPath, input);

      const content = readFileSync(statusPath, "utf-8");
      expect(content).toContain("index.ts");
    });
  });

  describe("Timestamp", () => {
    test("includes last updated timestamp", async () => {
      const statusPath = join(TEST_DIR, ".claude", "status_time.md");
      const input = createStatusInput();

      await runStatusUpdater(statusPath, input);

      const content = readFileSync(statusPath, "utf-8");
      // Should contain some timestamp format
      expect(content).toMatch(/\d{2}:\d{2}/);
    });
  });

  describe("Error Handling", () => {
    test("exits with error when no path provided", async () => {
      const proc = Bun.spawn(["bun", "run", "update-status.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify(createStatusInput()));
      proc.stdin.end();

      const exitCode = await proc.exited;
      expect(exitCode).not.toBe(0);
    });
  });
});
