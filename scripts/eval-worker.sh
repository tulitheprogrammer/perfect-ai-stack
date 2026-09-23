#!/usr/bin/env bash
# eval-worker — compare local models on Lore's curation task.
#
# Curation turns a conversation into durable `.lore.md` entries. Lore's docs
# put the practical floor at 32B+, so a small local worker is a real
# trade-off: this script lets you see the trade instead of guessing from
# parameter counts.
#
# Sends ONE fixed conversation to each model you name, through the gateway
# (so you get the real path: LiteLLM -> Ollama), and prints the raw output
# side by side. It does NOT write .lore.md or touch your DB — it is read-only
# and safe to re-run.
#
# Usage:
#   sh scripts/eval-worker.sh                       # all local models served
#   sh scripts/eval-worker.sh ministral-3:8b        # specific models
#   LORE_URL=http://localhost:3207 sh scripts/eval-worker.sh
#
# What to look for in the output:
#   - valid JSON (a small model often emits prose or trailing commentary)
#   - categories used correctly (decision vs preference vs gotcha)
#   - titles short and unique (duplicates are the documented 7B failure)
#   - no invented facts (hallucinated entries are worse than none)
#   - latin/emoji garbage or repetition loops = model not up to the task

set -eu

LORE_URL="${LORE_URL:-http://localhost:3207}"
TIMEOUT="${TIMEOUT:-300}"

# The curator's actual job, from Lore's bundle:
#   "You are a long-term memory curator. Your job is to extract durable
#    knowledge from a conversation that should persist across sessions."
# Categories match .lore.md: decision, pattern, preference, architecture, gotcha.
read -r -d '' SYSTEM <<'EOF' || true
You are a long-term memory curator. Your job is to extract durable knowledge from a conversation that should persist across sessions.

Extract only facts worth remembering. Categories: decision, pattern, preference, architecture, gotcha.

Return ONLY a JSON array. Each entry: {"category": "...", "title": "...", "content": "..."}
No prose, no markdown fences, no commentary.
EOF

read -r -d '' CONVO <<'EOF' || true
User: We're switching from npm to pnpm across all our repos. npm was creating duplicate lockfiles.
Assistant: Understood — I'll use pnpm from now on.
User: Also note that the auth service must never talk to the billing DB directly, only through the API gateway. We found this out when a migration broke production last month.
Assistant: Noted.
User: One more thing — always use `ruff` for Python linting, not flake8. The team standardised on it last quarter.
Assistant: Got it.
User: Oh, and the payments webhook times out if you don't set `Retry-After` on 429 responses. Cost us two hours of debugging.
Assistant: I'll remember that.
EOF

payload() {
  # Build JSON with python3 so quoting/escaping is not a shell hazard.
  SYSTEM="$SYSTEM" CONVO="$CONVO" MODEL="$1" python3 -c '
import json, os
print(json.dumps({
    "model": os.environ["MODEL"],
    "max_tokens": 900,
    "temperature": 0,
    "messages": [
        {"role": "system", "content": os.environ["SYSTEM"]},
        {"role": "user", "content": os.environ["CONVO"]},
    ],
}))'
}

models_to_test() {
  if [ "$#" -gt 0 ]; then
    printf '%s\n' "$@"
    return
  fi
  # Default: the local (Ollama-backed) models the gateway advertises.
  curl -sf --max-time 10 "$LORE_URL/v1/models" 2>/dev/null \
    | tr ',' '\n' | sed -n 's/.*"id":"\([^"]*\)".*/\1/p' \
    | grep -E ':(latest|[0-9]|8b|14b|16b|3b)|ministral|qwen|llama|deepseek-coder-v2' \
    || true
}

