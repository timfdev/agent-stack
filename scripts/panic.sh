#!/usr/bin/env bash
# Kill switch. Stops the stack, removes the local Discord token so the bot
# cannot reconnect, and reminds you to rotate the Anthropic key.
#
# Run from the repo root:  ./scripts/panic.sh

set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Stopping compose stack"
docker compose down

if [[ -f secrets/discord-az-token ]]; then
  echo "==> Moving Discord token aside (./secrets/discord-az-token.revoked-$(date +%s))"
  mv secrets/discord-az-token "secrets/discord-az-token.revoked-$(date +%s)"
fi

cat <<'EOF'

==> Manual follow-ups (do these NOW):
    1. Discord developer portal → Bot → Reset Token
       https://discord.com/developers/applications
    2. Anthropic console → API keys → Revoke the agent key
       https://console.anthropic.com/settings/keys
    3. Once new credentials are issued, write them back into secrets/
       and `docker compose up -d` to bring the stack back.

EOF
