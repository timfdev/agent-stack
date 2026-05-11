# Mac mini autonomous agent — plan

## Architecture

Mac mini is the dedicated host. Docker Desktop runs the entire stack in containers. Agent Zero is the controller and owns its own scheduling. Discord integration is via the `spinnakergit/a0-discord` plugin loaded inside the Agent Zero container — no separate bridge service. All tools reach Agent Zero through the Docker MCP gateway, so adding capability = registering a server in a custom catalog, not editing compose. LinkedIn integration uses `stickerdaniel/linkedin-mcp-server` — Patchright-managed browser is bundled inside that image, no separate Chrome service. NordVPN Meshnet provides private SSH/UI access; no VPN tunnel for outbound traffic. Credentials live in compose secrets inside the agent stack, never in the personal 1Password. Dedicated agent accounts limit blast radius; permission scoping bounds capability.

## Host (macOS)

The Mac mini is dedicated — no personal use, only agent + dev services. Single macOS user, no split identities at the OS level.

- Docker Desktop, autostart at login, VM allocated 12GB / 4 cores
- NordVPN Meshnet client (only ingress path; SSH, web UI, dev access)
- FileVault on (protects agent secrets if device is physically stolen)
- Auto-login off; auto-restart-after-reboot enabled so services come back up unattended
- Default macOS user holds the agent's git identity (SSH key for the agent's GitHub account, git user.name/email set globally to agent identity)
- `restic` cron → encrypted off-site backup of `~/agent-stack/data/`, `~/agent-stack/secrets/`, and any local dev trees (mandatory — this machine is the only copy of agent state)

## v0 stack — 2 compose services

| Service | Purpose |
|---|---|
| `agent-zero` | Controller — memory, skills, self-managed scheduler, **a0-discord plugin loaded** |
| `mcp-gateway` | Docker MCP Toolkit gateway — lazy-spawns MCP servers from catalogs |

Single internal network `agent-net`. No host port exposure — Meshnet only reaches Agent Zero's web UI on the container port. The Discord plugin opens an outbound websocket to Discord; no inbound port needed.

## MCP servers — gateway-managed, not in compose

Registered in `mcp-config/custom.yaml`, lazy-spawned by the gateway:

```yaml
servers:
  linkedin:
    image: ghcr.io/stickerdaniel/linkedin-mcp-server:4.12.0
    volumes:
      - ./data/linkedin-mcp/cache:/cache
    env:
      LINKEDIN_BROWSER_CACHE: /cache
    disabled_tools:
      - connect_with_person
      - send_message
```

**Adding tool #2 = new entry in `custom.yaml` + `docker mcp server enable X`. No compose edit. No agent restart.**

## Discord routing — channel-based, plugin-handled

The `a0-discord` plugin reads channel/permission config from its YAML, no router service needed. Agent Zero gains Discord as a capability (read, send, monitor, react) the same way it has any other tool.

| Channel | Purpose |
|---|---|
| `#general` | Conversation, ad-hoc tasks, criteria refinement |
| `#leads` | Daily LinkedIn digest output (write-only by agent) |
| `#audit` | Action log, write-only by agent, kill-switch view |

(`#code`, `#projects` added later when OpenHands joins — likely as a separate Discord bot account at that point.)

## Compose secrets — in `secrets/`, chmod 600

- `anthropic-key` — Agent Zero, with provider-side daily $ cap
- `discord-az-token` — Agent Zero bot, consumed by the a0-discord plugin

