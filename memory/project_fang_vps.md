---
name: Fang VPS Agent Project
description: Autonomous Claude Code agent (Fang) being deployed on personal-vps (91.99.113.48) — architecture, status, and key decisions
type: project
---

Fang is an autonomous Claude Code agent running 24/7 on a Hetzner VPS (91.99.113.48, SSH alias: personal-vps, user: karimel).

**Why:** The user wants a persistent AI assistant with its own WhatsApp account that can monitor conversations, spawn isolated project sessions, auto-create skills, and learn continuously.

**How to apply:** When working in ~/sandbox/claude-code-vps-setup/, follow the CLAUDE.md there for deployment checklist and session protocol. The master agent architecture enforces strict context isolation — it never reads project source code.

Key details:
- VPS: 4 vCPU, 8GB RAM, 75GB disk, Ubuntu 24.04
- Runtime: tmux + claude --dangerously-skip-permissions + /loop 5m /heartbeat
- Memory: memr (mem-reason CLI v0.2.0) — hybrid central + per-project DBs
- Config sync: ccrice repo (github.com/kream0/ccrice) via SSH
- Web terminal: ttyd behind nginx + basic auth at fang.karimel.com
- Project sessions: separate tmux windows (proj-*, forge-*, inv-*), max 2 concurrent, 2h timeout
- Communication: structured JSON reports in ~/fang/reports/
