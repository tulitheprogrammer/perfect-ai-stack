#!/bin/sh
# Checks the wizard's API-key handling in bin/ai-stack.sh.
#
# The logic is lifted out of the real function by line range, not copied, so a
# regression in bin/ai-stack.sh is what fails here. Run: sh scripts/check-wizard-keys.sh
#
# Two behaviors are guarded:
#
# 1. Detection. DEEPSEEK_API_KEY is canonical but OPENAI_API_KEY is a working
#    alias (docker-compose.yml sets both, each falling back to the other). A
#    legacy-only export must not be reported as "not set" — that both pushed a
#    DeepSeek-only user into an unnecessary prompt and offered to re-persist a
#    key that already worked.
# 2. The menu is always offered. `wizard` means "write me a .env", so it must not
#    exit before the menu just because every key is already exported. A key that
#    IS exported must never be copied into the file, or the file becomes a
#    second copy to keep in sync.
set -eu

cd "$(dirname "$0")/.."

# The block: MISSING="" through the prompt_var loop's closing brace.
start=$(grep -n '^  MISSING=""$' bin/ai-stack.sh | cut -d: -f1)
end=$(grep -n '^  prompt_var "DEEPSEEK_API_KEY"' bin/ai-stack.sh | cut -d: -f1)
[ -n "$start" ] && [ -n "$end" ] || { echo "FAIL: could not locate wizard key block (lines moved?)"; exit 1; }
# Back off from the prompt_var call to the real file path, then include it.
end=$((end + 1))
LOGIC=$(sed -n "${start},${end}p" bin/ai-stack.sh)
[ -n "$LOGIC" ] || { echo "FAIL: empty logic block"; exit 1; }

fails=0

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

echo ""
if [ "$fails" -eq 0 ]; then
  echo "PASS: wizard key detection + menu (6 cases)"
else
  echo "FAIL: $fails case(s)"
  exit 1
fi
