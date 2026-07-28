#!/bin/sh
set -e

# Generate lore.json from template with env var defaults
# Uses env vars with defaults when template vars aren't substituted by docker

LORE_CHAT_MODEL="${LORE_CHAT_MODEL:-claude-3-5-sonnet}"
LORE_WORKER_MODEL="${LORE_WORKER_MODEL:-local-llama}"
LORE_DEBUG="${LORE_DEBUG:-true}"

# Substitute template placeholders
sed \
  -e "s|{{LORE_CHAT_MODEL}}|$LORE_CHAT_MODEL|g" \
  -e "s|{{LORE_WORKER_MODEL}}|$LORE_WORKER_MODEL|g" \
  -e "s|{{LORE_DEBUG}}|$LORE_DEBUG|g" \
  /etc/lore/lore.json.template > /etc/lore/lore.json

exec lore start --local --port 3207
