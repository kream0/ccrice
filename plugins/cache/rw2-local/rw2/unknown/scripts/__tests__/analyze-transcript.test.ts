/**
 * Tests for analyze-transcript.ts
 *
 * Tests the transcript analysis logic:
 * - Error pattern detection
 * - Repeated error counting
 * - File modification tracking
 * - Test execution status detection
 * - Phase completion detection
 * - Meaningful changes detection
 */

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { writeFileSync, unlinkSync, mkdirSync, rmdirSync } from "fs";
import { join } from "path";
import type { TranscriptAnalysis } from "../types";

const TEST_DIR = "/tmp/ralph-analyze-tests";
const SCRIPT_DIR = "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts";

// ===== Test Fixtures =====

function createTranscriptFile(name: string, messages: any[]): string {
  const path = join(TEST_DIR, name);
  const content = messages.map((m) => JSON.stringify(m)).join("\n");
  writeFileSync(path, content);
  return path;
}

function createMessage(role: "user" | "assistant" | "system", text: string): any {
  return {
    role,
    message: {
      content: [{ type: "text", text }],
    },
  };
}

function createToolMessage(role: "assistant", text: string, toolUse: any): any {
  return {
    role,
    message: {
      content: [
        { type: "text", text },
        { type: "tool_use", tool_use: toolUse },
      ],
    },
  };
}

// ===== Setup/Teardown =====

beforeAll(() => {
  try {
    mkdirSync(TEST_DIR, { recursive: true });
  } catch {
    // Directory might already exist
  }
});

afterAll(() => {
  try {
    // Clean up test files
    const files = require("fs").readdirSync(TEST_DIR);
    for (const file of files) {
      unlinkSync(join(TEST_DIR, file));
    }
    rmdirSync(TEST_DIR);
  } catch {
    // Cleanup might fail, ignore
  }
});

// ===== Helper to run analyzer =====

async function runAnalyzer(transcriptPath: string): Promise<TranscriptAnalysis> {
  const proc = Bun.spawn(["bun", "run", "analyze-transcript.ts", transcriptPath], {
    cwd: SCRIPT_DIR,
    stdout: "pipe",
    stderr: "pipe",
  });

  const output = await new Response(proc.stdout).text();
  return JSON.parse(output);
}

// ===== Tests =====

