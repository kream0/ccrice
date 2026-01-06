#!/usr/bin/env bun
/**
 * ralph-recall.ts - Query past Ralph sessions from memorai
 *
 * Searches memorai for Ralph-related memories including:
 * - Session summaries
 * - Error patterns
 * - Key learnings
 * - Accomplishments
 *
 * Features:
 * - Local project search (default)
 * - Global search across all known projects
 * - Date range filtering
 * - Multiple output formats
 */

import { MemoraiClient, databaseExists } from 'memorai';
import { existsSync, readdirSync, statSync, lstatSync } from 'fs';
import { join, resolve, basename } from 'path';
import { homedir } from 'os';

interface RecallInput {
  mode: 'sessions' | 'errors' | 'learnings' | 'search' | 'stats';
  query?: string;
  limit?: number;
  importance_min?: number;
  // New options
  global?: boolean;           // Search all known projects
  project?: string;           // Specific project path
  since?: string;             // ISO date string or relative (e.g., "7d", "1w", "1m")
  until?: string;             // ISO date string
  format?: 'json' | 'markdown' | 'compact';
}

interface RecallResult {
  id: string;
  category: string;
  title: string;
  summary: string;
  tags: string[];
  importance: number;
  created_at: string;
  relevance?: number;
  project?: string;  // Project name for global searches
}

interface RecallOutput {
  success: boolean;
  mode: string;
  count: number;
  results: RecallResult[];
  projects_searched?: string[];
  error?: string;
}

interface ProjectInfo {
  path: string;
  name: string;
}

/**
 * Parse relative date strings like "7d", "1w", "1m" into Date objects
 */
function parseRelativeDate(dateStr: string): Date | null {
  const now = new Date();

  // Try ISO date first
  const isoDate = new Date(dateStr);
  if (!isNaN(isoDate.getTime())) {
    return isoDate;
  }

  // Parse relative dates
  const match = dateStr.match(/^(\d+)([dwmy])$/i);
  if (!match) return null;

  const num = parseInt(match[1], 10);
  const unit = match[2].toLowerCase();

  switch (unit) {
    case 'd': // days
      now.setDate(now.getDate() - num);
      break;
    case 'w': // weeks
      now.setDate(now.getDate() - num * 7);
      break;
    case 'm': // months
      now.setMonth(now.getMonth() - num);
      break;
    case 'y': // years
      now.setFullYear(now.getFullYear() - num);
      break;
    default:
      return null;
  }

  return now;
}

/**
 * Find all projects with memorai databases
 */
function findMemoraProjects(): ProjectInfo[] {
  const projects: ProjectInfo[] = [];
  const searchPaths: string[] = [];

  // Common project locations
  const home = homedir();

  // Check common dev directories
  const commonDirs = [
    join(home, 'Documents'),
    join(home, 'Projects'),
    join(home, 'work'),
    join(home, 'dev'),
    join(home, 'code'),
    join(home, 'src'),
    // WSL paths
    '/mnt/c/Users',
  ];

  for (const dir of commonDirs) {
    if (existsSync(dir)) {
      searchPaths.push(dir);
    }
  }

  // Also check Claude's project cache for known projects
  const claudeProjectsDir = join(home, '.claude', 'projects');
  if (existsSync(claudeProjectsDir)) {
    try {
      const entries = readdirSync(claudeProjectsDir);
      for (const entry of entries) {
        // Claude encodes paths: /foo/bar -> -foo-bar
        // Decode: -foo-bar -> /foo/bar
        const decodedPath = entry.replace(/^-/, '/').replace(/-/g, '/');
        if (existsSync(decodedPath)) {
          searchPaths.push(decodedPath);
        }
      }
    } catch {
      // Ignore errors
    }
  }

  // Search for .memorai directories
  const visited = new Set<string>();

  function searchDir(dir: string, depth: number = 0): void {
    if (depth > 4 || visited.has(dir)) return;
    visited.add(dir);

    try {
      const memoraiPath = join(dir, '.memorai', 'memory.db');
      if (existsSync(memoraiPath)) {
        projects.push({
          path: dir,
          name: basename(dir)
        });
        return; // Don't search subdirs of projects
      }

      // Search subdirectories
      const entries = readdirSync(dir, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.isDirectory() && !entry.name.startsWith('.') && entry.name !== 'node_modules') {
          const fullPath = join(dir, entry.name);
          try {
            // Check if it's a symlink to avoid infinite loops
            const stat = lstatSync(fullPath);
            if (stat.isSymbolicLink()) {
              continue; // Skip symlinks to prevent circular references
            }
            searchDir(fullPath, depth + 1);
          } catch {
            // Skip entries we can't stat
          }
        }
      }
    } catch {
      // Ignore permission errors
    }
  }

  for (const searchPath of searchPaths) {
    searchDir(searchPath);
  }

  return projects;
}

