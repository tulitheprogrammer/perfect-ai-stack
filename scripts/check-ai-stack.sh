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
# 5. Startup flags that only look like noise. Compose naming an unset optional
#    key, Lore flushing a Batch API LiteLLM does not serve, and `lore start
#    --local` turning off the container's hosted/remote-gateway defaults each
#    printed a warning that read as ambient but described a real fault.
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
#
# These cases run the REAL `models` command (a subprocess, so the whole script
# runs). write_model_choice also writes the shared worker to the stack .env,
# which is the developer's live config — snapshot and restore it, or running the
# checks silently rewrites their worker model.
case_tmp=$(mktemp -d)
env_backup="$case_tmp/.env.backup"
env_present=""
if [ -f .env ]; then
  env_present="1"
  cp .env "$env_backup"
fi
trap 'if [ -n "$env_present" ]; then cp "$env_backup" .env; else rm -f .env; fi; rm -rf "$case_tmp"' EXIT
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

# ── 7: the apply command carries the mount ─────────────────────────────────

# The env var only reaches the container on recreate, and compose resolves the
# :/app mount from AI_STACK_PROJECT_DIR — defaulting to '.' (the stack dir) when
# it is unset. A hint printed from the stack dir without that variable
# re-mounts the STACK at /app, so Lore reads no project .lore.json at all: the
# exact failure this whole area exists to prevent. Assert the apply command sets
# it, and that the hint names the container's stale value.
#
# docker is stubbed to answer `inspect --format` with a stale model, standing in
# for a running container that was never recreated.
hint_out=$(h_tmp=$(mktemp -d); printf 'K=1\n' > "$h_tmp/.env"; \
  DIR="$h_tmp";
  gateway_is_up() { return 0; };
  docker() { printf 'X\nLORE_WORKER_MODEL=openai/qwen3:8b\n'; };
  eval "$SW";
  write_shared_worker "ministral-3:8b" "/tmp/some-project";
  rm -rf "$h_tmp") 2>/dev/null || true

if printf '%s' "$hint_out" | grep -q "AI_STACK_PROJECT_DIR='/tmp/some-project'"; then
  echo "  ok   apply command pins AI_STACK_PROJECT_DIR (mount stays correct)"
else
  echo "  FAIL apply command omits AI_STACK_PROJECT_DIR — would mount the stack dir"
  printf '%s\n' "$hint_out" | sed 's/^/         /'
  fails=$((fails + 1))
fi

if printf '%s' "$hint_out" | grep -q 'running with LORE_WORKER_MODEL=openai/qwen3:8b'; then
  echo "  ok   stale container detected (baked value named in the hint)"
else
  echo "  FAIL did not report the running container's stale value"
  fails=$((fails + 1))
fi

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

# ── 9: startup noise that was a stack fault, not a harmless warning ─────────

# Each of these printed on every start / every distillation flush and looked like
# ambient noise, which is exactly why they must not come back: the batch one was
# retrying a request that can never succeed (and addressing it at api.openai.com
# on a local-first stack), and the ANTHROPIC one warned about a key the default
# Ollama-only setup has no reason to own.

# `environment: - ANTHROPIC_API_KEY` (no =) passes the host value through only
# when it is set. The `=${ANTHROPIC_API_KEY}` form names an unset variable, which
# is what makes Compose warn on every start.
if grep -qE '^[[:space:]]*-[[:space:]]*ANTHROPIC_API_KEY[[:space:]]*$' docker-compose.yml; then
  echo "  ok   ANTHROPIC_API_KEY passed through without interpolation"
else
  echo "  FAIL ANTHROPIC_API_KEY is interpolated — Compose warns on every start"
  fails=$((fails + 1))
fi

