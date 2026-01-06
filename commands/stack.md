---
description: Quick verification of all 3 servers in the Assistario stack
---

Verify all 3 servers are running and report status.

Run these health checks:

```bash
curl -s http://localhost:1337/app/ | head -3      # Frontend
curl -s http://localhost:3001/health              # Backend API
curl -s http://localhost:3000/api/v1/health       # MCP Server
```

Report in this format:

| Server | Port | Status | Response |
|--------|------|--------|----------|
| Frontend | 1337 | ✅/❌ | [first line of response or error] |
| Backend API | 3001 | ✅/❌ | [health response or error] |
| MCP Server | 3000 | ✅/❌ | [health response or error] |

## If servers are down, provide start commands:

**Frontend (from project root):**
```bash
npm start
```

**Backend API (from backend/):**
```bash
cd backend && npm run dev
```

**MCP Server (from mcp-server/):**
```bash
cd mcp-server && npm start
```

## Quick Start All (background):
```bash
npm start &                           # Frontend
cd backend && npm run dev &           # Backend
cd mcp-server && npm start &          # MCP
```
