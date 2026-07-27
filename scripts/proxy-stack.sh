#!/usr/bin/env bash
set -euo pipefail

# ── Proxy Stack Launcher ──────────────────────────────────────────────────
# Part of @pluginizer/ai-stack. Run via `ai-stack start|stop|logs`.
# ───────────────────────────────────────────────────────────────────────────

# Resolve config dir: set by bin/ai-stack.sh, or default
AI_CONFIG_DIR="${AI_STACK_DIR:-$HOME/.config/ai-stack}"
AI_DATA_DIR="${AI_STACK_DATA:-$HOME/.local/share/ai-stack}"
LOGS_DIR="$AI_DATA_DIR/logs"
mkdir -p "$LOGS_DIR"

PORTS_NAMES=(lore litellm headroom)
PORTS_VALUES=(3207 4000 8787)

kill_stale() {
  local port=$1 name=$2
  local pids
  pids=$(lsof -ti ":$port" 2>/dev/null || true)
  if [ -n "$pids" ]; then
    echo "  [kill] stale $name (PIDs $pids on :$port)"
    kill $pids 2>/dev/null || true
    for i in $(seq 1 10); do
      if ! lsof -ti ":$port" >/dev/null 2>&1; then
        break
      fi
      sleep 0.2
    done
  fi
}

cleanup() {
  echo ""
  echo "⏹  Shutting down AI stack..."
  for (( _i=0; _i<${#PORTS_NAMES[@]}; _i++ )); do
    local name="${PORTS_NAMES[$_i]}" port="${PORTS_VALUES[$_i]}"
    local pids
    pids=$(lsof -ti ":$port" 2>/dev/null || true)
    if [ -n "$pids" ]; then
      echo "  [stop] $name (PIDs $pids)"
      kill $pids 2>/dev/null || true
    fi
  done
  wait 2>/dev/null || true
  echo "☑  All services stopped."
  exit 0
}

stop_all() { cleanup; exit 0; }

follow_logs() {
  if command -v multitail >/dev/null 2>&1; then
    exec multitail "$LOGS_DIR"/lore.log "$LOGS_DIR"/headroom.log "$LOGS_DIR"/litellm.log
  else
    echo "-- Lore Gateway ----------------------"
    tail -f "$LOGS_DIR/lore.log" &
    echo "-- LiteLLM --------------------------"
    tail -f "$LOGS_DIR/litellm.log" &
    echo "-- Headroom --------------------------"
    exec tail -f "$LOGS_DIR/headroom.log"
  fi
}

trap cleanup SIGINT SIGTERM EXIT

case "${1:-start}" in
  stop)  stop_all ;;
  logs)  follow_logs ;;
  start|*)
    echo "🚀 Starting AI stack..."
    for (( _i=0; _i<${#PORTS_NAMES[@]}; _i++ )); do
      kill_stale "${PORTS_VALUES[$_i]}" "${PORTS_NAMES[$_i]}"
    done

    echo "  [start] LiteLLM Proxy (port 4000)"
    litellm --config "$AI_CONFIG_DIR/config/litellm.yaml" > "$LOGS_DIR/litellm.log" 2>&1 &
    echo $! > "$LOGS_DIR/litellm.pid"

    echo "  [start] Headroom AI Proxy (port 8787)"
    headroom proxy --openai-api-url http://localhost:4000/v1 --no-memory-context > "$LOGS_DIR/headroom.log" 2>&1 &
    echo $! > "$LOGS_DIR/headroom.pid"

    echo "  [start] Lore AI Gateway (port 3207)"
    lore start --local --bg > "$LOGS_DIR/lore.log" 2>&1 &
    echo $! > "$LOGS_DIR/lore.pid"

    sleep 2
    for (( _i=0; _i<${#PORTS_NAMES[@]}; _i++ )); do
      name="${PORTS_NAMES[$_i]}" port="${PORTS_VALUES[$_i]}"
      if lsof -ti ":$port" >/dev/null 2>&1; then
        echo "  ☑  $name is up on :$port"
      else
        echo "  ⚠  $name NOT running (check $LOGS_DIR/$name.log)"
      fi
    done

    echo ""
    echo "All services running. Logs in $LOGS_DIR/"
    echo "  Follow: ai-stack logs"
    echo "  Stop:   ai-stack stop"
    echo ""
    wait
    ;;
esac
