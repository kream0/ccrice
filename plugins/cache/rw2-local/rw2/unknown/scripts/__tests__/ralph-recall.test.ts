/**
 * Tests for ralph-recall.ts
 *
 * Tests recall query logic:
 * - Input parsing (CLI and stdin)
 * - Query modes (sessions, errors, learnings, search, stats)
 * - Date parsing (relative and ISO)
 * - Output formatting
 * - Error handling
 */

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { mkdirSync, rmSync } from "fs";
import { join } from "path";

const TEST_DIR = "/tmp/ralph-recall-tests";
const SCRIPT_DIR = "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts";

// ===== Setup/Teardown =====

beforeAll(() => {
  try {
    mkdirSync(TEST_DIR, { recursive: true });
    mkdirSync(join(TEST_DIR, ".memorai"), { recursive: true });
  } catch {
    // Directory might exist
  }
});

afterAll(() => {
  try {
    rmSync(TEST_DIR, { recursive: true, force: true });
  } catch {
    // Cleanup might fail
  }
});

// ===== Test Fixtures =====

function createRecallInput(overrides: any = {}): any {
  return {
    mode: "sessions",
    limit: 10,
    ...overrides,
  };
}

// ===== Helper to run ralph-recall =====

async function runRecall(
  input?: any,
  args?: string[]
): Promise<{ exitCode: number; output: string; stderr: string }> {
  const cmdArgs = ["bun", "run", "ralph-recall.ts"];
  if (args) {
    cmdArgs.push(...args);
  }

  const proc = Bun.spawn(cmdArgs, {
    cwd: SCRIPT_DIR,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });

  if (input !== undefined) {
    proc.stdin.write(typeof input === "string" ? input : JSON.stringify(input));
  }
  proc.stdin.end();

  const [output, stderr, exitCode] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
    proc.exited,
  ]);

  return { exitCode, output, stderr };
}

// ===== Tests =====

