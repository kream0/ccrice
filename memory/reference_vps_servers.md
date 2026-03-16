---
name: VPS Server Reference
description: SSH access and purpose of the user's VPS servers
type: reference
---

**Production VPS (Hetzner):**
- IP: 167.235.153.214
- SSH: `ssh vps` (key: ~/.ssh/id_rsa)
- Purpose: Production apps (m-bao, decorio, assistario, croissantscore, crowdfounding-gala, yeli-backend)
- Specs: 15GB RAM, 150GB disk, 501+ days uptime
- Stack: PM2 + nginx + PostgreSQL 16 + Docker/Supabase

**Personal VPS (Hetzner):**
- IP: 91.99.113.48
- SSH: `ssh personal-vps` (key: ~/.ssh/personal-vps)
- Purpose: Fang autonomous agent
- Specs: 4 vCPU, 8GB RAM, 75GB disk, 4GB swap
- Stack: Node.js 22, Claude Code 2.1.76, bun, memr, tmux, ttyd, nginx
