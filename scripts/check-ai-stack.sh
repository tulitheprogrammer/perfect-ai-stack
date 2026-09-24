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
# 4. Shared worker model. Lore resolves the worker model as
#    LORE_WORKER_MODEL (env) > .lore.json workerModel > cost-aware default. One
#    container mounts one project at /app, so .lore.json's worker field is
#    invisible to every project except the mounted one — the env var is the only
#    channel that spans projects. write_shared_worker must therefore persist it
#    to the stack .env WITHOUT disturbing the user's other lines.
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

# ── 4: model list is not duplicated ─────────────────────────────────────────

# The menu renders the model table itself (scripts/select-model), so the printed
# list must be suppressed exactly when the menu will run. Both decisions read
# menu_supported(), so this checks the predicate agrees with select-model's own
# requirements: a tty on stdin AND stdout, plus bash for `read -rsn1`.
MS=$(sed -n '/^menu_supported()/,/^}$/p' bin/ai-stack.sh)
[ -n "$MS" ] || { echo "FAIL: could not locate menu_supported"; exit 1; }

dup_case() {
  # $1=label $2=expected  $3=stdin  $4=stdout  (each: tty|pipe)
  #
  # The predicate is `[ -t 0 ] && [ -t 1 ] && bash exists`. Rather than fake a
  # tty for the pipe cases (which cannot be done reliably from a script), run it
  # for real under `script` for the tty case, and under redirection for the pipe
  # cases — then assert the verdict.
  if [ "$3" = tty ] && [ "$4" = tty ]; then
    got=$(script -q /dev/null sh -c "printf '%s' 'MENU'
" >/dev/null 2>&1; \
          script -q /dev/null sh -c "MS='$MS'; eval \"\$MS\"; menu_supported && echo MENU || echo LIST" 2>/dev/null \
          | tr -d '\r' | grep -oE 'MENU|LIST' | head -1)
  else
    # stdin redirected => [ -t 0 ] is false => LIST, regardless of stdout.
    got=$(MS="$MS" sh -c 'eval "$MS"; menu_supported && echo MENU || echo LIST' \
          </dev/null 2>/dev/null | grep -oE 'MENU|LIST' | head -1)
  fi
  if [ "$got" = "$2" ]; then
    printf '  ok   %-30s -> %s\n' "$1" "$got"
  else
    printf '  FAIL %-30s -> %s expected %s\n' "$1" "$got" "$2"
    fails=$((fails + 1))
  fi
}

# A real terminal is the case where the list used to appear twice, so the menu
# must own the list there.
dup_case "interactive terminal"    MENU  tty  tty
# No tty on stdin means no menu, so the list MUST still print or the user sees
# no list at all.
dup_case "stdin piped"             LIST  pipe pipe
dup_case "stdin piped, stdout tty" LIST  pipe tty

# ── 5: the default model is defined once ────────────────────────────────────

# It used to appear as a literal in seven places that had to agree by hand.
# Assert one definition and no stray literals in code (comments may name it).
n=$(grep -cE '^DEFAULT_MODEL=' bin/ai-stack.sh)
if [ "$n" -eq 1 ]; then
  echo "  ok   DEFAULT_MODEL defined once"
else
  echo "  FAIL DEFAULT_MODEL defined $n times (expected 1)"
  fails=$((fails + 1))
fi

# Code lines (not comments) that still hardcode the default model name.
# show_models_help is exempt: it prints usage EXAMPLES, where a concrete model
# name is the point, and the example need not track the default.
default_name=$(sed -n 's/^DEFAULT_MODEL="\(.*\)"$/\1/p' bin/ai-stack.sh)
help_start=$(grep -n '^show_models_help()' bin/ai-stack.sh | cut -d: -f1)
help_end=$(awk -v s="$help_start" 'NR>s && /^}$/ {print NR; exit}' bin/ai-stack.sh)
stray=$(grep -nE "^[[:space:]]*[^#]*'?\"?${default_name}" bin/ai-stack.sh \
  | grep -v '^[0-9]*:DEFAULT_MODEL=' \
  | awk -F: -v a="$help_start" -v b="$help_end" '!($1 >= a && $1 <= b)' || true)
if [ -z "$stray" ]; then
  echo "  ok   no code path hardcodes the default model name"
else
  echo "  FAIL default model name still hardcoded in code:"
  printf '%s\n' "$stray" | sed 's/^/         /'
  fails=$((fails + 1))
fi

# ── 6: models writes the defaults, without clobbering a real selection ──────

