/**
 * Tests for parse-json-output.ts
 *
 * Tests parsing of Claude's JSON output format:
 * - Token metrics extraction
 * - Response text extraction
 * - Session ID and cost extraction
 * - Error handling for malformed input
 */

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { writeFileSync, unlinkSync, mkdirSync, rmdirSync } from "fs";
import { join } from "path";
import type { ParsedJsonOutput } from "../types";

const TEST_DIR = "/tmp/ralph-parse-tests";
const SCRIPT_DIR = "/mnt/c/Users/Karim/Documents/work/_tools/AI/R&D/ralphwiggum/repo/scripts";

// ===== Test Fixtures =====

function createClaudeResponse(overrides: any = {}): any {
  return {
    type: "result",
    subtype: "success",
    is_error: false,
    duration_ms: 5000,
    duration_api_ms: 4500,
    num_turns: 1,
    result: "Hello, I'm Claude!",
    session_id: "test-session-123",
    total_cost_usd: 0.05,
    usage: {
      input_tokens: 1000,
      output_tokens: 500,
    },
    ...overrides,
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
    const files = require("fs").readdirSync(TEST_DIR);
    for (const file of files) {
      unlinkSync(join(TEST_DIR, file));
    }
    rmdirSync(TEST_DIR);
  } catch {
    // Cleanup might fail
  }
});

// ===== Helper to run parser =====

async function runParser(input: string): Promise<ParsedJsonOutput> {
  const proc = Bun.spawn(["bun", "run", "parse-json-output.ts"], {
    cwd: SCRIPT_DIR,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });

  proc.stdin.write(input);
  proc.stdin.end();

  const output = await new Response(proc.stdout).text();
  return JSON.parse(output);
}

async function runParserFromFile(filePath: string): Promise<ParsedJsonOutput> {
  const proc = Bun.spawn(["bun", "run", "parse-json-output.ts", filePath], {
    cwd: SCRIPT_DIR,
    stdout: "pipe",
    stderr: "pipe",
  });

  const output = await new Response(proc.stdout).text();
  return JSON.parse(output);
}

// ===== Tests =====

