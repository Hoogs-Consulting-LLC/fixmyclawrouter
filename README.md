# 🔧 FixMyClawRouter — Keep OpenClaw Running

**Anthropic changed the rules. We changed the game.**

On April 4, 2026, Anthropic started metering third-party tool usage on Claude Max subscriptions — breaking OpenClaw for thousands of users. FixMyClawRouter is a smart LLM routing proxy that keeps your OpenClaw running by distributing requests across multiple AI providers.

## What It Does

Instead of sending everything to one expensive provider, FixMyClawRouter intelligently routes each request to the best available LLM:

- **Simple messages** → fast free models
- **Code generation** → specialized code models
- **Complex reasoning** → premium models
- **Tool calling** → only models that support it (automatically detected)

## Free Tier — Yes, Actually Free

We share our infrastructure with the community. Free users get:
- Access to our vLLM models and free-tier providers
- Tool calling support (required for OpenClaw agents)
- Slower response times (2s throttle) but **it works**

Subscribers get zero delay, higher limits, and priority routing.

## One-Command Install

```bash
curl -fsSL https://fixmyclawrouter.com/install.sh | bash
```

That's it. Your OpenClaw config is automatically updated. The script:
1. Generates a unique API key (or re-uses your existing one on re-install)
2. Backs up your `openclaw.json` and any agent `models.json` files
3. Updates the API endpoint to route through FixMyClawRouter
4. Saves config hashes so uninstall knows if you changed things

Re-running the installer is safe — it detects an existing installation and lets you keep your current key or generate a new one.

## Uninstall

Changed your mind? No hard feelings:

```bash
curl -fsSL https://fixmyclawrouter.com/nah-i-didnt-like-it.sh | bash
```

It detects what changed since install and offers:
- **Surgical restore** — only revert the proxy settings
- **Full restore** — restore your entire backup (openclaw.json + models.json)
- **Manual** — show you what to change

Agent `models.json` files are only restored if they haven't been modified since install — we won't risk breaking your config.

## How It Works

```
Your OpenClaw → FixMyClawRouter Proxy → Best Available LLM
                     ↓
              CPU Classifier (<1ms)
              analyzes your prompt
                     ↓
         Routes to optimal provider:
         ├── Free tier (simple queries)
         ├── Our vLLM fleet (self-hosted)
         ├── Mid-range models (code, analysis)
         └── Premium models (reasoning, BYOK)
```

## Bring Your Own Keys (BYOK)

Already have API keys? Add them in your dashboard and they'll be used for your requests — at your cost, no markup:

1. Go to [fixmyclawrouter.com/configure](https://fixmyclawrouter.com/configure)
2. Add your Groq, xAI, Anthropic, OpenAI keys
3. The router uses YOUR keys for premium models, free providers for simple stuff

## Claim Your Account

After installing, claim your key to unlock:
- Dashboard with usage analytics
- Provider management
- Referral system (1M bonus tokens per referral)
- Plan upgrades

Visit [fixmyclawrouter.com/claim](https://fixmyclawrouter.com/claim)

## Pricing

| Plan | Price | What You Get |
|------|-------|-------------|
| **Free** | $0 | 500 req/day, free models, 2s delay, BYOK for premium |
| **Pro** | $49/mo | Unlimited, all models, zero delay, ~$40 API credits |
| **Team** | $99/mo | 5 seats, ~$80 credits, priority routing |
| **Enterprise** | $199/mo | Dedicated throughput, SLA, onboarding |

## Why Not Just Use the Free APIs Directly?

You could — but:
- **Tool calling** doesn't work on all free models. We route to ones that do.
- **Rate limits** — we handle failover automatically. Hit a 429? We try the next provider.
- **Prompt compression** — we optimize your prompts to save tokens.
- **Smart classification** — code goes to code models, chat goes to chat models.
- **One endpoint** — your OpenClaw just points to us. No config per provider.

## Security

- API keys encrypted at rest (AES-256-GCM)
- Email verification on account claims
- Prompt guardrails (injection detection, content safety)
- No prompt storage — we route in real-time
- BYOK keys never leave your account

## Built By

[Hoogs Consulting LLC](https://hoogs.net) — Fractional CTO services for startups.

Also check out [Agent-Generator.com](https://agent-generator.com) for pre-built AI agents.

---

**Questions?** → [info@fixmyclawrouter.com](mailto:info@fixmyclawrouter.com)

**Found a bug?** → Open an issue here.

**Want to contribute?** → PRs welcome for the install/uninstall scripts.