# The display used to show a fallback name that was never persisted, so
# "Current selection" could name a model .lore.json did not contain.
case_tmp=$(mktemp -d)
trap 'rm -rf "$case_tmp"' EXIT
STACK_SH="$(pwd)/bin/ai-stack.sh"

( cd "$case_tmp" && sh "$STACK_SH" models >/dev/null 2>&1 </dev/null || true )
if [ -f "$case_tmp/.lore.json" ]; then
  echo "  ok   no .lore.json -> defaults written"
else
  # Only fail if the gateway is up; with it down there is no model list and
  # writing nothing is the documented outcome.
  if curl -sf -o /dev/null --max-time 3 http://localhost:3207/v1/models 2>/dev/null; then
    echo "  FAIL gateway is up but models wrote no .lore.json"
    fails=$((fails + 1))
  else
    echo "  skip gateway down — defaults not written by design"
  fi
fi

# An existing selection must survive a bare `models` run (the guard is
# [ ! -f "$cfg" ]); clobbering it would silently undo the user's choice.
if [ -f "$case_tmp/.lore.json" ]; then
  printf '{\n  "model":{"providerID":"openai","modelID":"deepseek-flash"},\n  "workerModel":{"providerID":"openai","modelID":"ministral-3:8b"},\n  "curator":{"enabled":false}\n}\n' \
    > "$case_tmp/.lore.json"
  ( cd "$case_tmp" && sh "$STACK_SH" models >/dev/null 2>&1 </dev/null || true )
  if grep -q 'deepseek-flash' "$case_tmp/.lore.json"; then
    echo "  ok   existing selection survives a bare models run"
  else
    echo "  FAIL bare models overwrote an existing selection"
    fails=$((fails + 1))
  fi
fi

# ── 4: shared worker model ─────────────────────────────────────────────────

# The migration is the risky part: the stack .env usually holds API keys, and a
# naive rewrite would drop them. Exercise the real function against a temp dir.
SW=$(sed -n '/^write_shared_worker()/,/^}$/p' bin/ai-stack.sh)
[ -n "$SW" ] || { echo "  FAIL could not locate write_shared_worker"; exit 1; }

sw_tmp=$(mktemp -d)
printf 'DEEPSEEK_API_KEY=sk-not-real\nLORE_WORKER_MODEL=openai/stale\n' > "$sw_tmp/.env"
node -e 'process.exit(0)' 2>/dev/null || true
(
  DIR="$sw_tmp"
  gateway_is_up() { return 1; }
  eval "$SW"
  write_shared_worker "qwen3:8b" >/dev/null 2>&1
) 2>/dev/null || true

if grep -q '^LORE_WORKER_MODEL=openai/qwen3:8b$' "$sw_tmp/.env"; then
  echo "  ok   worker model written to the stack .env"
else
  echo "  FAIL worker model not written (or wrong format)"
  fails=$((fails + 1))
fi

if grep -q '^DEEPSEEK_API_KEY=sk-not-real$' "$sw_tmp/.env"; then
  echo "  ok   existing .env lines preserved (keys survive)"
else
  echo "  FAIL existing .env lines were dropped"
  fails=$((fails + 1))
fi

n=$(grep -c '^LORE_WORKER_MODEL=' "$sw_tmp/.env")
if [ "$n" -eq 1 ]; then
  echo "  ok   exactly one LORE_WORKER_MODEL line (stale one replaced)"
else
  echo "  FAIL $n LORE_WORKER_MODEL lines (expected 1)"
  fails=$((fails + 1))
fi
rm -rf "$sw_tmp"

# The worker must be persisted somewhere the CONTAINER reads. .env in the stack
# dir is the only place Compose loads, so assert the function targets it rather
# than a per-project file.
if printf '%s\n' "$SW" | grep -q 'env_file="\$DIR/.env"'; then
  echo "  ok   writes to \$DIR/.env (the path Compose loads)"
else
  echo "  FAIL write_shared_worker does not target \$DIR/.env"
  fails=$((fails + 1))
fi

# Both mounts must exist: /app for the mounted project's files, and the real
# absolute path so a project-named request resolves in-container.
if grep -q '\${AI_STACK_PROJECT_DIR:-.}:\${AI_STACK_PROJECT_DIR:-/app}' docker-compose.yml; then
  echo "  ok   compose mounts the project at its real absolute path"
else
  echo "  FAIL compose does not mount \$AI_STACK_PROJECT_DIR at its own path"
  fails=$((fails + 1))
fi

echo ""
if [ "$fails" -eq 0 ]; then
  echo "PASS: wizard keys + menu + model advice + list dedup + defaults + shared worker (21 cases)"
else
  echo "FAIL: $fails case(s)"
  exit 1
fi