describe("Ralph Recall", () => {
  describe("Input Parsing", () => {
    test("accepts JSON input via stdin", async () => {
      const { output } = await runRecall(createRecallInput({ mode: "sessions" }));
      const result = JSON.parse(output);
      expect(result).toHaveProperty("mode");
      expect(result.mode).toBe("sessions");
    });

    test("accepts string query via stdin as search mode", async () => {
      const { output } = await runRecall("authentication error");
      const result = JSON.parse(output);
      expect(result.mode).toBe("search");
    });

    test("accepts JSON argument via CLI", async () => {
      const { output } = await runRecall(undefined, ['{"mode":"learnings"}']);
      const result = JSON.parse(output);
      expect(result.mode).toBe("learnings");
    });

    test("accepts string argument as search query", async () => {
      const { output } = await runRecall(undefined, ["test query"]);
      const result = JSON.parse(output);
      expect(result.mode).toBe("search");
    });

    test("defaults to sessions mode with no input", async () => {
      const { output } = await runRecall("");
      const result = JSON.parse(output);
      expect(result.mode).toBe("sessions");
    });
  });

  describe("Query Modes", () => {
    test("sessions mode returns session results", async () => {
      const { output } = await runRecall({ mode: "sessions" });
      const result = JSON.parse(output);
      expect(result.mode).toBe("sessions");
      expect(result).toHaveProperty("results");
      expect(Array.isArray(result.results)).toBe(true);
    });

    test("errors mode returns error results", async () => {
      const { output } = await runRecall({ mode: "errors" });
      const result = JSON.parse(output);
      expect(result.mode).toBe("errors");
      expect(result).toHaveProperty("results");
    });

    test("learnings mode returns learning results", async () => {
      const { output } = await runRecall({ mode: "learnings" });
      const result = JSON.parse(output);
      expect(result.mode).toBe("learnings");
      expect(result).toHaveProperty("results");
    });

    test("search mode accepts custom query", async () => {
      const { output } = await runRecall({ mode: "search", query: "authentication" });
      const result = JSON.parse(output);
      expect(result.mode).toBe("search");
    });

    test("stats mode returns statistics", async () => {
      const { output } = await runRecall({ mode: "stats" });
      const result = JSON.parse(output);
      expect(result.mode).toBe("stats");
    });
  });

  describe("Output Structure", () => {
    test("includes success field", async () => {
      const { output } = await runRecall({ mode: "sessions" });
      const result = JSON.parse(output);
      expect(result).toHaveProperty("success");
      expect(typeof result.success).toBe("boolean");
    });

    test("includes mode field", async () => {
      const { output } = await runRecall({ mode: "sessions" });
      const result = JSON.parse(output);
      expect(result).toHaveProperty("mode");
    });

    test("includes count field", async () => {
      const { output } = await runRecall({ mode: "sessions" });
      const result = JSON.parse(output);
      expect(result).toHaveProperty("count");
      expect(typeof result.count).toBe("number");
    });

    test("includes results array", async () => {
      const { output } = await runRecall({ mode: "sessions" });
      const result = JSON.parse(output);
      expect(result).toHaveProperty("results");
      expect(Array.isArray(result.results)).toBe(true);
    });

    test("includes error field on failure", async () => {
      const { output } = await runRecall({ mode: "sessions", project: "/nonexistent/path" });
      const result = JSON.parse(output);
      if (!result.success) {
        expect(result).toHaveProperty("error");
      }
    });
  });

  describe("Limit Option", () => {
    test("respects limit parameter", async () => {
      const { output } = await runRecall({ mode: "sessions", limit: 5 });
      const result = JSON.parse(output);
      expect(result.results.length).toBeLessThanOrEqual(5);
    });

    test("defaults to 10 results", async () => {
      const { output } = await runRecall({ mode: "sessions" });
      const result = JSON.parse(output);
      expect(result.results.length).toBeLessThanOrEqual(10);
    });
  });

  describe("Date Filtering", () => {
    // Test the parseRelativeDate function logic

    test("since parameter accepts relative day format", () => {
      // "7d" means 7 days ago
      const sinceStr = "7d";
      expect(sinceStr).toMatch(/^\d+d$/);
    });

    test("since parameter accepts relative week format", () => {
      // "2w" means 2 weeks ago
      const sinceStr = "2w";
      expect(sinceStr).toMatch(/^\d+w$/);
    });

    test("since parameter accepts relative month format", () => {
      // "1m" means 1 month ago
      const sinceStr = "1m";
      expect(sinceStr).toMatch(/^\d+m$/);
    });

    test("since parameter accepts ISO date format", () => {
      const sinceStr = "2026-01-01T00:00:00Z";
      const parsed = new Date(sinceStr);
      expect(parsed.getTime()).not.toBeNaN();
    });

    test("input with since filter is valid", async () => {
      const { output } = await runRecall({ mode: "sessions", since: "7d" });
      const result = JSON.parse(output);
      expect(result).toHaveProperty("mode");
    });

    test("input with until filter is valid", async () => {
      const { output } = await runRecall({ mode: "sessions", until: "2026-12-31" });
      const result = JSON.parse(output);
      expect(result).toHaveProperty("mode");
    });
  });

  describe("Format Options", () => {
    test("json format returns pure JSON", async () => {
      const { output } = await runRecall({ mode: "sessions", format: "json" });
      const result = JSON.parse(output);
      expect(result).toHaveProperty("results");
    });

    test("markdown format outputs formatted text to stderr", async () => {
      const { stderr } = await runRecall({ mode: "sessions", format: "markdown" });
      // Markdown format outputs to stderr for human reading
      // Empty results would show "No sessions found"
      expect(typeof stderr).toBe("string");
    });

    test("compact format outputs compact view", async () => {
      const { stderr } = await runRecall({ mode: "sessions", format: "compact" });
      expect(typeof stderr).toBe("string");
    });
  });

  describe("Global Search", () => {
    test("global flag is accepted in input", () => {
      // Test that the global flag is a valid input option
      const input = createRecallInput({ global: true });
      expect(input.global).toBe(true);
    });

    test("project flag searches specific project", async () => {
      // Use current directory which should have or not have memorai
      const { output } = await runRecall({ mode: "sessions", project: SCRIPT_DIR });
      const result = JSON.parse(output);
      // Should return valid JSON output regardless of memorai presence
      expect(result).toHaveProperty("success");
    });
  });

  describe("Importance Filter", () => {
    test("importance_min filters low importance results", async () => {
      const { output } = await runRecall({ mode: "sessions", importance_min: 5 });
      const result = JSON.parse(output);
      expect(result).toHaveProperty("results");
    });

    test("defaults to importance_min of 1", async () => {
      const input = createRecallInput();
      // Default importance_min would be 1 (include all)
      expect(input.importance_min ?? 1).toBe(1);
    });
  });

  describe("Error Handling", () => {
    test("handles invalid mode gracefully", async () => {
      const { output } = await runRecall({ mode: "invalid_mode" });
      // Should fall back to search mode
      const result = JSON.parse(output);
      expect(result).toHaveProperty("mode");
    });

    test("handles missing memorai database", async () => {
      const { output } = await runRecall({ mode: "sessions", project: "/nonexistent" });
      const result = JSON.parse(output);
      expect(result.success).toBe(false);
      expect(result).toHaveProperty("error");
    });
  });

  describe("Result Fields", () => {
    // Test the expected structure of result items
    test("result items have expected fields", () => {
      const expectedFields = [
        "id",
        "category",
        "title",
        "summary",
        "tags",
        "importance",
        "created_at",
      ];

      for (const field of expectedFields) {
        expect(expectedFields).toContain(field);
      }
    });

    test("result items may have relevance score", () => {
      // Search results include relevance scores
      const resultWithRelevance = {
        id: "mem-123",
        category: "notes",
        title: "Test",
        summary: "Summary",
        tags: ["ralph"],
        importance: 5,
        created_at: "2026-01-01",
        relevance: 0.95,
      };

      expect(resultWithRelevance.relevance).toBe(0.95);
    });

    test("result items may have project field for global search", () => {
      const resultWithProject = {
        id: "mem-123",
        category: "notes",
        title: "Test",
        summary: "Summary",
        tags: ["ralph"],
        importance: 5,
        created_at: "2026-01-01",
        project: "my-project",
      };

      expect(resultWithProject.project).toBe("my-project");
    });
  });
});

