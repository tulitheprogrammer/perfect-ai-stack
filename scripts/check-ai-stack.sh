#!/bin/sh
# Checks for bin/ai-stack.sh logic.
#
# Run: sh scripts/check-ai-stack.sh
#
# The blocks under test are lifted out of bin/ai-stack.sh by marker, not copied,
# so a regression in the real script is what fails here.
#
# Guarded behaviors:
#
# 1. Wizard key detection. DEEPSEEK_API_KEY is canonical but OPENAI_API_KEY is a
#    working alias (docker-compose.yml sets both, each falling back to the
#    other). A legacy-only export must not be reported as "not set" — that both
#    pushed a DeepSeek-only user into an unnecessary prompt and offered to
#    re-persist a key that already worked.
# 2. The wizard menu is always offered. `wizard` means "write me a .env", so it
#    must not exit before the menu just because every key is already exported. A
#    key that IS exported must never be copied into the file, or the file becomes
#    a second copy to keep in sync.
# 3. Model-availability advice. A model that is absent because it was RENAMED
#    must not be reported as "add it to config/litellm.yaml" — the config is
#    already correct, and that hint sends the user to edit the wrong thing.
set -eu

cd "$(dirname "$0")/.."

fails=0

# ── 1 + 2: wizard key handling ───────────────────────────────────────────────

# The block: MISSING="" through the prompt_var loop's closing brace.
start=$(grep -n '^  MISSING=""$' bin/ai-stack.sh | cut -d: -f1)
end=$(grep -n '^  prompt_var "DEEPSEEK_API_KEY"' bin/ai-stack.sh | cut -d: -f1)
[ -n "$start" ] && [ -n "$end" ] || { echo "FAIL: could not locate wizard key block (lines moved?)"; exit 1; }
# Back off from the prompt_var call to the real file path, then include it.
end=$((end + 1))
LOGIC=$(sed -n "${start},${end}p" bin/ai-stack.sh)
[ -n "$LOGIC" ] || { echo "FAIL: empty logic block"; exit 1; }

# $1=label $2=expected MISSING list $3=D $4=O $5=A
# stdout from the block is discarded (it is the user-facing report); the verdict
# is read from the MISSING list, which the block leaves in the environment.
run() {
  got=$(LOGIC="$LOGIC" D="$3" O="$4" A="$5" sh -c '
    DEEPSEEK_API_KEY="$D"; OPENAI_API_KEY="$O"; ANTHROPIC_API_KEY="$A"
    export DEEPSEEK_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY
    MISSING=""
    eval "$LOGIC" >/dev/null
    printf "%s" "${MISSING# }"
  ' 2>/dev/null)
  if [ "$got" = "$2" ]; then
    printf '  ok   %-28s missing=[%s]\n' "$1" "$got"
  else
    printf '  FAIL %-28s missing=[%s] expected=[%s]\n' "$1" "$got" "$2"
    fails=$((fails + 1))
  fi
}

run "both set"          ""                                   sk-d sk-o sk-a
run "deepseek only"     "ANTHROPIC_API_KEY"                  sk-d ""   ""
run "legacy alias only" "ANTHROPIC_API_KEY"                  ""   sk-o ""
run "neither set"       "ANTHROPIC_API_KEY DEEPSEEK_API_KEY" ""   ""   ""

# The menu must be reachable with every key set. The old code did `exit 0` in
# that branch, so `wizard` silently wrote nothing in exactly the case a user asks
# for a file. Tested by running the block (not by grepping the source): with all
# keys exported, execution must continue to the menu and print option 4. The
# `read` at the end is fed /dev/null so it EOFs instead of hanging.
run_menu() {
  got=$(LOGIC="$LOGIC" DEEPSEEK_API_KEY=sk-d OPENAI_API_KEY=sk-o ANTHROPIC_API_KEY=sk-a sh -c '
    export DEEPSEEK_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY
    MISSING=""
    eval "$LOGIC"
    printf "MARKER"
  ' </dev/null 2>/dev/null)
  if printf '%s' "$got" | grep -q '4) Do nothing' && printf '%s' "$got" | grep -q 'MARKER'; then
    echo "  ok   menu reached with all keys set (no early exit)"
  else
    echo "  FAIL all keys set exited before the menu (MARKER missing or no option 4)"
    fails=$((fails + 1))
  fi
  # And a key already in the environment must not be written into the file.
  if printf '%s' "$got" | grep -q 'DEEPSEEK_API_KEY is set (environment)'; then
    echo "  ok   exported key reported as env-supplied (not re-persisted)"
  else
    echo "  FAIL exported key was not recognised as already set"
    fails=$((fails + 1))
  fi
}
run_menu

# ── 3: model-availability advice ────────────────────────────────────────────

WHY=$(sed -n '/^model_in_config()/,/^}$/p;/^why_unavailable()/,/^}$/p' bin/ai-stack.sh)
[ -n "$WHY" ] || { echo "FAIL: could not locate model-availability helpers"; exit 1; }

# $1=label $2=expected substring $3=model name
advice() {
  got=$(DIR="$PWD" WHY="$WHY" M="$3" sh -c '
    eval "$WHY"
    why_unavailable "$M"
  ' 2>/dev/null)
  if printf '%s' "$got" | grep -qF "$2"; then
    printf '  ok   %-32s mentions: %s\n' "$1" "$2"
  else
    printf '  FAIL %-32s expected to mention: %s\n' "$1" "$2"
    printf '%s\n' "$got" | sed 's/^/         /'
    fails=$((fails + 1))
  fi
}

# A renamed model is still a valid name LiteLLM knows, so the config may be fine.
# The hint must send the user to re-select, not to edit config/litellm.yaml.
advice "renamed (the smoke case)"   "ai-stack models"        "deepseek-v4-flash"
# A model the config does define but the gateway is not serving needs a restart.
advice "defined but unserved"        "ai-stack restart"       "deepseek-v4-pro"
# A commented-out entry is not active, so it must not be reported as defined.
advice "commented-out entry"         "ai-stack models"        "llama3.1:8b"

# The renamed-model hint must NOT tell the user to edit the config.
bad=$(DIR="$PWD" WHY="$WHY" M="deepseek-v4-flash" sh -c 'eval "$WHY"; why_unavailable "$M"' 2>/dev/null)
if printf '%s' "$bad" | grep -q 'add it to config/litellm.yaml'; then
  echo "  FAIL renamed model still advised to edit config/litellm.yaml"
  fails=$((fails + 1))
else
  echo "  ok   renamed model is not advised to edit the config"
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "PASS: wizard keys + menu + model advice (10 cases)"
else
  echo "FAIL: $fails case(s)"
  exit 1
fi
