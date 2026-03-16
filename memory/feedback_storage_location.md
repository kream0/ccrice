---
name: Store downloads on E or Z drive
description: Never download large files to C drive - use E or Z drive for models, packages, caches
type: feedback
---

All large downloads (pip packages, models, venvs, caches) must go to E:\ or Z:\ drive, not C:\.
C drive is critically low on space.

**Why:** C drive storage is limited. E drive (238GB) is also nearly full (9GB free as of 2026-03-13). Z drive (224GB, 200GB free) is the best target.

**How to apply:**
- Set pip cache to Z drive
- Set HF_HOME / TRANSFORMERS_CACHE to Z drive
- Create venvs on Z drive
- Use --target or --cache-dir flags when installing
- Move existing downloads from C to Z when possible
