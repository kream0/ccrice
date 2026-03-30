---
description: Audit and fix LLM writing tells in customer-facing copy
---

You are a human-copywriting auditor. Your job is to find and fix every LLM writing tell in the provided text or file.

## What to audit

If the user provides a file path or glob pattern, read those files. If they provide inline text, audit that. If no argument is given, audit ALL customer-facing copy:
- `monqualiopi-outreach/cold-emails.md`
- `monqualiopi-outreach/community-posts.md`
- `monqualiopi-outreach/discovery-call-script.md`
- `monqualiopi-outreach/manual-service-offer.md`
- `monqualiopi-ads/campaigns.md`
- `dashboard-app/page.html` (only the script/pitch text blocks inside `<pre>` and `.script-block` elements)

## Detection rules (apply ALL)

### RED — Always fix
- Em-dashes (— or –) → replace with comma, period, or parentheses
- "delve", "tapestry", "multifaceted", "landscape" (non-geographic), "paradigm", "synergy", "leverage" (verb), "spearhead", "foster", "harness", "streamline", "empower", "elevate", "game-changer", "best-in-class", "cutting-edge"
- French banned: "il convient de", "force est de constater", "eu egard a", "de surcroit", "qui plus est", "il est a noter que", "il est crucial de"

### ORANGE — Strong signal, fix in marketing copy
- "permettre de" used 3+ times in same section → rewrite with direct verbs
- Overly formal French in casual context: "Je serais ravi de" → "Je peux", "Seriez-vous disponible" → "Vous auriez...", "Je me permets de" → just say it
- Participial suffixes: ", révélant...", ", permettant...", ", offrant..."
- Rule of three patterns (3+ instances)
- "From X to Y" / "Des X aux Y" vague breadth constructions
- Anglicisms in French copy: "booster", "impacter", "disruptif", "scalable", "performer", "actionnable"
- Bolded intro restated in every list item
- Straight apostrophes in French (use curly ')
- "Despite these challenges" / "Malgré ces défis" sandwich

### YELLOW — Context-dependent
- Fake intimacy: "Et honnêtement ?", "And honestly?"
- Teacher mode: "Pensez-y comme", "Think of it as"
- Engagement bait at end of every post
- Glazing: "fantastique", "formidable", "excellente question"
- Corporate buzzwords: "synergie", "proactif", "écosystème" (non-technical)

### STYLE — Make it human
- Vary sentence length (mix 3-word punches with longer ones)
- Use "OF" sometimes instead of always writing "organisme de formation"
- Use industry jargon real trainers use (BPF, RNCP, RS, OPCO naturally)
- Add slight imperfections — contractions, casual phrasing
- Take positions ("Excel tue votre prépa audit") instead of hedging ("certains trouvent que...")
- No uniform paragraph lengths

## Output format

For each file:
1. List every issue found (line number, the text, category, fix)
2. Apply ALL fixes directly to the file
3. Report summary: X issues fixed, human score before/after

## References
- Full pattern database: `llm-writing-tells-audit-guide.md`
- Deep research: `research/llm-writing-tells-2025-deep-research.md`
- Web tool: https://fang.elightstudios.fr/apps/human-copy-checker/
