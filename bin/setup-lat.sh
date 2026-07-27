#!/usr/bin/env bash
set -euo pipefail

# ── lat.md Scaffold — add lat.md to any project ────────────────────────────
# Part of @pluginizer/ai-stack. Delegates to the npm package copy for script,
# or can be copied standalone.
#
# Usage:
#   cd your-project
#   ai-stack setup-lat
#   # or standalone:
#   setup-lat.sh
# ────────────────────────────────────────────────────────────────────────────

PROJECT_ROOT="$(pwd)"
echo "📦 Setting up lat.md in $PROJECT_ROOT"

# ── Step 1: Install lat if missing ─────────────────────────────────────────
if ! command -v lat &>/dev/null; then
  echo "  [install] lat.md via npm"
  npm install -g lat.md
else
  echo "  ☑  lat already installed ($(lat --version 2>/dev/null || echo '?'))"
fi

# ── Step 2: Initialize ─────────────────────────────────────────────────────
if [ -d "$PROJECT_ROOT/lat.md" ]; then
  echo "  ⚠  lat.md/ already exists — skipping init"
else
  echo "  [init] lat.md/"
  lat init
fi

# ── Step 3: Pre-commit hook ────────────────────────────────────────────────
HOOK_FILE="$PROJECT_ROOT/.git/hooks/pre-commit"
if [ -f "$HOOK_FILE" ] && ! grep -q "lat check" "$HOOK_FILE" 2>/dev/null; then
  echo "  ⚠  pre-commit hook exists but doesn't run lat check — appending"
  echo "" >> "$HOOK_FILE"
  echo "# lat.md validation" >> "$HOOK_FILE"
  echo "exec lat check 2>&1" >> "$HOOK_FILE"
elif [ ! -f "$HOOK_FILE" ]; then
  echo "  [hook] installing pre-commit hook"
  mkdir -p "$(dirname "$HOOK_FILE")"
  cat > "$HOOK_FILE" << 'HOOK'
cp "$(dirname "$0")/../scripts/pre-commit-hook.sh" "$HOOK_FILE"
  chmod +x "$HOOK_FILE"
else
  echo "  ☑  pre-commit hook already runs lat check"
fi

# ── Step 4: .gitignore ─────────────────────────────────────────────────────
GITIGNORE="$PROJECT_ROOT/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if ! grep -q "lat.md/node_modules" "$GITIGNORE" 2>/dev/null; then
    echo "" >> "$GITIGNORE"
    echo "# lat.md cache" >> "$GITIGNORE"
    echo "lat.md/node_modules/" >> "$GITIGNORE"
    echo "  [gitignore] added lat.md/node_modules/"
  else
    echo "  ☑  .gitignore already covers lat.md/node_modules/"
  fi
fi

# ── Step 5: Verify ─────────────────────────────────────────────────────────
echo ""
echo "🔍 Running lat check..."
lat check && echo "" && echo "☑  lat.md is ready in $PROJECT_ROOT"