score() {
  # Heuristic, printed as a hint not a verdict: valid JSON + distinct titles.
  python3 - "$1" <<'PY'
import json, re, sys
raw = sys.argv[1]
# A transport/config failure is not a quality signal — say so plainly rather
# than reporting "did not follow the format", which misreads a 404 as a bad model.
if raw.startswith("ERROR:") or raw.startswith("[empty"):
    print("    (skipped — request failed, not a model-quality result)")
    sys.exit()
m = re.search(r"\[.*\]", raw, re.S)
if not m:
    print("    valid JSON: NO  (no array found — model did not follow the format)")
    sys.exit()
try:
    items = json.loads(m.group(0))
except Exception as e:
    print(f"    valid JSON: NO  ({e})")
    sys.exit()
titles = [str(i.get("title", "")).strip().lower() for i in items if isinstance(i, dict)]
cats = sorted({str(i.get("category", "")).strip() for i in items if isinstance(i, dict)})
dupes = len(titles) - len(set(titles))
print(f"    valid JSON: yes")
print(f"    entries:    {len(items)}")
print(f"    categories: {', '.join(cats) if cats else '(none)'}")
print(f"    dup titles: {dupes}" + ("  <-- duplicates are the documented small-model failure" if dupes else ""))
PY
}

check_gateway() {
  if ! curl -sf -o /dev/null --max-time 5 "$LORE_URL/v1/models"; then
    echo "  Gateway not reachable at $LORE_URL"
    echo "  Start it first:  sh bin/ai-stack.sh start"
    exit 1
  fi
}

main() {
  check_gateway
  local models
  models="$(models_to_test "$@")"
  if [ -z "$models" ]; then
    echo "  No models to test. Pass one explicitly, e.g.:"
    echo "    sh scripts/eval-worker.sh ministral-3:8b"
    exit 1
  fi

  echo "Curation eval — same conversation, one model at a time"
  echo "Gateway: $LORE_URL"
  echo ""
  echo "The conversation contains 5 durable facts to find:"
  echo "  1. preference  — pnpm over npm (why: duplicate lockfiles)"
  echo "  2. architecture— auth service must not touch billing DB directly"
  echo "  3. preference  — ruff not flake8"
  echo "  4. gotcha      — payments webhook needs Retry-After on 429"
  echo "  5. decision    — migration broke prod (context for #2)"
  echo ""

  # Only offer models that are both served by the gateway AND present in
  # Ollama; otherwise every run ends in a 404 that looks like model failure.
  local ollama_models
  ollama_models="$(curl -sf --max-time 5 http://localhost:11434/api/tags 2>/dev/null \
    | tr ',' '\n' | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' || true)"

  for m in $models; do
    printf '  %s\n' "=============================================================="
    printf '  MODEL: %s\n' "$m"
    printf '  %s\n' "=============================================================="
    if [ -n "$ollama_models" ] && ! printf '%s\n' "$ollama_models" | grep -qxF "$m"; then
      echo "      NOT PULLED in Ollama — run:  ollama pull $m"
      echo ""
      continue
    fi
    out="$(curl -s --max-time "$TIMEOUT" -X POST "$LORE_URL/v1/chat/completions" \
      -H "content-type: application/json" \
      -H "authorization: Bearer sk-eval" \
      -d "$(payload "$m")" 2>/dev/null \
      | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
except Exception:
    print("[empty or non-JSON response]"); sys.exit()
if "error" in d:
    print("ERROR: "+json.dumps(d["error"])[:300]); sys.exit()
ch=d.get("choices",[{}])[0].get("message",{})
# Thinking models put text in `reasoning` and leave content empty.
print(ch.get("content") or ch.get("reasoning") or "[empty content — thinking model with too small max_tokens?]")')"

    printf '  %s\n' "$out" | sed 's/^/    /'
    echo ""
    score "$out"
    echo ""
  done

  echo "  Now score it yourself: which entries would you approve in a PR?"
  echo "  Compare against Lore's floor (32B+ for full parity) and the"
  echo "  curator on/off decision in the README's Model selection section."
}

main "$@"
