#!/bin/sh
# Register Discord channels with the a0-discord chat bridge.
# Idempotent: re-running just overwrites the same channel entries.
# Triggered automatically by the discord-init compose service after
# agent-zero becomes healthy; can also be invoked manually:
#   docker compose run --rm discord-init
#
# Reads from env (passed by compose via env_file: .env):
#   DISCORD_GUILD_ID         — required, the server (guild) ID
#   DISCORD_CHANNEL_<LABEL>  — one variable per channel; label is lowercase

set -eu

GUILD_ID="${DISCORD_GUILD_ID:-}"
if [ -z "$GUILD_ID" ]; then
  echo "register-channels: DISCORD_GUILD_ID not set; nothing to do" >&2
  exit 0
fi

# Compose's depends_on (condition: service_healthy) already gates this
# script on agent-zero being up. On a brand-new setup where the discord
# plugin hasn't been UI-installed yet, the docker exec returns
# ImportError and we skip cleanly — no separate wait needed.
for var in $(env | sed -n 's/^\(DISCORD_CHANNEL_[A-Z_]*\)=.*/\1/p'); do
  cid=$(env | sed -n "s/^${var}=//p")
  [ -z "$cid" ] && continue
  label=$(echo "$var" | sed 's/^DISCORD_CHANNEL_//' | tr '[:upper:]' '[:lower:]')

  echo "register-channels: $label ($cid)"
  docker exec agent-zero /opt/venv-a0/bin/python - <<PY
import sys
sys.path.insert(0, "/a0")
try:
    from usr.plugins.discord.helpers.discord_bot import add_chat_channel
    add_chat_channel("$cid", "$GUILD_ID", "$label")
    print("  registered")
except ImportError as e:
    print("  plugin not installed yet; skipping:", e)
PY
done
