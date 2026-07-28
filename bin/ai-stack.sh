#!/usr/bin/env bash
set -euo pipefail

# ai-stack — Docker-based AI proxy stack
# Starts/shows logs/stops the stack via docker compose.

DIR="$(cd "$(dirname "$0")/.." && pwd)"
CMD="${1:-help}"

case "$CMD" in
  start|up)
    echo "🚀 Starting AI stack..."
    cd "$DIR" && docker compose up -d
    echo "☑  Stack is running"
    echo "   Lore    → http://localhost:3207"
    echo "   LiteLLM → http://localhost:4000"
    ;;
  stop|down)
    echo "⏹  Stopping AI stack..."
    cd "$DIR" && docker compose down
    echo "☑  Stack stopped"
    ;;
  restart)
    cd "$DIR" && docker compose restart
    echo "☑  Stack restarted"
    ;;
  logs)
    cd "$DIR" && docker compose logs -f
    ;;
  ps|status)
    cd "$DIR" && docker compose ps
    ;;
  update)
    cd "$DIR" && docker compose pull && docker compose up -d
    echo "☑  Stack updated"
    ;;
  setup-lat)
    if ! command -v lat &>/dev/null; then
      echo "  [install] lat.md via npm"
      npm install -g lat.md
    fi
    if [ ! -f "$PWD/lat.md/lat.md" ]; then
      echo "  [init] lat.md"
      (cd "$PWD" && lat init)
    fi
    echo "☑  lat.md ready"
    ;;
  help|*)
    echo "perfect-ai-stack — Docker-based AI proxy stack"
    echo ""
    echo "Usage: ai-stack <command>"
    echo ""
    echo "  start      Start all containers (docker compose up -d)"
    echo "  stop       Stop all containers (docker compose down)"
    echo "  restart    Restart all containers"
    echo "  logs       Follow combined logs"
    echo "  ps         Show container status"
    echo "  update     Pull latest images and recreate"
    echo "  setup-lat  Scaffold lat.md in current project"
    echo ""
    echo "Requires: docker, docker compose"
    echo "Config:   $DIR/config/"
    echo "Logs:     docker compose logs"
    ;;
esac