# LORE_BATCH_DISABLED must be the STRING "1". The gateway compares with strict
# equality in three places:
#   process.env.LORE_BATCH_DISABLED === "1"
# so "true" is silently falsy and the batch path stays enabled — LiteLLM serves no
# batch endpoint, its inline fallback then rebuilds the worker call from the
# SESSION's provider, and lore-distill degrades to a stop. The startup banner
# reports the failing case as `(current: false)`, which is this comparison, not a
# missing flag.
if grep -qE '^[[:space:]]*-[[:space:]]*LORE_BATCH_DISABLED=1$' docker-compose.yml; then
  echo "  ok   LORE_BATCH_DISABLED=1 (string form the gateway compares against)"
else
  echo "  FAIL LORE_BATCH_DISABLED is not =1 — 'true' is silently falsy (strict ===)"
  fails=$((fails + 1))
fi

# The batch path is what silently swaps the worker model: its inline fallback
# rebuilds the call from the SESSION's provider. Observed: a configured
# ministral-3:8b worker became anthropic/claude-sonnet-4-6 (400, model not served)
# and qwen3:8b. Those rows are in distillations.call_type='batch'.
# Lore must reach LiteLLM over the same chat endpoint the session uses, with a
# provider ID it can resolve, or the batch/flush path has no valid target.
if grep -qE 'LORE_WORKER_UPSTREAM=.*http://litellm:4000' docker-compose.yml; then
  echo "  ok   worker upstream points at LiteLLM (bare root, no /v1)"
else
  echo "  FAIL worker upstream is not http://litellm:4000"
  fails=$((fails + 1))
fi

# LORE_WORKER_MODEL is the HIGHEST-priority worker source: the resolver parses it
# and returns before the config file is consulted. The `/` is load-bearing — a
# value with no slash is read as an ANTHROPIC model:
#
#   function $be(e) {
#     let t = e.indexOf("/");
#     return t > 0 ? { providerID: e.slice(0,t), modelID: e.slice(t+1) }
#                  : { providerID: "anthropic", modelID: e };   // no slash
#   }
#
# which against this stack's LiteLLM 400s on /v1/messages naming a model like
# claude-sonnet-4-6 ("Invalid model name passed in"). So every value here must
# carry an openai/ prefix. Absent .env is fine: the compose default applies.
if [ ! -f .env ] || grep -qE '^LORE_WORKER_MODEL=openai/[^/]+$' .env; then
  echo "  ok   LORE_WORKER_MODEL is openai/<model> (slash present, right protocol)"
else
  echo "  FAIL LORE_WORKER_MODEL is not openai/<model> — a slashless value parses as anthropic"
  fails=$((fails + 1))
fi

# A bare model name is the specific mistake that yields the claude-sonnet-4-6
# symptom, so assert it is rejected rather than merely discouraged.
if grep -qE '^LORE_WORKER_MODEL=[^/]+$' .env 2>/dev/null; then
  echo "  FAIL LORE_WORKER_MODEL has no provider prefix -> parsed as anthropic"
  fails=$((fails + 1))
else
  echo "  ok   no slashless LORE_WORKER_MODEL (would resolve to an anthropic model)"
fi

# `lore start` defaults to hosted + remote-gateway mode, which is what a
# containerised gateway needs (its /app is a bind mount). --local flips both off,
# so every session logs remoteGateway=false / hosted=false and memory has no
# project signal — the exact state `lore run` and the X-Lore-Project header exist
# to prevent.
if grep -qE '^CMD \["lore", "start", "--port"' Dockerfile; then
  echo "  ok   gateway starts in its hosted/remote-gateway defaults (no --local)"
else
  echo "  FAIL Dockerfile passes --local (or changed the start flags) — remote/hosted mode off"
  fails=$((fails + 1))
fi

# ── 8: the worker can actually answer ─────────────────────────────────────

