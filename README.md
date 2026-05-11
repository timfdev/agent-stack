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
  `data/` (memory, scheduler.db, plugin runtime state, MCP session caches).

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

### 3. Register MCP servers with the gateway

Host-side CLI; doesn't need the stack up. The `docker mcp` CLI ships
with Docker Desktop.

```bash
docker mcp catalog import ./mcp-config/custom.yaml
docker mcp server enable <name>           # for each server in custom.yaml
```

One-time registration into the gateway's profile DB. The gateway then
lazy-spawns each MCP server container on first tool call. Adding a new
tool later = append an entry to `custom.yaml` + run `docker mcp server
enable <name>`; no compose changes.

Some MCP servers need their own first-time setup before the agent can
use them (e.g. interactive login for browser-based scrapers, OAuth flow
for API-based ones). Those steps live in each server's own
documentation — keep notes in `mcp-config/` if you need a runbook.

### 4. Bring up the stack

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

### 5. Install the Discord plugin via Agent Zero's UI

Open the UI, find the Discord plugin in the community plugin list,
install + enable it from there, and configure channel routing +
`auto_start` in its plugin settings page. The plugin reads
`DISCORD_BOT_TOKEN` from the container env (set by compose from `.env`);
no wrapper needed.

### 6. Bootstrap the v0 skill

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
| Per MCP-server quirks | Re-do any per-server first-time setup if a session expires (see that server's docs) |
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