// Parse input from stdin
async function getInput(): Promise<RecallInput> {
  // Check for command line argument first
  if (process.argv[2]) {
    try {
      return JSON.parse(process.argv[2]) as RecallInput;
    } catch {
      // Treat as search query string
      return { mode: 'search', query: process.argv.slice(2).join(' '), limit: 10 };
    }
  }

  // Read from stdin
  const chunks: Buffer[] = [];
  for await (const chunk of Bun.stdin.stream()) {
    chunks.push(chunk as Buffer);
  }
  const input = Buffer.concat(chunks).toString('utf-8').trim();

  if (!input) {
    return { mode: 'sessions', limit: 10 };
  }

  try {
    return JSON.parse(input) as RecallInput;
  } catch {
    // Treat as search query string
    return { mode: 'search', query: input, limit: 10 };
  }
}

function formatResults(results: RecallResult[], mode: string, format: 'markdown' | 'compact' = 'markdown'): string {
  if (results.length === 0) {
    return `No ${mode} found in memorai.`;
  }

  const lines: string[] = [];

  if (format === 'compact') {
    // Compact format for quick scanning
    lines.push(`Ralph ${mode.charAt(0).toUpperCase() + mode.slice(1)} (${results.length}):`);
    lines.push('');
    for (const result of results) {
      const date = new Date(result.created_at).toLocaleDateString();
      const projectStr = result.project ? `[${result.project}] ` : '';
      const stars = '★'.repeat(Math.min(result.importance, 5));
      lines.push(`${stars} ${projectStr}${result.title} (${date})`);
    }
    return lines.join('\n');
  }

  // Full markdown format
  lines.push(`## Ralph ${mode.charAt(0).toUpperCase() + mode.slice(1)} (${results.length} found)\n`);

  for (const result of results) {
    const date = new Date(result.created_at).toLocaleDateString();
    const importanceStars = '★'.repeat(Math.min(result.importance, 10));
    const relevanceStr = result.relevance !== undefined
      ? ` (${Math.round(result.relevance * 100)}% match)`
      : '';
    const projectStr = result.project ? ` | 📂 ${result.project}` : '';

    lines.push(`### ${result.title}${relevanceStr}`);
    lines.push(`📁 ${result.category} | 📅 ${date} | ${importanceStars}${projectStr}`);
    if (result.tags.length > 0) {
      lines.push(`🏷️ ${result.tags.join(', ')}`);
    }
    lines.push('');
    lines.push(result.summary);
    lines.push('');
    lines.push('---');
    lines.push('');
  }

  return lines.join('\n');
}

/**
 * Query a single project for Ralph memories
 */
function queryProject(
  projectPath: string,
  mode: string,
  query: string | undefined,
  limit: number,
  importanceMin: number,
  sinceDate: Date | null,
  untilDate: Date | null
): RecallResult[] {
  if (!databaseExists(projectPath)) {
    return [];
  }

  const memorai = new MemoraiClient({ projectDir: projectPath });
  const projectName = basename(projectPath);

  let searchResults;
  switch (mode) {
    case 'sessions':
      searchResults = memorai.search({
        query: 'ralph session',
        tags: ['ralph', 'session-summary'],
        limit: limit * 2, // Get more for date filtering
        importanceMin
      });
      break;

    case 'errors':
      searchResults = memorai.search({
        query: 'error pattern ralph',
        tags: ['ralph', 'error-pattern'],
        limit: limit * 2,
        importanceMin
      });
      break;

    case 'learnings':
      searchResults = memorai.search({
        query: 'learning ralph',
        tags: ['ralph', 'learning'],
        limit: limit * 2,
        importanceMin
      });
      break;

    case 'search':
    default:
      searchResults = memorai.search({
        query: query || 'ralph',
        tags: ['ralph'],
        limit: limit * 2,
        importanceMin
      });
      break;
  }

  let results: RecallResult[] = searchResults.map(r => ({
    id: r.id,
    category: r.category,
    title: r.title,
    summary: r.summary,
    tags: r.tags,
    importance: r.importance,
    created_at: r.createdAt,
    relevance: r.relevance,
    project: projectName
  }));

  // Apply date filtering
  if (sinceDate) {
    results = results.filter(r => new Date(r.created_at) >= sinceDate);
  }
  if (untilDate) {
    results = results.filter(r => new Date(r.created_at) <= untilDate);
  }

  return results;
}

