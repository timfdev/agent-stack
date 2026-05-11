# agent-stack

Mac mini autonomous agent. Two-service compose stack: Agent Zero as the
controller, Docker MCP gateway for everything else. Discord plugin loaded
inside the Agent Zero container. v0 milestone is an autonomous weekday
LinkedIn lead digest.

The architectural rationale lives in [`agent-stack-plan.md`](agent-stack-plan.md);
this file is the operator's runbook.

## What's tracked here vs. what's local

- **Tracked (this repo):** `docker-compose.yml`, `.env.example`,
  `mcp-config/`, `agent-zero/skills/`, this README.
- **Gitignored (local on the Mac mini):** `.env` (real credentials + config),
  `data/` (memory, scheduler.db, LinkedIn session cache), the cloned
  `agent-zero/plugins/discord/` source.

Disaster recovery is therefore `git clone + restic restore + docker compose up -d`.

## First-time setup on the Mac mini

Prereqs already in place on the host: Docker Desktop running, NordVPN
Meshnet client active, FileVault on, restic configured for `data/` +
`secrets/`.

### 1. Clone

```bash
mkdir -p ~/agent-stack && cd ~/agent-stack
git clone git@github.com:<agent-account>/agent-stack.git .
```

### 2. Populate `.env`

```bash
cp .env.example .env
chmod 600 .env
# Fill in:
#   OPENAI_API_KEY              — set a low monthly $ cap on it
#   DISCORD_BOT_TOKEN           — bot account token
#   DISCORD_CHANNEL_*           — channel IDs after creating the server
#   AGENT_ZERO_BIND             — Mac mini's Meshnet IP
```

Why .env and not Docker secrets: neither Agent Zero nor a0-discord read
the `_FILE` indirection convention, so the secrets/ ceremony would have
been ornamental. `chmod 600 .env` is the same threat model on this host.

### 3. Clone the a0-discord plugin source

The plugin source is third-party and not tracked here — clone it into the
gitignored path and pin to a known commit:

```bash
git clone https://github.com/spinnakergit/a0-discord.git agent-zero/plugins/discord
cd agent-zero/plugins/discord
git checkout <PIN_THIS_COMMIT>   # write the hash you tested into this README
cd ../../..
```

Compose mounts `agent-zero/plugins/discord` read-only into the container
at `/a0/usr/plugins/discord`. On first start, run the plugin's one-time
initialize step inside the container:

```bash
docker compose up -d agent-zero
docker exec agent-zero ln -sf /a0/usr/plugins/discord /a0/plugins/discord
docker exec agent-zero python /a0/usr/plugins/discord/initialize.py
docker exec agent-zero touch /a0/usr/plugins/discord/.toggle-1
docker exec agent-zero supervisorctl restart run_ui
```

The plugin reads `DISCORD_BOT_TOKEN` directly from the container env
(set by compose from `.env`); no wrapper needed.

### 4. Register the LinkedIn MCP server with the gateway

```bash
docker mcp catalog import ./mcp-config/custom.yaml
docker mcp server enable linkedin
```

This is a one-time registration into the gateway's profile DB. The
gateway will lazy-spawn the LinkedIn container on first tool call.

### 5. First-time LinkedIn login (manual, ~once per quarter)

The Patchright session lives in `data/linkedin-mcp/cache/`. Easiest path:

```bash
docker run --rm -it \
  -v "$PWD/data/linkedin-mcp/cache:/home/pwuser/.linkedin-mcp" \
  stickerdaniel/linkedin-mcp-server:4.12.0 --login
```

Follow the prompts, complete the LinkedIn login in the headed browser.
The session persists in the mounted cache directory.

### 6. Bring up the stack

```bash
docker compose up -d
docker compose logs -f agent-zero
```

Reach the web UI directly over Meshnet from any linked device:

```
http://<mac-mini-meshnet-ip>:50001
```

Set an Agent Zero UI password on first login. Tighten Meshnet per-peer
permissions in the NordVPN app so only devices that need it have
"Allow incoming traffic" enabled.

(SSH-forward fallback if you prefer to bind to 127.0.0.1 instead:
`ssh -L 50001:127.0.0.1:50001 <meshnet-name>`.)

### 7. Bootstrap the v0 skill

Pick `gpt-4o-mini` as the model in Agent Zero's Settings on first run
(the OPENAI_API_KEY is already in the container env, so it just shows
up as a valid provider). Then:

In Discord `#general`, ask Agent Zero to:

> Create a skill named `linkedin_daily_digest` from
> `knowledge/custom/skills/linkedin_daily_digest.md`. Schedule it weekdays
> at 08:00 with ±15 minutes of jitter. Post results to `#leads`.

Then iterate criteria conversationally. The agent persists schedule and
memory under `data/agent-zero/`.

## Daily operation

| Cadence | Action |
|---|---|
| Always | Docker Desktop running, Meshnet up |
| On boot | `docker compose up -d` (compose `restart: unless-stopped` covers most cases) |
| Per quarter | Re-run step 5 (LinkedIn re-login) |
| Per month | Glance at `#audit`, test-restore from restic |
| Per key rotation | Edit `.env`, `docker compose restart agent-zero` |
| Per new tool | Add entry to `mcp-config/custom.yaml`, `docker mcp server enable <name>` |

## Notes on image pins

- `agent0ai/agent-zero:ready` — Agent Zero ships with a moving `ready`
  tag rather than versioned tags. Pin by digest in `.env` if you want
  strict reproducibility: `AGENT_ZERO_IMAGE=agent0ai/agent-zero@sha256:...`.
- `docker/mcp-gateway:v0.42.1` — versioned, bump deliberately.
- `stickerdaniel/linkedin-mcp-server:4.12.0` — versioned. Swap to your
  own fork's image tag here when you add `search_posts`.

## Growth path

New tools = new entry in `mcp-config/custom.yaml` plus
`docker mcp server enable <name>`. No compose changes. See the growth
table in `agent-stack-plan.md` for when to add a second service
(OpenHands, socket-proxy, caddy).
