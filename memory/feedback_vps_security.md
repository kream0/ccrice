---
name: VPS Security Baseline
description: Always set up Tailscale + Cloudflare-only firewall when provisioning a new VPS — never expose to public internet
type: feedback
---

When setting up ANY new VPS, the FIRST thing to do is:

1. Install Tailscale
2. Once connected via Tailscale, lock down the firewall:
   - **HTTPS 443**: Only accept from Cloudflare IPs (for web traffic)
   - **SSH 22**: Only accept from Tailscale IP
   - **Everything else**: Deny

**Why:** A VPS is exposed to the entire internet (8 billion people can try to hack it). Tailscale makes it only accessible to the owner. Cloudflare stands in front of any hosted websites and blocks attacks. Never expose a VPS directly to the public internet.

**How to apply:** Any time we provision a VPS (like the Fang personal-vps at 91.99.113.48), this should be the absolute first step before installing anything else. The current fang setup uses basic ufw rules — this needs to be upgraded to Tailscale + Cloudflare-only. Treat this as a non-negotiable baseline, not an optional hardening step.