describe("Parse JSON Output", () => {
  describe("Basic Parsing", () => {
    test("extracts result text", async () => {
      const response = createClaudeResponse({ result: "Hello World!" });
      const result = await runParser(JSON.stringify(response));

      expect(result.text).toBe("Hello World!");
    });

    test("extracts session ID", async () => {
      const response = createClaudeResponse({ session_id: "my-session-456" });
      const result = await runParser(JSON.stringify(response));

      expect(result.session_id).toBe("my-session-456");
    });

    test("extracts duration", async () => {
      const response = createClaudeResponse({ duration_ms: 3500 });
      const result = await runParser(JSON.stringify(response));

      expect(result.duration_ms).toBe(3500);
    });

    test("extracts cost", async () => {
      const response = createClaudeResponse({ total_cost_usd: 0.123 });
      const result = await runParser(JSON.stringify(response));

      expect(result.cost_usd).toBe(0.123);
    });
  });

  describe("Token Metrics from usage field", () => {
    test("extracts input and output tokens", async () => {
      const response = createClaudeResponse({
        usage: {
          input_tokens: 2000,
          output_tokens: 800,
        },
      });
      const result = await runParser(JSON.stringify(response));

      expect(result.tokens.input_tokens).toBe(2000);
      expect(result.tokens.output_tokens).toBe(800);
      expect(result.tokens.total_tokens).toBe(2800);
    });

    test("includes cache tokens in input count", async () => {
      const response = createClaudeResponse({
        usage: {
          input_tokens: 1000,
          output_tokens: 500,
          cache_creation_input_tokens: 200,
          cache_read_input_tokens: 300,
        },
      });
      const result = await runParser(JSON.stringify(response));

      // Input should be: 1000 + 200 + 300 = 1500
      expect(result.tokens.input_tokens).toBe(1500);
      expect(result.tokens.total_tokens).toBe(2000); // 1500 + 500
    });

    test("handles missing usage gracefully", async () => {
      const response = createClaudeResponse();
      delete response.usage;

      const result = await runParser(JSON.stringify(response));

      expect(result.tokens.input_tokens).toBe(0);
      expect(result.tokens.output_tokens).toBe(0);
    });
  });

  describe("Token Metrics from modelUsage field", () => {
    test("extracts tokens from modelUsage", async () => {
      const response = createClaudeResponse({
        usage: undefined,
        modelUsage: {
          "claude-3-opus-20240229": {
            inputTokens: 5000,
            outputTokens: 2000,
            contextWindow: 200000,
            costUSD: 0.10,
          },
        },
      });
      const result = await runParser(JSON.stringify(response));

      expect(result.tokens.input_tokens).toBe(5000);
      expect(result.tokens.output_tokens).toBe(2000);
      expect(result.tokens.context_window).toBe(200000);
    });

    test("modelUsage overrides usage when higher", async () => {
      const response = createClaudeResponse({
        usage: {
          input_tokens: 100,
          output_tokens: 50,
        },
        modelUsage: {
          "claude-3-opus-20240229": {
            inputTokens: 5000,
            outputTokens: 2000,
            contextWindow: 200000,
            costUSD: 0.10,
          },
        },
      });
      const result = await runParser(JSON.stringify(response));

      // modelUsage values are higher, should use those
      expect(result.tokens.input_tokens).toBe(5000);
      expect(result.tokens.output_tokens).toBe(2000);
    });

    test("sums across multiple models", async () => {
      const response = createClaudeResponse({
        usage: undefined,
        modelUsage: {
          "claude-3-opus-20240229": {
            inputTokens: 3000,
            outputTokens: 1000,
            contextWindow: 200000,
            costUSD: 0.05,
          },
          "claude-3-haiku-20240307": {
            inputTokens: 500,
            outputTokens: 200,
            contextWindow: 200000,
            costUSD: 0.01,
          },
        },
      });
      const result = await runParser(JSON.stringify(response));

      expect(result.tokens.input_tokens).toBe(3500); // 3000 + 500
      expect(result.tokens.output_tokens).toBe(1200); // 1000 + 200
    });

    test("extracts context window from modelUsage", async () => {
      const response = createClaudeResponse({
        modelUsage: {
          "claude-3-haiku-20240307": {
            inputTokens: 100,
            outputTokens: 50,
            contextWindow: 100000,
            costUSD: 0.001,
          },
        },
      });
      const result = await runParser(JSON.stringify(response));

      expect(result.tokens.context_window).toBe(100000);
    });
  });

  describe("Context Percentage Calculation", () => {
    test("calculates context percentage correctly", async () => {
      const response = createClaudeResponse({
        usage: {
          input_tokens: 40000,
          output_tokens: 10000,
        },
        modelUsage: {
          "claude-3-opus": {
            inputTokens: 40000,
            outputTokens: 10000,
            contextWindow: 200000,
            costUSD: 0.1,
          },
        },
      });
      const result = await runParser(JSON.stringify(response));

      // 50000 / 200000 = 0.25 = 25%
      expect(result.tokens.context_pct).toBe(25);
    });

    test("handles zero context window", async () => {
      const response = createClaudeResponse({
        modelUsage: {
          model: {
            inputTokens: 100,
            outputTokens: 50,
            contextWindow: 0,
            costUSD: 0,
          },
        },
      });
      // Delete default usage to test edge case
      delete response.usage;

      const result = await runParser(JSON.stringify(response));

      // contextWindow 0 should use default 200000
      expect(result.tokens.context_pct).toBeLessThan(1);
    });

    test("uses 2 decimal places for percentage", async () => {
      const response = createClaudeResponse({
        usage: {
          input_tokens: 12345,
          output_tokens: 6789,
        },
      });
      const result = await runParser(JSON.stringify(response));

      // Should be a number with at most 2 decimal places
      const decimals = (result.tokens.context_pct.toString().split(".")[1] || "").length;
      expect(decimals).toBeLessThanOrEqual(2);
    });
  });

  describe("Error Handling", () => {
    test("returns raw input as text for invalid JSON", async () => {
      const result = await runParser("not valid json");

      expect(result.text).toBe("not valid json");
      expect(result.tokens.input_tokens).toBe(0);
    });

    test("handles empty result field", async () => {
      const response = createClaudeResponse({ result: "" });
      const result = await runParser(JSON.stringify(response));

      expect(result.text).toBe("");
    });

    test("handles missing fields with defaults", async () => {
      const response = {};
      const result = await runParser(JSON.stringify(response));

      expect(result.text).toBe("");
      expect(result.session_id).toBe("");
      expect(result.duration_ms).toBe(0);
      expect(result.cost_usd).toBe(0);
    });
  });

  describe("File Input Mode", () => {
    test("reads from file when path provided", async () => {
      const response = createClaudeResponse({ result: "From file!" });
      const filePath = join(TEST_DIR, "response.json");
      writeFileSync(filePath, JSON.stringify(response));

      const result = await runParserFromFile(filePath);

      expect(result.text).toBe("From file!");
    });
  });

  describe("Default Values", () => {
    test("uses 200000 as default context window", async () => {
      const response = createClaudeResponse();
      delete response.modelUsage;

      const result = await runParser(JSON.stringify(response));

      expect(result.tokens.context_window).toBe(200000);
    });
  });
});