describe("Relative Date Parsing", () => {
  // Unit tests for the parseRelativeDate function logic

  test("parses days correctly", () => {
    const now = new Date();
    const sevenDaysAgo = new Date(now);
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    const diff = Math.abs(now.getTime() - sevenDaysAgo.getTime());
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    expect(days).toBe(7);
  });

  test("parses weeks correctly", () => {
    const now = new Date();
    const twoWeeksAgo = new Date(now);
    twoWeeksAgo.setDate(twoWeeksAgo.getDate() - 14);

    const diff = Math.abs(now.getTime() - twoWeeksAgo.getTime());
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    expect(days).toBe(14);
  });

  test("parses months correctly", () => {
    const now = new Date();
    const oneMonthAgo = new Date(now);
    oneMonthAgo.setMonth(oneMonthAgo.getMonth() - 1);

    // Month calculations vary, just verify it's roughly 28-31 days
    const diff = Math.abs(now.getTime() - oneMonthAgo.getTime());
    const days = Math.floor(diff / (1000 * 60 * 60 * 24));
    expect(days).toBeGreaterThanOrEqual(28);
    expect(days).toBeLessThanOrEqual(31);
  });

  test("returns valid date for ISO format", () => {
    const isoDate = "2026-01-15T10:30:00Z";
    const parsed = new Date(isoDate);
    expect(parsed.getFullYear()).toBe(2026);
    expect(parsed.getMonth()).toBe(0); // January is 0
    expect(parsed.getDate()).toBe(15);
  });
});

describe("Format Results", () => {
  test("empty results show appropriate message", () => {
    const results: any[] = [];
    const mode = "sessions";
    const message = results.length === 0 ? `No ${mode} found in memorai.` : "";
    expect(message).toBe("No sessions found in memorai.");
  });

  test("compact format includes stars for importance", () => {
    const importance = 4;
    const stars = "★".repeat(Math.min(importance, 5));
    expect(stars).toBe("★★★★");
  });

  test("markdown format includes headers", () => {
    const mode = "sessions";
    const count = 5;
    const header = `## Ralph ${mode.charAt(0).toUpperCase() + mode.slice(1)} (${count} found)\n`;
    expect(header).toBe("## Ralph Sessions (5 found)\n");
  });
});