# qwen3:8b is a thinking model, and LiteLLM drops Ollama's reasoning channel:
# when thinking consumes the response the caller gets HTTP 200 with
# finish_reason=stop and content:"", which Lore logs as
#   worker empty response ... finish_reason=stop
# and "lore-distill failed (no-response)" — distillation stops silently, with
# no error the user ever sees. config/litellm.yaml pins `think: false` on the
# qwen3:8b entry to prevent exactly that.
#
# A prompt that invites long deliberation is what makes the difference, so that
# is what this sends: with thinking disabled the model answers inside the
# budget; with it enabled the same budget is spent thinking and content comes
# back empty. Asserting non-empty content is enough to catch a removed
# `think: false`, and it is the real request path (gateway -> LiteLLM ->
# Ollama), not a grep of the config.
#
# Skipped when the gateway is down — there is nothing to ask, the same rule the
# defaults check above uses.
if curl -sf -o /dev/null --max-time 3 http://localhost:3207/v1/models 2>/dev/null; then
  payload='{"model":"qwen3:8b","max_tokens":250,"temperature":0,"messages":[{"role":"system","content":"Think step by step about each fact at length, weighing alternatives and explaining your reasoning in detail. Then return ONLY a JSON array."},{"role":"user","content":"User: We switched from npm to pnpm; npm created duplicate lockfiles.\nAssistant: Understood.\nUser: The auth service must never talk to the billing DB directly, only through the gateway.\nAssistant: Noted."}]}'
  resp=$(curl -s --max-time 180 -X POST http://localhost:3207/v1/chat/completions \
    -H 'content-type: application/json' -H 'authorization: Bearer sk-check' \
    -d "$payload" 2>/dev/null || true)
  if printf '%s' "$resp" | grep -q '"content":"[^"]'; then
    echo "  ok   qwen3:8b answers with non-empty content (thinking disabled)"
  else
    echo "  FAIL qwen3:8b returned empty content — worker would log 'no-response'"
    printf '%s\n' "$resp" | cut -c1-200 | sed 's/^/         /'
    fails=$((fails + 1))
  fi
else
  echo "  skip gateway down — the worker answer check needs the gateway"
fi

# ── 10: shared model config reaches the container ───────────────────────────

# The gateway reads `<projectDir>/.lore.json` via a loader that parses an EMPTY
# object when the file is absent:
#
#   async function qC(e) {
#     let t = join(e, ".lore.json")
#     if (existsSync(t)) return eB = Kpe.parse(JSON.parse(strip(t)))
#     return eB = Kpe.parse({})          // no file -> {}
#   }
#
# and the session model then takes a HARDCODED fallback:
#
#   Xe().model ?? { providerID: "anthropic", modelID: "claude-sonnet-4-6" }
#
# LiteLLM serves no claude-sonnet-4-6 here, so a missing .lore.json at /app 400s
# every session-model resolution. One container has one /app, so with a shared
# gateway the file must be mounted rather than written per project.
if grep -qE '^[[:space:]]*-[[:space:]]*\./config/lore\.json:/app/\.lore\.json' docker-compose.yml; then
  echo "  ok   shared .lore.json mounted at /app (spans every project)"
else
  echo "  FAIL no shared .lore.json mount — missing file falls back to hardcoded claude-sonnet-4-6"
  fails=$((fails + 1))
fi

# Mount order is load-bearing: a bind mount is a directory overlay, so the file
# mount must come AFTER the project's /app mount or the project's own (possibly
# absent) .lore.json shadows it and the fallback returns.
app_line=$(grep -nE '^[[:space:]]*-[[:space:]]*\$\{AI_STACK_PROJECT_DIR:-[^}]*\}:/app[[:space:]]*$' docker-compose.yml | head -1 | cut -d: -f1)
lore_line=$(grep -nE '^[[:space:]]*-[[:space:]]*\./config/lore\.json:/app/\.lore\.json' docker-compose.yml | head -1 | cut -d: -f1)
if [ -n "$app_line" ] && [ -n "$lore_line" ] && [ "$lore_line" -gt "$app_line" ]; then
  echo "  ok   shared config is layered after the /app mount (overlay wins)"
else
  echo "  FAIL shared .lore.json is not layered after the /app mount (app=$app_line lore=$lore_line)"
  fails=$((fails + 1))
fi