async function main() {
  const input = await getInput();
  const limit = input.limit ?? 10;
  const importanceMin = input.importance_min ?? 1;
  const format = input.format ?? 'markdown';

  // Parse date filters
  const sinceDate = input.since ? parseRelativeDate(input.since) : null;
  const untilDate = input.until ? parseRelativeDate(input.until) : null;

  let results: RecallResult[] = [];
  let projectsSearched: string[] = [];

  try {
    // Handle stats mode separately
    if (input.mode === 'stats') {
      const projects = input.global ? findMemoraProjects() : [];
      const currentProject = process.cwd();

      if (!input.global && !databaseExists(currentProject)) {
        const output: RecallOutput = {
          success: false,
          mode: 'stats',
          count: 0,
          results: [],
          error: 'Memorai database not found. Run `memorai init` or use --global.'
        };
        console.log(JSON.stringify(output, null, 2));
        return;
      }

      const statsProjects = input.global ? projects : [{ path: currentProject, name: basename(currentProject) }];
      const statsLines: string[] = ['## Ralph Global Statistics\n'];

      for (const proj of statsProjects) {
        if (!databaseExists(proj.path)) continue;
        const memorai = new MemoraiClient({ projectDir: proj.path });
        const stats = memorai.stats();

        // Count ralph entries
        const ralphEntries = memorai.search({ query: 'ralph', tags: ['ralph'], limit: 1000 });
        const sessionCount = ralphEntries.filter(r => r.tags.includes('session-summary')).length;
        const errorCount = ralphEntries.filter(r => r.tags.includes('error-pattern')).length;
        const learningCount = ralphEntries.filter(r => r.tags.includes('learning')).length;

        statsLines.push(`### ${proj.name}`);
        statsLines.push(`- Total memories: ${stats.total}`);
        statsLines.push(`- Ralph entries: ${ralphEntries.length}`);
        statsLines.push(`  - Sessions: ${sessionCount}`);
        statsLines.push(`  - Errors: ${errorCount}`);
        statsLines.push(`  - Learnings: ${learningCount}`);
        statsLines.push('');
      }

      const output: RecallOutput = {
        success: true,
        mode: 'stats',
        count: statsProjects.length,
        results: [],
        projects_searched: statsProjects.map(p => p.name)
      };

      console.log(JSON.stringify(output, null, 2));
      console.error('\n' + statsLines.join('\n'));
      return;
    }

    // Determine which projects to search
    if (input.global) {
      // Global search across all projects
      const projects = findMemoraProjects();
      projectsSearched = projects.map(p => p.name);

      for (const project of projects) {
        const projectResults = queryProject(
          project.path,
          input.mode,
          input.query,
          Math.ceil(limit / projects.length) + 5, // Distribute limit
          importanceMin,
          sinceDate,
          untilDate
        );
        results.push(...projectResults);
      }
    } else if (input.project) {
      // Specific project
      const projectPath = resolve(input.project);
      if (!databaseExists(projectPath)) {
        const output: RecallOutput = {
          success: false,
          mode: input.mode,
          count: 0,
          results: [],
          error: `Memorai database not found in ${projectPath}`
        };
        console.log(JSON.stringify(output, null, 2));
        return;
      }

      projectsSearched = [basename(projectPath)];
      results = queryProject(
        projectPath,
        input.mode,
        input.query,
        limit,
        importanceMin,
        sinceDate,
        untilDate
      );
    } else {
      // Current project only
      const projectDir = process.cwd();
      if (!databaseExists(projectDir)) {
        const output: RecallOutput = {
          success: false,
          mode: input.mode,
          count: 0,
          results: [],
          error: 'Memorai database not found. Run `memorai init` first.'
        };
        console.log(JSON.stringify(output, null, 2));
        return;
      }

      projectsSearched = [basename(projectDir)];
      results = queryProject(
        projectDir,
        input.mode,
        input.query,
        limit,
        importanceMin,
        sinceDate,
        untilDate
      );
    }

    // Sort by importance then date
    results.sort((a, b) => {
      if (b.importance !== a.importance) {
        return b.importance - a.importance;
      }
      return new Date(b.created_at).getTime() - new Date(a.created_at).getTime();
    });

    // Apply final limit
    results = results.slice(0, limit);

    const output: RecallOutput = {
      success: true,
      mode: input.mode,
      count: results.length,
      results,
      projects_searched: projectsSearched
    };

    // Output based on format
    if (format === 'json') {
      console.log(JSON.stringify(output, null, 2));
    } else {
      // Output JSON to stdout for programmatic use
      console.log(JSON.stringify(output, null, 2));
      // Also output formatted text to stderr for human reading
      console.error('\n' + formatResults(results, input.mode, format === 'compact' ? 'compact' : 'markdown'));
    }

  } catch (error) {
    const output: RecallOutput = {
      success: false,
      mode: input.mode,
      count: 0,
      results: [],
      error: error instanceof Error ? error.message : String(error)
    };
    console.log(JSON.stringify(output, null, 2));
  }
}

main().catch(console.error);