describe("Analyze Transcript", () => {
  describe("Error Pattern Detection", () => {
    test("detects TypeScript compilation errors", async () => {
      const path = createTranscriptFile("ts-error.jsonl", [
        createMessage("assistant", "I see an error: error TS2304: Cannot find name 'foo'"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.errors.some((e) => e.pattern === "TypeScript compilation error")).toBe(true);
    });

    test("detects JavaScript syntax errors", async () => {
      const path = createTranscriptFile("syntax-error.jsonl", [
        createMessage("assistant", "Error: SyntaxError: Unexpected token"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.errors.some((e) => e.pattern === "JavaScript syntax error")).toBe(true);
    });

    test("detects test failures", async () => {
      const path = createTranscriptFile("test-failure.jsonl", [
        createMessage("assistant", "FAILED tests/auth.test.ts"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.errors.some((e) => e.pattern === "Test failure")).toBe(true);
    });

    test("detects timeout errors", async () => {
      const path = createTranscriptFile("timeout.jsonl", [
        createMessage("assistant", "The request timed out after 30s"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.errors.some((e) => e.pattern === "Timeout error")).toBe(true);
    });

    test("detects file not found errors", async () => {
      const path = createTranscriptFile("enoent.jsonl", [
        createMessage("assistant", "Error: ENOENT: no such file or directory"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.errors.some((e) => e.pattern === "File not found")).toBe(true);
    });

    test("detects module resolution errors", async () => {
      const path = createTranscriptFile("module-error.jsonl", [
        createMessage("assistant", "Cannot find module 'lodash'"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.errors.some((e) => e.pattern === "Module resolution error")).toBe(true);
    });

    test("returns empty array for clean transcript", async () => {
      const path = createTranscriptFile("clean.jsonl", [
        createMessage("assistant", "Everything is working perfectly!"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.errors).toEqual([]);
    });

    test("includes sample in error entry", async () => {
      const path = createTranscriptFile("sample.jsonl", [
        createMessage("assistant", "Build failed with error TS2345: Argument is wrong"),
      ]);

      const result = await runAnalyzer(path);

      const tsError = result.errors.find((e) => e.pattern === "TypeScript compilation error");
      expect(tsError).toBeDefined();
      expect(tsError?.sample).toContain("TS2345");
    });
  });

  describe("Repeated Error Counting", () => {
    test("counts repeated errors correctly", async () => {
      const path = createTranscriptFile("repeated.jsonl", [
        createMessage("assistant", "error TS2304: foo"),
        createMessage("assistant", "error TS2304: bar"),
        createMessage("assistant", "error TS2304: baz"),
      ]);

      const result = await runAnalyzer(path);

      const repeated = result.repeated_errors.find(
        (e) => e.pattern === "TypeScript compilation error"
      );
      expect(repeated).toBeDefined();
      expect(repeated?.count).toBe(3);
    });

    test("only includes errors with 2+ occurrences", async () => {
      const path = createTranscriptFile("single-error.jsonl", [
        createMessage("assistant", "error TS2304: single error"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.repeated_errors).toEqual([]);
    });

    test("sorts repeated errors by count descending", async () => {
      const path = createTranscriptFile("multi-error.jsonl", [
        createMessage("assistant", "SyntaxError: x"),
        createMessage("assistant", "SyntaxError: y"),
        createMessage("assistant", "error TS2304: a"),
        createMessage("assistant", "error TS2304: b"),
        createMessage("assistant", "error TS2304: c"),
        createMessage("assistant", "error TS2304: d"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.repeated_errors.length).toBe(2);
      expect(result.repeated_errors[0].count).toBeGreaterThanOrEqual(
        result.repeated_errors[1].count
      );
    });
  });

  describe("File Modification Tracking", () => {
    test("detects files from tool calls", async () => {
      const path = createTranscriptFile("tool-files.jsonl", [
        createToolMessage("assistant", "Writing file", {
          tool: "Write",
          file_path: "/src/index.ts",
        }),
      ]);

      const result = await runAnalyzer(path);

      expect(result.files_modified).toContain("/src/index.ts");
    });

    test("detects files from text mentions", async () => {
      const path = createTranscriptFile("text-files.jsonl", [
        createMessage("assistant", 'Created file `/src/utils.ts`'),
      ]);

      const result = await runAnalyzer(path);

      expect(result.files_modified).toContain("/src/utils.ts");
    });

    test("deduplicates file paths", async () => {
      const path = createTranscriptFile("dup-files.jsonl", [
        createMessage("assistant", 'Modified `/src/app.ts`'),
        createMessage("assistant", 'Updated `/src/app.ts`'),
      ]);

      const result = await runAnalyzer(path);

      const appCount = result.files_modified.filter((f) => f === "/src/app.ts").length;
      expect(appCount).toBe(1);
    });

    test("returns empty for no file modifications", async () => {
      const path = createTranscriptFile("no-files.jsonl", [
        createMessage("assistant", "Just thinking about the problem..."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.files_modified).toEqual([]);
    });
  });

  describe("Test Execution Status", () => {
    test("detects npm test execution", async () => {
      const path = createTranscriptFile("npm-test.jsonl", [
        createMessage("assistant", "Running npm test..."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.tests_run).toBe(true);
    });

    test("detects bun test execution", async () => {
      const path = createTranscriptFile("bun-test.jsonl", [
        createMessage("assistant", "Running bun test..."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.tests_run).toBe(true);
    });

    test("detects pytest execution", async () => {
      const path = createTranscriptFile("pytest.jsonl", [
        createMessage("assistant", "Running pytest..."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.tests_run).toBe(true);
    });

    test("detects test pass", async () => {
      const path = createTranscriptFile("test-pass.jsonl", [
        createMessage("assistant", "All tests passed! 15 tests passed"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.tests_passed).toBe(true);
    });

    test("detects test fail", async () => {
      const path = createTranscriptFile("test-fail.jsonl", [
        createMessage("assistant", "Tests failed: 3 failed, 10 passed"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.tests_failed).toBe(true);
    });

    test("returns false for all when no tests", async () => {
      const path = createTranscriptFile("no-tests.jsonl", [
        createMessage("assistant", "Just writing some code..."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.tests_run).toBe(false);
      expect(result.tests_passed).toBe(false);
      expect(result.tests_failed).toBe(false);
    });
  });

  describe("Phase Completion Detection", () => {
    test("detects phase 1 completion", async () => {
      const path = createTranscriptFile("phase1.jsonl", [
        createMessage("assistant", "Phase 1 complete! Moving to phase 2."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.phase_completions).toContain("phase-1");
    });

    test("detects tests passing phase", async () => {
      const path = createTranscriptFile("tests-pass.jsonl", [
        createMessage("assistant", "Tests passed! All 25 tests passing now."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.phase_completions).toContain("tests-passing");
    });

    test("detects implementation complete", async () => {
      const path = createTranscriptFile("impl-done.jsonl", [
        createMessage("assistant", "Implementation complete. All features working."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.phase_completions).toContain("implementation");
    });

    test("detects setup complete", async () => {
      const path = createTranscriptFile("setup-done.jsonl", [
        createMessage("assistant", "Setup done! Ready to start coding."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.phase_completions).toContain("setup");
    });

    test("only checks assistant messages", async () => {
      const path = createTranscriptFile("user-phase.jsonl", [
        createMessage("user", "Phase 1 complete"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.phase_completions).not.toContain("phase-1");
    });

    test("returns empty for no phases", async () => {
      const path = createTranscriptFile("no-phases.jsonl", [
        createMessage("assistant", "Working on the task..."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.phase_completions).toEqual([]);
    });
  });

  describe("Meaningful Changes Detection", () => {
    test("true when files are modified", async () => {
      const path = createTranscriptFile("meaningful-files.jsonl", [
        createMessage("assistant", 'Created `/src/new.ts`'),
      ]);

      const result = await runAnalyzer(path);

      expect(result.meaningful_changes).toBe(true);
    });

    test("true when tests are run", async () => {
      const path = createTranscriptFile("meaningful-tests.jsonl", [
        createMessage("assistant", "Running npm test"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.meaningful_changes).toBe(true);
    });

    test("true when phases complete", async () => {
      const path = createTranscriptFile("meaningful-phase.jsonl", [
        createMessage("assistant", "Phase 1 complete"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.meaningful_changes).toBe(true);
    });

    test("true for substantive output (>500 chars)", async () => {
      const longText = "Here is a detailed analysis: " + "x".repeat(500);
      const path = createTranscriptFile("meaningful-long.jsonl", [
        createMessage("assistant", longText),
      ]);

      const result = await runAnalyzer(path);

      expect(result.meaningful_changes).toBe(true);
    });

    test("true for output with code blocks", async () => {
      const path = createTranscriptFile("meaningful-code.jsonl", [
        createMessage("assistant", "Here's the code:\n```typescript\nconst x = 1;\n```"),
      ]);

      const result = await runAnalyzer(path);

      expect(result.meaningful_changes).toBe(true);
    });

    test("false for short non-meaningful output", async () => {
      const path = createTranscriptFile("not-meaningful.jsonl", [
        createMessage("assistant", "OK, let me think..."),
      ]);

      const result = await runAnalyzer(path);

      expect(result.meaningful_changes).toBe(false);
    });
  });

  describe("Transcript Parsing", () => {
    test("handles CRLF line endings", async () => {
      const path = join(TEST_DIR, "crlf.jsonl");
      const content = [
        JSON.stringify(createMessage("assistant", "Line 1")),
        JSON.stringify(createMessage("assistant", "Line 2")),
      ].join("\r\n");
      writeFileSync(path, content);

      const result = await runAnalyzer(path);

      // Should not throw and should process messages
      expect(result).toBeDefined();
      expect(result.meaningful_changes).toBe(false);
    });

    test("handles empty lines", async () => {
      const path = join(TEST_DIR, "empty-lines.jsonl");
      const content =
        JSON.stringify(createMessage("assistant", "Hello")) +
        "\n\n\n" +
        JSON.stringify(createMessage("assistant", "World"));
      writeFileSync(path, content);

      const result = await runAnalyzer(path);

      expect(result).toBeDefined();
    });

    test("skips malformed JSON lines", async () => {
      const path = join(TEST_DIR, "malformed.jsonl");
      const content =
        JSON.stringify(createMessage("assistant", "Valid")) +
        "\n{invalid json\n" +
        JSON.stringify(createMessage("assistant", "Also valid"));
      writeFileSync(path, content);

      const result = await runAnalyzer(path);

      expect(result).toBeDefined();
    });
  });

  describe("Error Handling", () => {
    test("exits with error for missing file", async () => {
      const proc = Bun.spawn(["bun", "run", "analyze-transcript.ts", "/nonexistent.jsonl"], {
        cwd: SCRIPT_DIR,
        stdout: "pipe",
        stderr: "pipe",
      });

      const exitCode = await proc.exited;
      expect(exitCode).not.toBe(0);
    });

    test("exits with error for missing argument", async () => {
      const proc = Bun.spawn(["bun", "run", "analyze-transcript.ts"], {
        cwd: SCRIPT_DIR,
        stdout: "pipe",
        stderr: "pipe",
      });

      const exitCode = await proc.exited;
      expect(exitCode).not.toBe(0);
    });
  });
});