# The shared config must name a model this stack actually serves, and providerID
# must be openai/ (the protocol LiteLLM answers). A claude-* name here is the
# documented cause of "Invalid model name passed in model=...".
if [ -f config/lore.json ]; then
  if node -e '
    const c = JSON.parse(require("fs").readFileSync("config/lore.json", "utf8"));
    const m = c.model || {}, w = c.workerModel || {};
    if (!m.modelID || !w.modelID) throw new Error("model/workerModel missing");
    if (m.providerID !== "openai" || w.providerID !== "openai")
      throw new Error("providerID must be openai");
    for (const v of [m.modelID, w.modelID])
      if (/^(claude|anthropic)/.test(v)) throw new Error("anthropic model " + v);
  ' 2>/dev/null; then
    echo "  ok   config/lore.json names served models on the openai provider"
  else
    echo "  FAIL config/lore.json is missing, malformed, or names an unserved/anthropic model"
    fails=$((fails + 1))
  fi
else
  echo "  FAIL config/lore.json does not exist (the compose mount would fail)"
  fails=$((fails + 1))
fi

# ── 11: `ai-stack models` writes the file the container reads ───────────────

# The project's own .lore.json is shadowed by the shared /app/.lore.json mount, so
# writing only there would look correct and change nothing. Exercise the real
# function against a temp stack dir and assert both files land.
WS=$(sed -n '/^write_shared_config()/,/^}$/p' bin/ai-stack.sh)
[ -n "$WS" ] || { echo "  FAIL could not locate write_shared_config"; exit 1; }

ws_tmp=$(mktemp -d)
mkdir -p "$ws_tmp/config"
(
  DIR="$ws_tmp"
  eval "$WS"
  write_shared_config "deepseek-flash" "ministral-3:8b"
) >/dev/null 2>&1 || true

if node -e '
  const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  if (c.model.modelID !== "deepseek-flash") throw 0;
  if (c.workerModel.modelID !== "ministral-3:8b") throw 0;
  if (c.model.providerID !== "openai") throw 0;
' "$ws_tmp/config/lore.json" 2>/dev/null; then
  echo "  ok   write_shared_config writes model+workerModel for the container"
else
  echo "  FAIL write_shared_config did not produce a parsable shared config"
  fails=$((fails + 1))
fi

# Unrelated keys must survive a re-run, or editing models would wipe curation
# settings and anything else a user added.
node -e '
  const fs = require("fs");
  const p = process.argv[1];
  const c = JSON.parse(fs.readFileSync(p, "utf8"));
  c.knowledge = { enabled: false };
  fs.writeFileSync(p, JSON.stringify(c, null, 2));
' "$ws_tmp/config/lore.json"
(
  DIR="$ws_tmp"
  eval "$WS"
  write_shared_config "qwen3:8b" "qwen3:8b"
) >/dev/null 2>&1 || true

if node -e '
  const c = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  if (c.model.modelID !== "qwen3:8b") throw 0;
  if (!c.knowledge || c.knowledge.enabled !== false) throw 0;
' "$ws_tmp/config/lore.json" 2>/dev/null; then
  echo "  ok   shared config keeps unrelated keys across a model change"
else
  echo "  FAIL write_shared_config clobbered unrelated keys"
  fails=$((fails + 1))
fi

# Both writers must be wired into write_model_choice, or `ai-stack models` updates
# one channel and leaves the other stale, which reads as "my change did nothing".
if sed -n '/^write_model_choice()/,/^}$/p' bin/ai-stack.sh | grep -q 'write_shared_config'; then
  echo "  ok   models writes the shared config (not only the shadowed project file)"
else
  echo "  FAIL write_model_choice never calls write_shared_config"
  fails=$((fails + 1))
fi
rm -rf "$ws_tmp"

echo ""
if [ "$fails" -eq 0 ]; then
  echo "PASS: wizard keys + menu + model advice + list dedup + defaults + shared worker + mount + startup flags + shared config + models-write + worker answer (38 cases)"
else
  echo "FAIL: $fails case(s)"
  exit 1
fi
