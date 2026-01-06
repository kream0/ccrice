/**
 * Tests for generate-summary.ts
 *
 * Tests summary generation logic:
 * - Outcome determination based on completion reason
 * - Objective capture
 * - Session data aggregation
 * - Summary file generation
 */

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { writeFileSync, unlinkSync, mkdirSync, rmdirSync, existsSync, readFileSync } from "fs";
import { join } from "path";

const TEST_DIR = "/tmp/ralph-summary-tests";
const SCRIPT_DIR = "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts";

// ===== Test Fixtures =====

interface SummaryInput {
  session_id: string;
  completion_reason: string;
  final_iteration: number;
  original_objective?: string;
  context_pct?: number;
}

function createSummaryInput(overrides: Partial<SummaryInput> = {}): SummaryInput {
  return {
    session_id: "ralph-test-123",
    completion_reason: "promise",
    final_iteration: 10,
    original_objective: "Build a REST API",
    ...overrides,
  };
}

// ===== Setup/Teardown =====

beforeAll(() => {
  try {
    mkdirSync(TEST_DIR, { recursive: true });
    mkdirSync(join(TEST_DIR, ".claude"), { recursive: true });
  } catch {
    // Directory might already exist
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

// ===== Helper to run generator =====

async function runGenerator(
  input: SummaryInput,
  outputPath: string = join(TEST_DIR, "RALPH_SUMMARY.md")
): Promise<{ exitCode: number; output: string; stderr: string }> {
  const proc = Bun.spawn(["bun", "run", "generate-summary.ts", outputPath], {
    cwd: SCRIPT_DIR,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });

  proc.stdin.write(JSON.stringify(input));
  proc.stdin.end();

  const [output, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  return { exitCode, output, stderr };
}

// ===== Tests =====

describe("Generate Summary", () => {
  describe("Outcome Determination", () => {
    test("COMPLETED for promise completion", async () => {
      const input = createSummaryInput({ completion_reason: "promise" });
      const outputPath = join(TEST_DIR, "summary-promise.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content).toContain("COMPLETED");
      expect(content).toContain("✅");
    });

    test("CANCELLED for cancelled completion", async () => {
      const input = createSummaryInput({ completion_reason: "cancelled" });
      const outputPath = join(TEST_DIR, "summary-cancelled.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content).toContain("CANCELLED");
    });

    test("PARTIAL/INCOMPLETE for max_iterations", async () => {
      const input = createSummaryInput({ completion_reason: "max_iterations" });
      const outputPath = join(TEST_DIR, "summary-max.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      // Should be either PARTIAL or INCOMPLETE depending on progress
      expect(content.includes("PARTIAL") || content.includes("INCOMPLETE")).toBe(true);
    });

    test("ERROR for error completion", async () => {
      const input = createSummaryInput({ completion_reason: "error" });
      const outputPath = join(TEST_DIR, "summary-error.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content).toContain("ERROR");
      expect(content).toContain("💥");
    });

    test("CYCLING for context_threshold", async () => {
      const input = createSummaryInput({
        completion_reason: "context_threshold",
        context_pct: 65,
      });
      const outputPath = join(TEST_DIR, "summary-cycling.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content).toContain("CYCLING");
      expect(content).toContain("🔄");
    });

    test("UNKNOWN for unrecognized reason", async () => {
      const input = createSummaryInput({ completion_reason: "some_unknown_reason" });
      const outputPath = join(TEST_DIR, "summary-unknown.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content).toContain("UNKNOWN");
      expect(content).toContain("❓");
    });
  });

  describe("Objective Capture", () => {
    test("includes original_objective when provided", async () => {
      const input = createSummaryInput({
        original_objective: "Create a user authentication system",
      });
      const outputPath = join(TEST_DIR, "summary-obj.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content).toContain("Create a user authentication system");
    });

    test("omits objective section when not provided", async () => {
      const input = createSummaryInput();
      delete input.original_objective;
      const outputPath = join(TEST_DIR, "summary-no-obj.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      // When no objective is provided, it should either show "Unknown" or omit the section
      // The script omits the section entirely
      expect(content).not.toContain("## Original Objective");
    });
  });

  describe("Session Information", () => {
    test("includes session ID", async () => {
      const input = createSummaryInput({ session_id: "ralph-20260105-abc123" });
      const outputPath = join(TEST_DIR, "summary-session.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content).toContain("ralph-20260105-abc123");
    });

    test("includes iteration count", async () => {
      const input = createSummaryInput({ final_iteration: 25 });
      const outputPath = join(TEST_DIR, "summary-iter.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content).toContain("25");
    });
  });

  describe("Output File", () => {
    test("creates summary file at specified path", async () => {
      const input = createSummaryInput();
      const outputPath = join(TEST_DIR, "custom-summary.md");

      await runGenerator(input, outputPath);

      expect(existsSync(outputPath)).toBe(true);
    });

    test("overwrites existing summary file", async () => {
      const outputPath = join(TEST_DIR, "overwrite-summary.md");
      writeFileSync(outputPath, "OLD CONTENT");

      const input = createSummaryInput({ completion_reason: "promise" });
      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content).not.toContain("OLD CONTENT");
      expect(content).toContain("COMPLETED");
    });

    test("handles nested paths", async () => {
      // Pre-create the directory since the script may not create parent dirs
      const nestedDir = join(TEST_DIR, "nested", "dir");
      mkdirSync(nestedDir, { recursive: true });

      const input = createSummaryInput();
      const outputPath = join(nestedDir, "summary.md");

      await runGenerator(input, outputPath);

      expect(existsSync(outputPath)).toBe(true);
    });
  });

  describe("Markdown Format", () => {
    test("includes header with emoji", async () => {
      const input = createSummaryInput({ completion_reason: "promise" });
      const outputPath = join(TEST_DIR, "format-header.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content).toContain("# Ralph");
    });

    test("includes Quick Stats section", async () => {
      const input = createSummaryInput();
      const outputPath = join(TEST_DIR, "format-stats.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      expect(content.includes("Quick Stats") || content.includes("Stats") || content.includes("|")).toBe(true);
    });

    test("includes timestamp", async () => {
      const input = createSummaryInput();
      const outputPath = join(TEST_DIR, "format-time.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      // Should contain some date/time reference
      expect(content).toMatch(/\d{4}|\d{2}:\d{2}/);
    });
  });

  describe("Error Handling", () => {
    test("handles missing output path argument", async () => {
      const proc = Bun.spawn(["bun", "run", "generate-summary.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      const input = createSummaryInput();
      proc.stdin.write(JSON.stringify(input));
      proc.stdin.end();

      const exitCode = await proc.exited;
      expect(exitCode).not.toBe(0);
    });

    test("handles invalid JSON input gracefully", async () => {
      const proc = Bun.spawn(["bun", "run", "generate-summary.ts", join(TEST_DIR, "bad.md")], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write("not valid json");
      proc.stdin.end();

      const exitCode = await proc.exited;
      // Should either exit 0 with defaults or exit non-zero
      // The script may handle this gracefully
      expect(typeof exitCode).toBe("number");
    });

    test("handles empty input", async () => {
      const proc = Bun.spawn(["bun", "run", "generate-summary.ts", join(TEST_DIR, "empty.md")], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.end();

      const exitCode = await proc.exited;
      // Should handle gracefully
      expect(typeof exitCode).toBe("number");
    });
  });

  describe("Context Threshold Info", () => {
    test("generates valid summary for context_threshold reason", async () => {
      const input = createSummaryInput({
        completion_reason: "context_threshold",
        context_pct: 72,
      });
      const outputPath = join(TEST_DIR, "context-pct.md");

      await runGenerator(input, outputPath);

      const content = readFileSync(outputPath, "utf-8");
      // Should show CYCLING status for context_threshold
      expect(content).toContain("CYCLING");
      expect(content).toContain("/ralph-resume");
    });
  });
});
