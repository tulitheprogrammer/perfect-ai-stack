#!/usr/bin/env bash
set -euo pipefail

# ── ai-stack — shared AI proxy stack for all your projects ─────────────────
# Installed via npm as @pluginizer/ai-stack.
#
# Usage:
#   ai-stack init          # copy config + scripts to ~/.config/ai-stack/
#   ai-stack start         # start all proxies
#   ai-stack stop          # stop all
#   ai-stack logs          # follow all logs
#   ai-stack setup-lat     # scaffold lat.md in current project
# ────────────────────────────────────────────────────────────────────────────

NPM_PACKAGE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AI_CONFIG_DIR="${AI_STACK_DIR:-$HOME/.config/ai-stack}"
AI_DATA_DIR="${AI_STACK_DATA:-$HOME/.local/share/ai-stack}"

cmd_init() {
  if [ -d "$AI_CONFIG_DIR" ]; then
    echo "⚠  $AI_CONFIG_DIR already exists — overwrite? [y/N]"
    read -r answer
    [ "$answer" != "y" ] && echo "aborted" && exit 1
  fi
  mkdir -p "$AI_CONFIG_DIR"/scripts "$AI_CONFIG_DIR"/config
  cp "$NPM_PACKAGE_DIR"/config/*.yaml "$AI_CONFIG_DIR/config/" 2>/dev/null || true
  cp "$NPM_PACKAGE_DIR"/scripts/*.sh "$AI_CONFIG_DIR/scripts/" 2>/dev/null || true
  chmod +x "$AI_CONFIG_DIR"/scripts/*.sh 2>/dev/null || true
  echo "☑  AI stack config installed to $AI_CONFIG_DIR"
  echo "   Config:    $AI_CONFIG_DIR/config/litellm.yaml"
  echo "   Scripts:   $AI_CONFIG_DIR/scripts/proxy-stack.sh"
  echo "   Data dir:  $AI_DATA_DIR"
  echo ""
  echo "   Start:     ai-stack start"
  echo "   Stop:      ai-stack stop"
  echo "   Logs:      ai-stack logs"
}

cmd_install() {
  cmd_init
}

cmd_start() {
  exec "$AI_CONFIG_DIR/scripts/proxy-stack.sh" start
}

cmd_stop() {
  exec "$AI_CONFIG_DIR/scripts/proxy-stack.sh" stop
}

cmd_logs() {
  exec "$AI_CONFIG_DIR/scripts/proxy-stack.sh" logs
}

cmd_setup_lat() {
  exec "$AI_CONFIG_DIR/scripts/setup-lat.sh"
}

case "${1:-help}" in
  init|install)
    cmd_init
    ;;
  start)
    cmd_start
    ;;
  stop)
    cmd_stop
    ;;
  logs)
    cmd_logs
    ;;
  setup-lat)
    cmd_setup_lat
    ;;
  help|--help|-h)
    echo "ai-stack — shared AI proxy stack"
    echo ""
    echo "Usage:  ai-stack <command>"
    echo ""
    echo "  init         Copy config + scripts to ~/.config/ai-stack/"
    echo "  start        Start all proxies (Lore, LiteLLM, Headroom)"
    echo "  stop         Stop all proxies"
    echo "  logs         Follow combined logs"
    echo "  setup-lat    Scaffold lat.md in current project"
    echo "  help         Show this help"
    ;;
  *)
    echo "Unknown command: $1"
    echo "Run 'ai-stack help' for usage."
    exit 1
    ;;
esac