LinkedIn session is **not a secret file** — it lives in `data/linkedin-mcp/cache/` (Patchright's persistent profile, set up via one-time login).

## Disk layout

```
~/agent-stack/
  docker-compose.yml
  .env                            # non-secret config
  secrets/                        # mounted via compose `secrets:`
  data/
    agent-zero/
      memory/
      knowledge/
      work_dir/
      scheduler.db
      plugins/
        discord/                  # a0-discord plugin state (member registry, etc.)
    linkedin-mcp/
      cache/                      # Patchright session — back this up
    audit-logs/
  mcp-config/
    custom.yaml                   # registers all custom MCP servers
  agent-zero/
    plugins/
      discord/                    # a0-discord plugin install (cloned/symlinked)
    skills/
      linkedin_daily_digest.md    # the v0 milestone skill
```

## v0 milestone — LinkedIn daily digest

1. `docker compose up -d` (2 services)
2. **Install a0-discord plugin** into the Agent Zero container: clone `spinnakergit/a0-discord` into `agent-zero/plugins/discord/`, symlink to `/a0/plugins/discord` per its README, configure with the Discord bot token from `secrets/discord-az-token`
3. **First-time LinkedIn login**: VNC into a one-shot Patchright run, or `pip install` on host once and copy the cache, → log in to LinkedIn manually, populate `data/linkedin-mcp/cache/`
4. Configure Agent Zero MCP client → point at `mcp-gateway`
5. In `#general`, ask Agent Zero to: create skill `linkedin_daily_digest`, schedule weekdays 08:00 ±15 min jitter, post results to `#leads`
6. Agent Zero stores the schedule in its own `scheduler.db`
7. Iterate criteria via Discord conversations; agent updates its memory
8. Curate the agent's LinkedIn account follows (~30 people, 10 hashtags, 10 companies) so feed yields lead-shaped content

### Daily routine the agent runs autonomously

~15–25 LinkedIn API calls/day, well under detection thresholds.

| Time | Action |
|---|---|
| 08:00 (jittered) | `get_feed` → judge → dedupe → post digest to `#leads` |
| 09–17 (ad-hoc) | `get_person_profile` / `search_people` from `#general` requests |
| 12:00 (jittered) | `get_company_posts` for 5 watched companies |
| 18:00 (jittered) | `get_inbox` summary |

## Growth path — linear, no architecture reshape

| Trigger | Add | Compose delta |
|---|---|---|
| Want post search precision | Fork stickerdaniel, add `search_posts` with LLM-based extraction (PR upstream re: issue #318), swap image tag in `custom.yaml` | none |
| Tool #2 (Twitter/X, GitHub watcher, calendar) | Entry in `custom.yaml`, `docker mcp server enable` | none |
| Plugin friction (need streaming progress, audit, custom UX) | Add separate `agent-zero-discord` bridge service alongside the plugin, or replace plugin with bridge | +1 service if added |
| First "build me code" task | `openhands` + its own Discord bot/integration, channels `#code`/`#projects` | +1–2 services |
| First need for sandboxed exec (untrusted scraping, data jobs) | `docker-socket-proxy`, dispatcher skill, worker images | +1 service (workers ephemeral) |
| Frequent cross-domain handoffs | `agent-bridge-mcp` (typed RPC, hop counter ≤ 1, audit logs) | none (new MCP server) |
| Want HTTPS / clean URLs | `caddy` reverse proxy | +1 service |

## Operational baseline

- **Spend caps**: hard daily $ cap at Anthropic, monitored in `#audit`
- **Backup**: nightly restic of `data/` + `secrets/` to remote (encryption password in personal 1Password — only one-way crossover)
- **Recovery**: one-line panic script revokes Discord bot token, rotates Anthropic key, kills compose
- **Audit channel**: every tool call logged before execution
- **Permission scoping**: Anthropic key has $ cap; Discord bot intents minimal; LinkedIn write tools disabled at gateway

## Source control

Infrastructure is version-controlled in a **private repo on the agent's GitHub account**. Code (compose, configs, skills, scripts) is committed; state (`secrets/`, `data/`, real `.env`) is gitignored. Restic handles state backup, git handles config history. Together they make disaster recovery `git clone + restic restore + docker compose up -d`.

Image tags are pinned (`:4.12.0`, not `:latest`) so the repo reproduces a known-working state at any commit.

Third-party plugin source (`a0-discord`) is documented in README rather than tracked as a submodule — clone instructions + pinned commit hash.

```
.gitignore:
  secrets/
  data/
  .env
  agent-zero/plugins/discord/   # third-party plugin source
  *.log
  .DS_Store
```

## Operator's daily / monthly burden

| Cadence | Action |
|---|---|
| Always | Docker Desktop running |
| On boot | `docker compose up -d` (auto-restart handles in-flight) |
| Per quarter | Re-login to LinkedIn (VNC into linkedin-mcp container or one-shot host login) |
| Per month | Glance at `#audit`, verify restic backup is restorable |
| Per key rotation | Update secrets file, restart agent-zero |
| Per new tool | Edit `custom.yaml`, `docker mcp server enable X` |

## Dev workflow (working on the agent's own tooling)

- SSH into Mac mini over Meshnet as the default user
- That user's git is configured globally with the agent's identity (name + email + SSH key)
- Public forks (e.g., `linkedin-mcp-server` for the eventual `search_posts` PR) live under the agent's GitHub account, cloned to `~/projects/`
- Build images locally, push to GHCR under the agent's account, swap image tag in `mcp-config/custom.yaml`
- Personal GitHub identity never touches this machine — separation is enforced at the GitHub layer, not at the macOS user layer

## Explicit non-goals — deferred or rejected

- Vault / Vaultwarden / 1Password integration — compose secrets sufficient
- OrbStack — Docker Desktop chosen
- VPN tunnel for outbound — hurts LinkedIn detection profile
- n8n — Agent Zero's scheduler covers it
- Postgres — file-based memory sufficient
- Inter-agent comms — manual handoff initially; bridge added when friction earns it
- Workers / dispatcher / socket-proxy — deferred until task #2+ needs sandboxed exec
- OpenHands — deferred until first code task
- Custom chrome-agent service — Patchright bundles it inside linkedin-mcp
- Custom build of LinkedIn MCP — use stickerdaniel; fork only when you need `search_posts`
- External cron — Agent Zero owns its schedule
- Free-form agent chat between Agent Zero and OpenHands — only typed RPC if/when added
- Custom Discord bridge service — using `spinnakergit/a0-discord` plugin instead; bridge added later only if plugin friction (streaming, audit, custom UX) earns it
- Caddy — deferred until clean URLs needed

---

**v0 is 2 compose services, one MCP server registered in the gateway catalog, one Discord plugin loaded into Agent Zero, one self-scheduled skill, one Discord channel that matters.** All capability growth happens via plugin (MCP server) or worker image — never by reshaping the architecture.
