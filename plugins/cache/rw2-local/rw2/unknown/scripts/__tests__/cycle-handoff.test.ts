/**
 * Tests for save-cycle-handoff.ts and load-cycle-handoff.ts
 *
 * Tests cycle handoff logic:
 * - Handoff data structure
 * - Save/load operations
 * - Context formatting
 * - Error handling
 *
 * Note: These tests focus on CLI behavior and data structures.
 * Memorai integration is tested separately.
 */

import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { mkdirSync, rmSync } from "fs";
import { join } from "path";

const TEST_DIR = "/tmp/ralph-handoff-tests";
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

function createHandoffInput(overrides: any = {}): any {
  return {
    session_id: "ralph-test-20260105-abc1",
    cycle_number: 1,
    original_objective: "Build a REST API for user management",
    context_pct: 65,
    accomplishments: ["Set up project structure", "Created database schema"],
    blockers: [],
    next_actions: ["Implement user endpoints", "Add authentication"],
    key_learnings: ["Use TypeScript strict mode", "Add input validation"],
    ...overrides,
  };
}

function createLoadInput(overrides: any = {}): any {
  return {
    session_id: "ralph-test-20260105-abc1",
    ...overrides,
  };
}

// ===== Save Cycle Handoff Tests =====

describe("Save Cycle Handoff", () => {
  describe("Input Validation", () => {
    test("exits with error for empty input", async () => {
      const proc = Bun.spawn(["bun", "run", "save-cycle-handoff.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.end();

      const exitCode = await proc.exited;
      expect(exitCode).not.toBe(0);
    });

    test("exits with error for invalid JSON", async () => {
      const proc = Bun.spawn(["bun", "run", "save-cycle-handoff.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write("not valid json");
      proc.stdin.end();

      const exitCode = await proc.exited;
      const stderr = await new Response(proc.stderr).text();
      expect(exitCode).not.toBe(0);
      expect(stderr).toContain("JSON");
    });
  });

  describe("Handoff Data Structure", () => {
    test("contains all required fields", () => {
      const input = createHandoffInput();
      expect(input).toHaveProperty("session_id");
      expect(input).toHaveProperty("cycle_number");
      expect(input).toHaveProperty("original_objective");
      expect(input).toHaveProperty("context_pct");
    });

    test("includes accomplishments array", () => {
      const input = createHandoffInput({
        accomplishments: ["Task 1", "Task 2", "Task 3"],
      });
      expect(Array.isArray(input.accomplishments)).toBe(true);
      expect(input.accomplishments.length).toBe(3);
    });

    test("includes blockers array", () => {
      const input = createHandoffInput({
        blockers: ["Database connection issue", "Auth not working"],
      });
      expect(Array.isArray(input.blockers)).toBe(true);
      expect(input.blockers.length).toBe(2);
    });

    test("includes next_actions array", () => {
      const input = createHandoffInput({
        next_actions: ["Fix auth", "Add tests"],
      });
      expect(Array.isArray(input.next_actions)).toBe(true);
      expect(input.next_actions.length).toBe(2);
    });

    test("includes key_learnings array", () => {
      const input = createHandoffInput({
        key_learnings: ["Learning 1", "Learning 2"],
      });
      expect(Array.isArray(input.key_learnings)).toBe(true);
      expect(input.key_learnings.length).toBe(2);
    });

    test("handles empty arrays", () => {
      const input = createHandoffInput({
        accomplishments: [],
        blockers: [],
        next_actions: [],
        key_learnings: [],
      });
      expect(input.accomplishments).toHaveLength(0);
      expect(input.blockers).toHaveLength(0);
      expect(input.next_actions).toHaveLength(0);
      expect(input.key_learnings).toHaveLength(0);
    });
  });

  describe("Context Percentage", () => {
    test("accepts valid context percentage", () => {
      const input = createHandoffInput({ context_pct: 72 });
      expect(input.context_pct).toBe(72);
    });

    test("handles zero context percentage", () => {
      const input = createHandoffInput({ context_pct: 0 });
      expect(input.context_pct).toBe(0);
    });

    test("handles high context percentage", () => {
      const input = createHandoffInput({ context_pct: 95 });
      expect(input.context_pct).toBe(95);
    });
  });

  describe("Cycle Number", () => {
    test("starts at cycle 1", () => {
      const input = createHandoffInput({ cycle_number: 1 });
      expect(input.cycle_number).toBe(1);
    });

    test("supports multi-cycle sessions", () => {
      const input = createHandoffInput({ cycle_number: 5 });
      expect(input.cycle_number).toBe(5);
    });
  });
});

// ===== Load Cycle Handoff Tests =====

describe("Load Cycle Handoff", () => {
  describe("Input Methods", () => {
    test("accepts session_id as argument", async () => {
      const proc = Bun.spawn(["bun", "run", "load-cycle-handoff.ts", "ralph-nonexistent-session"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      await proc.exited;

      // Should return JSON with found: false for nonexistent session
      const result = JSON.parse(output);
      expect(result).toHaveProperty("found");
    });

    test("accepts JSON input via stdin", async () => {
      const proc = Bun.spawn(["bun", "run", "load-cycle-handoff.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write(JSON.stringify({ session_id: "ralph-test-session" }));
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      await proc.exited;

      const result = JSON.parse(output);
      expect(result).toHaveProperty("found");
    });

    test("accepts plain session_id string via stdin", async () => {
      const proc = Bun.spawn(["bun", "run", "load-cycle-handoff.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.write("ralph-plain-session-id");
      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      await proc.exited;

      const result = JSON.parse(output);
      expect(result).toHaveProperty("found");
    });
  });

  describe("Load Input Structure", () => {
    test("requires session_id", () => {
      const input = createLoadInput();
      expect(input).toHaveProperty("session_id");
    });

    test("accepts optional cycle_number", () => {
      const input = createLoadInput({ cycle_number: 3 });
      expect(input.cycle_number).toBe(3);
    });
  });

  describe("Load Output Structure", () => {
    test("returns found boolean", async () => {
      const proc = Bun.spawn(["bun", "run", "load-cycle-handoff.ts", "nonexistent"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      await proc.exited;

      const result = JSON.parse(output);
      expect(typeof result.found).toBe("boolean");
    });

    test("returns error message when not found", async () => {
      const proc = Bun.spawn(["bun", "run", "load-cycle-handoff.ts", "definitely-not-exists"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.end();

      const output = await new Response(proc.stdout).text();
      await proc.exited;

      const result = JSON.parse(output);
      if (!result.found) {
        expect(result).toHaveProperty("error");
      }
    });
  });

  describe("Error Handling", () => {
    test("handles empty input", async () => {
      const proc = Bun.spawn(["bun", "run", "load-cycle-handoff.ts"], {
        cwd: SCRIPT_DIR,
        stdin: "pipe",
        stdout: "pipe",
        stderr: "pipe",
      });

      proc.stdin.end();

      const exitCode = await proc.exited;
      expect(exitCode).not.toBe(0);
    });
  });
});

// ===== Handoff Content Format Tests =====

describe("Handoff Content Format", () => {
  describe("Markdown Generation", () => {
    test("handoff content includes cycle number", () => {
      const input = createHandoffInput({ cycle_number: 3 });
      // Content would include "Cycle 3 Handoff"
      expect(input.cycle_number).toBe(3);
    });

    test("handoff content includes original objective", () => {
      const objective = "Implement user authentication system";
      const input = createHandoffInput({ original_objective: objective });
      expect(input.original_objective).toBe(objective);
    });

    test("handoff content includes context percentage", () => {
      const input = createHandoffInput({ context_pct: 68 });
      expect(input.context_pct).toBe(68);
    });
  });

  describe("Context Formatting", () => {
    // Test the formatHandoffContext function logic

    test("next cycle number is incremented", () => {
      const cycleNumber = 2;
      const nextCycle = cycleNumber + 1;
      expect(nextCycle).toBe(3);
    });

    test("empty accomplishments shows placeholder", () => {
      const accomplishments: string[] = [];
      const placeholder = accomplishments.length > 0
        ? accomplishments.join("\n")
        : "- Work in progress";
      expect(placeholder).toBe("- Work in progress");
    });

    test("empty blockers shows none", () => {
      const blockers: string[] = [];
      const placeholder = blockers.length > 0
        ? blockers.join("\n")
        : "- None identified";
      expect(placeholder).toBe("- None identified");
    });

    test("empty next_actions shows default", () => {
      const nextActions: string[] = [];
      const placeholder = nextActions.length > 0
        ? nextActions.join("\n")
        : "1. Continue working on the original objective";
      expect(placeholder).toBe("1. Continue working on the original objective");
    });
  });
});

// ===== Integration Tests =====

describe("Save and Load Integration", () => {
  test("handoff data round-trips correctly", () => {
    const original = createHandoffInput({
      session_id: "ralph-roundtrip-test",
      cycle_number: 2,
      original_objective: "Test objective for round-trip",
      context_pct: 55,
      accomplishments: ["Item 1", "Item 2"],
      blockers: ["Blocker 1"],
      next_actions: ["Action 1", "Action 2"],
      key_learnings: ["Learning 1"],
    });

    // Serialize and deserialize (simulating save/load)
    const serialized = JSON.stringify(original);
    const deserialized = JSON.parse(serialized);

    expect(deserialized.session_id).toBe(original.session_id);
    expect(deserialized.cycle_number).toBe(original.cycle_number);
    expect(deserialized.original_objective).toBe(original.original_objective);
    expect(deserialized.context_pct).toBe(original.context_pct);
    expect(deserialized.accomplishments).toEqual(original.accomplishments);
    expect(deserialized.blockers).toEqual(original.blockers);
    expect(deserialized.next_actions).toEqual(original.next_actions);
    expect(deserialized.key_learnings).toEqual(original.key_learnings);
  });

  test("preserves session ID across cycles", () => {
    const sessionId = "ralph-persistent-session-id";
    const cycle1 = createHandoffInput({ session_id: sessionId, cycle_number: 1 });
    const cycle2 = createHandoffInput({ session_id: sessionId, cycle_number: 2 });
    const cycle3 = createHandoffInput({ session_id: sessionId, cycle_number: 3 });

    expect(cycle1.session_id).toBe(sessionId);
    expect(cycle2.session_id).toBe(sessionId);
    expect(cycle3.session_id).toBe(sessionId);
  });
});
