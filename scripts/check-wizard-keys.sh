#!/bin/sh
# Checks the wizard's API-key detection in bin/ai-stack.sh.
#
# The logic is lifted out of the real function by line range, not copied, so a
# regression in bin/ai-stack.sh is what fails here. Run: sh scripts/check-wizard-keys.sh
#
# The bug this guards against: DEEPSEEK_API_KEY is canonical but OPENAI_API_KEY
# is a working alias (docker-compose.yml sets both, each falling back to the
# other). A legacy-only export was reported as "not set", which both pushed a
# DeepSeek-only user into an unnecessary prompt and offered to re-persist a key
# that already worked.
set -eu

cd "$(dirname "$0")/.."

# The block: MISSING="" through the "All set" early exit.
start=$(grep -n '^  MISSING=""$' bin/ai-stack.sh | cut -d: -f1)
end=$(grep -n '^  fi$' bin/ai-stack.sh | awk -F: -v s="$start" '$1 > s {print $1; exit}')
LOGIC=$(sed -n "${start},${end}p" bin/ai-stack.sh)
[ -n "$LOGIC" ] || { echo "FAIL: could not locate wizard key block (lines moved?)"; exit 1; }

fails=0

# $1=label $2=expected MISSING list $3=D $4=O $5=A
# stdout from the block is discarded (it is the user-facing report); the verdict
# is read from the MISSING list, which the block prints as a final marker.
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

echo ""
if [ "$fails" -eq 0 ]; then
  echo "PASS: wizard key detection (4 cases)"
else
  echo "FAIL: $fails case(s)"
  exit 1
fi
