# `secrets/` — local-only secret files

This directory is gitignored. Each file is mounted as a Docker compose
secret at `/run/secrets/<name>` inside the container.

Permissions: every file in here MUST be `chmod 600` and owned by the
operator user. Compose will surface them read-only into the container.

## Required files

| File | Contents | Used by |
|---|---|---|
| `anthropic-key` | Raw Anthropic API key, no `Bearer`, no newline. Set a daily $ cap on the key in the Anthropic console. | Agent Zero LLM calls |
| `discord-az-token` | Discord bot token for the agent's Discord application. Grant only the intents the a0-discord plugin needs. | a0-discord plugin |

## Populate

```bash
# from the repo root
umask 077
printf '%s' "sk-ant-..." > secrets/anthropic-key
printf '%s' "DISCORD_BOT_TOKEN_HERE" > secrets/discord-az-token
chmod 600 secrets/*
```

`printf` (not `echo`) avoids the trailing newline that breaks some
clients.

## Rotation

Replace the file, then `docker compose restart agent-zero`. The plugin
re-reads the token on restart.

## Backup

`secrets/` is included in the nightly restic backup. The restic
encryption password is the only cross-over with the operator's personal
1Password — keep it there, never on this machine.
