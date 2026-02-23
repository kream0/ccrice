const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

let input = '';
process.stdin.on('data', chunk => input += chunk);
process.stdin.on('end', () => {
    try {
        const data = JSON.parse(input);
        const model = data.model?.display_name || data.model?.id || '?';
        const dir = path.basename(data.workspace?.current_dir || data.cwd || '.');
        const pct = Math.floor(data.context_window?.used_percentage || 0);
        const durationMs = data.cost?.total_duration_ms || 0;

        const CYAN = '\x1b[36m', GREEN = '\x1b[32m', YELLOW = '\x1b[33m', RED = '\x1b[31m', MAGENTA = '\x1b[35m', BLUE = '\x1b[34m', RESET = '\x1b[0m';

        // Color-coded progress bar based on context usage
        const barColor = pct >= 90 ? RED : pct >= 70 ? YELLOW : GREEN;
        const filled = Math.floor(pct / 10);
        const bar = '\u2588'.repeat(filled) + '\u2591'.repeat(10 - filled);

        // Duration formatting
        const totalSecs = Math.floor(durationMs / 1000);
        let duration;
        if (totalSecs < 60) {
            duration = `${totalSecs}s`;
        } else if (totalSecs < 3600) {
            duration = `${Math.floor(totalSecs / 60)}m ${totalSecs % 60}s`;
        } else if (totalSecs < 86400) {
            const h = Math.floor(totalSecs / 3600);
            const m = Math.floor((totalSecs % 3600) / 60);
            duration = `${h}h ${m}m`;
        } else {
            const d = Math.floor(totalSecs / 86400);
            const h = Math.floor((totalSecs % 86400) / 3600);
            duration = `${d}d ${h}h`;
        }


        // Git info with caching
        const CACHE_FILE = path.join(require('os').tmpdir(), 'statusline-git-cache');
        const CACHE_MAX_AGE = 5;
        const cwd = data.workspace?.current_dir || data.cwd;

        let branch = '', staged = 0, modified = 0, untracked = 0, ahead = 0, behind = 0;
        let cacheStale = true;
        try {
            if (fs.existsSync(CACHE_FILE)) {
                cacheStale = (Date.now() / 1000) - fs.statSync(CACHE_FILE).mtimeMs / 1000 > CACHE_MAX_AGE;
            }
        } catch {}

        if (cacheStale) {
            try {
                execSync('git rev-parse --git-dir', { cwd, stdio: 'ignore' });
                branch = execSync('git branch --show-current', { cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
                if (!branch) {
                    // Detached HEAD: try tag name, then short SHA
                    try { branch = execSync('git describe --tags --exact-match HEAD', { cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim(); } catch {}
                    if (!branch) branch = execSync('git rev-parse --short HEAD', { cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim();
                    if (branch) branch = `(${branch})`; // wrap detached ref in parens
                }
                staged = execSync('git diff --cached --numstat', { cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim().split('\n').filter(Boolean).length;
                modified = execSync('git diff --numstat', { cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim().split('\n').filter(Boolean).length;
                untracked = execSync('git ls-files --others --exclude-standard', { cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim().split('\n').filter(Boolean).length;

                // Ahead/behind remote tracking branch
                try {
                    const ab = execSync('git rev-list --left-right --count HEAD...@{upstream}', { cwd, encoding: 'utf8', stdio: ['pipe', 'pipe', 'ignore'] }).trim().split(/\s+/);
                    ahead = parseInt(ab[0]) || 0;
                    behind = parseInt(ab[1]) || 0;
                } catch {}

                fs.writeFileSync(CACHE_FILE, `${branch}|${staged}|${modified}|${untracked}|${ahead}|${behind}`);
            } catch {
                fs.writeFileSync(CACHE_FILE, '|||||');
            }
        } else {
            try {
                const parts = fs.readFileSync(CACHE_FILE, 'utf8').trim().split('|');
                branch = parts[0] || '';
                staged = parseInt(parts[1]) || 0;
                modified = parseInt(parts[2]) || 0;
                untracked = parseInt(parts[3]) || 0;
                ahead = parseInt(parts[4]) || 0;
                behind = parseInt(parts[5]) || 0;
            } catch {}
        }

        // Line 1: model, directory, git branch with full status
        let line1 = `${CYAN}[${model}]${RESET} \ud83d\udcc1 ${dir}`;
        if (branch) {
            let parts = [];
            if (staged > 0) parts.push(`${GREEN}+${staged}${RESET}`);
            if (modified > 0) parts.push(`${YELLOW}~${modified}${RESET}`);
            if (untracked > 0) parts.push(`${RED}?${untracked}${RESET}`);
            if (ahead > 0) parts.push(`${MAGENTA}\u2191${ahead}${RESET}`);
            if (behind > 0) parts.push(`${BLUE}\u2193${behind}${RESET}`);

            // Branch color: green if clean, yellow if dirty, red if untracked
            const branchColor = untracked > 0 ? RED : (staged > 0 || modified > 0) ? YELLOW : GREEN;
            line1 += ` | ${branchColor}\ud83c\udf3f ${branch}${RESET}${parts.length ? ' ' + parts.join(' ') : ''}`;
        }

        // Line 2: progress bar, percentage, duration
        const line2 = `${barColor}${bar}${RESET} ${pct}% | \u23f1\ufe0f ${duration}`;

        console.log(line1);
        console.log(line2);
    } catch (e) {
        console.log('statusline error');
    }
});
