# perfect-ai-stack

**AI proxy stack**
LiteLLM (with Headroom compression sidecar)

- Lore in Docker,
- per-repo lat.md knowledge graph scaffolded git-hook enforcement.

```
// e.g using Zed IDE
Zed -> Lore (:3207) -> LiteLLM + Headroom (:4000) -> DeepSeek / Anthropic / OpenAI / Ollama (host)
```

## Install

One command, from your project:

```sh
cd ~/code/your-project
npx perfect-ai-stack init
```

`init` starts the gateway, scaffolds `lat.md/` + the pre-commit hook, and
prints the IDE config to use. Safe to re-run;
if the gateway is already up it, skips startup instead of restarting it.
Requires Docker Desktop (see [Prerequisites](#prerequisites)).

`npx` installs the package into npm's cache and runs `bin/ai-stack.sh` from
there.
Project files (`.env`, `lat.md/`, git hooks) always land in the project
you run it from.

Keep the memory DB and Headroom cache out of the npx cache dir, so they survive upgrades:

```sh
export AI_STACK_DATA_DIR=~/.ai-stack      # Lore DB + Headroom cache (shared across projects)
```

Working on the stack itself? Clone it and see
[Development](#development) — `sh bin/ai-stack.sh init` behaves identically.

## Prerequisites

**Docker Desktop, installed and running.**
That's the only requirement — no API keys needed to try it (local models run through Ollama).

```sh
open -a Docker      # macOS; wait for the whale icon to stop animating
```

`init` checks this and tells you exactly what's missing if it isn't there.

## Quick start

Three steps, in order. Do them all before touching your IDE.

### 1. Start the gateway

From any existing project:

```sh
npx perfect-ai-stack init
```

This starts the gateway, asks for your session + worker models (press Enter for
the defaults), scaffolds `lat.md/` + the pre-commit hook in your project, and
prints the config you'll need in step 3. First run pulls the LiteLLM image and
builds both containers — allow a few minutes. The first model request also
downloads Headroom's compression model (~275 MB), cached once in
`data/headroom/`.

### 2. Pull a local model

The default model is `qwen3:8b`, served by **Ollama on your host** — not inside
Docker. If Ollama isn't running, or the model isn't pulled, requests fail with
`Invalid model name passed in model=qwen3:8b` even though the gateway is
healthy. So:

```sh
brew install ollama && brew services start ollama   # or: ollama serve
ollama pull qwen3:8b
```

Prefer a cloud model instead? Put `OPENAI_API_KEY` in your environment and use
`deepseek-v4-flash` as the model name. You still need Ollama only if you want a
local worker (recommended — see [Model selection](#model-selection)).

Verify both halves before continuing:

```sh
curl -s http://localhost:11434/api/tags   # Ollama up, and qwen3:8b listed
curl -s http://localhost:3207/v1/models   # gateway up, models listed
```

### 3. Point your IDE at it

```
Base URL:  http://localhost:3207/v1
API key:   any non-empty string (auth is off on this local stack)
Model:     qwen3:8b            (free, local via Ollama)
           deepseek-v4-flash   (needs OPENAI_API_KEY)
```

No IDE config to write: the same endpoint works for Zed, Cursor, VS Code
(Continue), and anything else that takes a custom base URL. Send one message to
confirm, then check the log for `POST /v1/chat/completions ... 200`:

```sh
cd /path/to/perfect-ai-stack && docker compose logs litellm --tail 5
```

> **Heads up: `qwen3:8b` is a _thinking_ model.** It writes its reasoning first,
> so on a short `max_tokens` (anything under a few hundred) you get `200 OK`
> with **empty content** — the budget was spent on reasoning. If a reply comes
> back blank, raise `max_tokens` in your client, or prefix the message with
> `/no_think` to skip reasoning. Your IDE's default limit is usually fine.

That's it — you're running. Optional next steps: [choose your models](#model-selection),
wire up the [knowledge graph over MCP](#knowledge-graph-access-mcp), or read
[Architecture](#architecture) to see what just happened.

**Already using a tool with built-in memory or context compression?** Read
[Choosing what to use](#choosing-what-to-use) before pointing it here — for
Claude Code and Copilot you likely want only part of this stack.

> **Ran Lore on the host before?** Clear the stale env vars first — they
> override the compose defaults and point inside the container at nothing.
>
> ```sh
> unset LORE_UPSTREAM_OPENAI LORE_UPSTREAM_ANTHROPIC LORE_WORKER_UPSTREAM LORE_WORKER_MODEL LORE_WORKER_API_KEY
> ```

## Choosing what to use

Some clients already ship memory and context compression. Pointing this stack
at them can duplicate work or fight the built-in behaviour, so pick per tool:

| Your client                              | Already has                                            | Use from this stack     | Why                                                                                                             |
| ---------------------------------------- | ------------------------------------------------------ | ----------------------- | --------------------------------------------------------------------------------------------------------------- |
| **Claude Code**                          | Auto-compaction, `CLAUDE.md` memory                    | ✅ `lat.md` + hook only | Skip Lore — it's also an Anthropic-protocol proxy and its distillation overlaps compaction                      |
| **GitHub Copilot** (VS Code / JetBrains) | Repo-aware indexing; **BYOK base URL is very limited** | ⚠️ `lat.md` + hook only | Copilot generally can't take a custom `OPENAI_BASE_URL`; point Continue at the gateway instead if you want Lore |
| **Cursor**                               | Built-in codebase index + rules                        | ✅ Full stack           | Its index is code-retrieval, not decision/error memory — no overlap with Lore                                   |
| **Zed**                                  | Nothing built-in                                       | ✅ Full stack           | The reference client                                                                                            |
| **Continue / Cline / Aider**             | Nothing built-in                                       | ✅ Full stack           | Plain BYOK OpenAI clients                                                                                       |
| **OpenCode / Pi**                        | Nothing built-in                                       | ✅ Full stack           | `lore run` auto-configures these natively                                                                       |

Rule of thumb: **`lat.md` never conflicts** — it's a plain markdown knowledge
graph, and Lore indexes it automatically when present. The parts worth being
selective about are **Lore** (memory) and **Headroom** (token compression),
both of which overlap what Claude Code and Copilot already do natively.

### Add only the knowledge graph (no Docker)

If you want the `lat.md` workflow without the gateway:

```sh
npm i -g lat.md
cd your-project && lat init          # creates lat.md/, wires agents
lat check                            # also runs on commit once init adds the hook
```

### Use the gateway with a tool that has its own memory

Point the tool at `http://localhost:3207/v1` as usual, then disable the
overlapping halves in `.lore.json` at your project root:

```json
{
  // Keep context management + recall, drop the long-term knowledge base
  "knowledge": { "enabled": false }
}
```

Set `"knowledge": { "enabled": false }` when your tool manages its own
persistent facts; Lore then still handles distillation, recall, and the
context window, without maintaining a second set of facts. See Lore's own
configuration docs for the full schema.

## Commands

| Command                              | What it does                                                            |
| ------------------------------------ | ----------------------------------------------------------------------- |
| `npx perfect-ai-stack <cmd>`         | Same as `sh bin/ai-stack.sh <cmd>` — run from any project               |
| `sh bin/ai-stack.sh init`            | **Start here.** Start gateway + scaffold this project + show IDE config |
| `sh bin/ai-stack.sh wizard`          | Interactive setup for env vars (only for cloud models)                  |
| `sh bin/ai-stack.sh start`           | Start the gateway only; also scaffolds lat.md + hook                    |
| `sh bin/ai-stack.sh stop`            | Stop the gateway                                                        |
| `sh bin/ai-stack.sh logs`            | Follow logs (all services)                                              |
| `sh bin/ai-stack.sh ps`              | Show status                                                             |
| `sh bin/ai-stack.sh update`          | Rebuild LiteLLM (with Headroom) + Lore from latest base images          |
| `sh bin/ai-stack.sh setup-lat [dir]` | Scaffold lat.md + hook in `[dir]` (default: cwd); runs on `start` too   |

## Model selection

You choose which models your session and Lore's background workers use.
Selection is **per project**, stored in `.lore.json` at your project root, so
switching models needs no restart and doesn't affect other projects.

```sh
npx perfect-ai-stack models                              # list + pick interactively
npx perfect-ai-stack models qwen3:8b ministral-3:8b     # session, then worker
```

That writes `.lore.json`:

```json
{
  "model": { "providerID": "openai", "modelID": "qwen3:8b" },
  "workerModel": { "providerID": "openai", "modelID": "ministral-3:8b" }
}
```

- **session** — the model your IDE chat uses.
- **worker** — distillation, curation, query expansion (background, async).
- **curator** — **off by default.** Curation writes durable entries into
  `.lore.md`, which is committed and PR-reviewed; opting in means you or a
  reviewer vet what the agent recorded. Turn it on with:

  ```json
  { "curator": { "enabled": true } }
  ```

  Opt in when you want automatic extraction of decisions and preferences that
  `lat.md` cannot hold (it describes code structure; the curator captures
  session facts). It needs a capable model — see the measured table below.

- Omitting `workerModel` falls back to the session model, then to
  `LORE_WORKER_MODEL` (env default `openai/qwen3:8b`).
- Existing keys in `.lore.json` (e.g. `knowledge`) are preserved, and an
  explicit `curator` setting is never overwritten by a re-run.
- Both `providerID`s are `openai` because every model here is reached through
  LiteLLM over the OpenAI protocol. **Don't split providers** — cross-provider
  worker calls fail (wrong credentials, wrong API format).

### Onboarding picks these for you

`init` asks for the session and worker model as part of setup, so a new
project starts on the measured-best local pair with the curator off. Press
Enter to accept the defaults, or name any model the gateway serves. Running
non-interactively (npx in a script, CI) skips the prompt and writes the
defaults rather than hanging.

### Make the worker a local model

The worker runs on **every session**, in the background, whether or not you
actually chat — distillation after each segment, curation on idle, query
expansion per recall. Point it at a cloud model and you pay on every session.
Point it at Ollama and that cost is zero.

**Thinking models cost more per worker call, but don't hurt quality.** `qwen3:8b`
emits reasoning before content, so a short `max_tokens` returns 200 with empty
content, and every background call spends tokens reasoning about a
summarization task. That is a **token-cost** issue, not an accuracy one —
measured below, it produced correct categories with no duplicates. `/no_think`
is not a fix, since the worker builds its own prompts.

### Which local model to use (measured)

Lore's docs put the curation floor at 32B+. We tested the 8B candidates on the
real task anyway — specs alone don't predict this, and the result was not what
parameter counts suggest:

```sh
ollama pull qwen3:8b
npx perfect-ai-stack models qwen3:8b qwen3:8b     # session + worker
```

| Model            | Categories correct | Duplicates | Verdict          |
| ---------------- | ------------------ | ---------- | ---------------- |
| `qwen3:8b`       | **4/4**            | 0          | ✅ use this      |
| `ministral-3:8b` | 2/4                | 0          | ❌ misclassifies |

`ministral-3:8b` systematically labelled "switching from npm to pnpm" a
**gotcha** instead of a decision/preference, and dropped the `preference`
category entirely — identically across three runs, so it is a real flaw rather
than sampling noise. A wrong category in a committed `.lore.md` is exactly the
review burden Lore warns about.

`qwen3:8b` classified all four facts correctly and kept the reason ("duplicate
lockfiles") in the content. Its cost is thinking tokens, which are local and
free.

### Compare models yourself

Quality is not predictable from parameter count, so measure it before choosing.
This sends one fixed conversation (5 known durable facts) to each model through
the gateway and prints the raw output plus a format check:

```sh
sh scripts/eval-worker.sh                 # every local model the gateway serves
sh scripts/eval-worker.sh qwen3:8b         # or specific models
```

Read-only — it does not write `.lore.md` or touch the database. What to look
for: valid JSON, correct categories, no duplicate titles, and no invented
facts. A wrong category is the failure to watch for most closely: it is the one
that silently corrupts a committed file while looking perfectly well-formed.

This is the recommended shape: **thinking-capable model for the session, local
model for the worker**. It works because both route through LiteLLM on the same
protocol — see [All models route through LiteLLM](#all-models-route-through-litellm).

A real run's output (model `qwen3:8b`, reformatted from one line):

```json
[
  {
    "category": "decision",
    "title": "Package Manager Switch",
    "content": "Switching from npm to pnpm across all repos due to duplicate lockfiles"
  },
  {
    "category": "architecture",
    "title": "Database Access Pattern",
    "content": "Auth service must communicate with billing DB only through API gateway"
  },
  {
    "category": "preference",
    "title": "Python Linting Tool",
    "content": "Use ruff instead of flake8 for Python linting"
  },
  {
    "category": "gotcha",
    "title": "Webhook Timeout Handling",
    "content": "Payments webhook times out without setting Retry-After header on 429 responses"
  }
]
```

```
    valid JSON: yes
    entries:    4
    categories: architecture, decision, gotcha, preference
    dup titles: 0
```

4 of 5 facts, correct categories, no duplicates. That is better than the 8B
small-model reputation suggests — but it still missed the subtlest entry (the
causal link between the migration incident and the DB rule), which is exactly
the kind of thing `lat.md` holds better anyway.

**Local quality floors** ([Lore's local-inference guide](https://withlore.ai/docs/guides/local-inference/)):

| Pipeline            | Local model        | Notes                                                                      |
| ------------------- | ------------------ | -------------------------------------------------------------------------- |
| **Distillation**    | 7B-class, Q4/Q5    | Fine. Produces usable observation logs, even code-heavy                    |
| **Query expansion** | 7B-class           | Fine — it only rephrases recall queries                                    |
| **Curation**        | **32B+ preferred** | 7B yields duplicates, wrong categories, low-confidence facts in `.lore.md` |

**When to opt in to curation.** These floors are why it ships off:

| Your worker model                  | Curation                                                       |
| ---------------------------------- | -------------------------------------------------------------- |
| 8B-class local (default)           | ❌ Leave it off — under the floor; one tested 8B misclassified |
| 32B+ local, or a cheap cloud model | ✅ Opt in — clears the documented floor                        |

With curation off you keep distillation, recall, gradient context management,
and `lat.md` indexing; you lose automatic `.lore.md` extraction. That is the
intended default for an 8B local worker, not a degraded mode.

If you have the RAM for 32B, or want to point the worker at a cheap cloud model
for curation only, opt in and check the output with
`sh scripts/eval-worker.sh`.

**To use a model not listed above**, add it to `config/litellm.yaml` under
`model_list`, then restart the gateway once (`ai-stack restart` — or
`docker compose up -d --force-recreate litellm` if you're calling compose
directly; a plain `up -d` can leave the old container running and the new
model invisible in `/v1/models`). Example:

```yaml
- model_name: qwen2.5-coder:14b
  litellm_params:
    model: ollama/qwen2.5-coder:14b
    api_base: http://host.docker.internal:11434
```

Then `ai-stack models qwen3:8b ministral-3:8b`. Any model your IDE
list shows comes from this file — `curl -s http://localhost:3207/v1/models`,
which is the authoritative check that a new entry registered.
Both local blocks are already in `config/litellm.yaml`: `ministral-3:8b` is
active, `llama3.1:8b` and `qwen2.5-coder:14b` are commented out. Uncomment the
one you pulled.

### Don't point Lore directly at Ollama

Lore's [local-inference guide](https://withlore.ai/docs/guides/local-inference/)
shows `LORE_UPSTREAM_OLLAMA=http://localhost:11434` for talking to a local
server without a proxy. **That env var does not exist in the gateway version
pinned here** (`@loreai/gateway` 0.40.0 reads only `LORE_UPSTREAM_OPENAI` and
`LORE_UPSTREAM_ANTHROPIC`), so setting it is a silent no-op.

Even on a newer gateway, prefer routing through LiteLLM: `LORE_UPSTREAM_*` is
where Lore forwards the session, so bypassing LiteLLM also bypasses
**Headroom compression**, and you'd lose the provider routing that
`config/litellm.yaml` centralises. Local models here are local _because
LiteLLM's `api_base` points at your Ollama host_ — not because Lore knows
Ollama exists.

## One stack, many projects

The stack is cloned **once** — every project you work in uses the same
running gateway (Lore keys memory per project via its git remote, not per
clone), and `lat` is a single global npm install. Per-project setup is just
the lat.md scaffold + pre-commit hook:

```sh
cd ~/code/project-a
sh /path/to/perfect-ai-stack/bin/ai-stack.sh setup-lat
# or from anywhere: sh .../ai-stack.sh setup-lat ~/code/project-b
```

Run it once per project — nothing to clone or reinstall. `start`/`stop`/
`logs`/`update` stay in the stack clone; point each project's IDE at the
shared gateway (see “IDE / agent setup”).

## Environment Variables

All vars have sensible defaults — API keys are only needed if you use cloud models.
Docker Compose interpolates `${VAR}` only inside `docker-compose.yml`, not
within `.env` values — overrides must be literal values (no `$REF`
indirection; see `.env.example.md`).

### Where to put API keys

Either export them in your shell profile (`~/.zshrc`, `~/.bashrc`):

```sh
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
```

or write them to a repo-local `.env` file (auto-loaded by Docker Compose,
gitignored). A template with every supported variable (zero secrets) is
committed as [`.env.example.md`](.env.example.md) — copy it to `.env` and
adjust. The wizard (`ai-stack.sh wizard`) can generate this for you too:

```sh
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
```

Don't override the `LORE_*` variables unless you need to — the defaults
(shown in `.env.example.md`) point Lore at LiteLLM, and that's where you
want it (see the stale-env warning in Quick start).

### LiteLLM

| Variable            | Purpose           | Default              |
| ------------------- | ----------------- | -------------------- |
| `ANTHROPIC_API_KEY` | Claude 3.5 Sonnet | only if using Claude |
| `OPENAI_API_KEY`    | DeepSeek / GPT-4o | only if using cloud  |

No `LITELLM_MASTER_KEY` is set: LiteLLM runs **auth-disabled** (accepts any
key) so Lore's forwarded client keys work without a key database. This is a
local single-user stack; don't expose port `4000` beyond your machine.

### Lore (Docker)

| Variable                  | Purpose                         | Default                         |
| ------------------------- | ------------------------------- | ------------------------------- |
| `LORE_UPSTREAM_OPENAI`    | OpenAI-compatible upstream      | `http://litellm:4000`           |
| `LORE_UPSTREAM_ANTHROPIC` | Anthropic upstream              | `http://litellm:4000`           |
| `LORE_WORKER_UPSTREAM`    | Upstream for background workers | `http://litellm:4000`           |
| `LORE_WORKER_MODEL`       | Background worker model         | `openai/qwen3:8b`               |
| `LORE_WORKER_API_KEY`     | Key used for worker calls       | `sk-litellm-master` (any works) |
| `LORE_DEBUG`              | Enable debug logging            | `true`                          |

`LORE_WORKER_MODEL` is a `provider/model` pair. The part after the slash is the
model name sent to `LORE_WORKER_UPSTREAM` and **must exist in LiteLLM's
`model_list`** (`config/litellm.yaml`). The part before the slash is the
**provider ID**, which selects the protocol the worker speaks:

- `openai/…` — OpenAI-compatible chat completions (LiteLLM, DeepSeek, Ollama).
- `anthropic/…` — Anthropic Messages API.

Lore resolves `providerID` and derives the protocol from it — it does not parse
a prefix string, and there is no implicit `anthropic` fallback for a bare model
name. Always write the `openai` provider when the worker targets LiteLLM, or the
worker speaks a protocol LiteLLM's `/v1/chat/completions` route won't answer.

**Workers must use the same provider as the session** — cross-provider worker
calls fail (wrong credentials, wrong API format). They _may_ use a different
model and a different real backend: `deepseek-v4-flash` (DeepSeek) for the
session and `qwen3:8b` (Ollama) for the worker is fine, because both are
`openai` provider and both route through LiteLLM. Override the URL the worker
calls with `LORE_WORKER_UPSTREAM`.

Change both the provider and the model name if your Ollama uses a different tag
(e.g. `openai/qwen2.5:7b` + a matching `model_list` entry).

The upstream defaults point at LiteLLM inside the Docker network — override
them only if you want Lore to skip LiteLLM.

### Ollama-only (no API keys)

No keys are needed for a fully local setup — Ollama runs on your host and
LiteLLM reaches it at `host.docker.internal:11434`. Setup is
[Quick start step 2](#2-pull-a-local-model); use `qwen3:8b` as both the session
and worker model.

## Models

| Model name          | Backend       | Notes                                |
| ------------------- | ------------- | ------------------------------------ |
| `deepseek-v4-flash` | DeepSeek API  | needs `OPENAI_API_KEY`               |
| `deepseek-v4-pro`   | DeepSeek API  | needs `OPENAI_API_KEY`               |
| `qwen3:8b`          | Ollama (host) | **worker + session** — measured best |
| `ministral-3:8b`    | Ollama (host) | measured: misclassifies              |
| `llama3.1:8b`       | Ollama (host) | untested alternative, 128K           |

## Architecture

### Request flow

One box means one network hop. Everything above the "Docker network" line runs
in a container; Ollama runs **on the host**, which is why LiteLLM reaches it at
`host.docker.internal` rather than a service name.

```mermaid
flowchart TB
    subgraph clients["Your IDE / agent"]
        IDE["Zed, Cursor, VS Code,\nContinue, Claude Code…"]
    end

    subgraph net["Docker network"]
        LORE["ai-lore — Lore gateway :3207\nmemory + context + recall"]
        LL["ai-litellm — LiteLLM :4000\nprovider routing\n+ Headroom callback"]
    end

    subgraph host["Host machine — not Docker"]
        OLL["Ollama :11434\nqwen3:8b"]
    end

    DS["DeepSeek API"]
    AN["Anthropic API"]
    OA["OpenAI API"]

    IDE -->|"http://localhost:3207/v1\nOpenAI-compatible"| LORE
    LORE -->|"LORE_UPSTREAM_OPENAI\nbear root, no /v1"| LL
    LL -->|"host.docker.internal:11434"| OLL
    LL --> DS
    LL --> AN
    LL --> OA
```

Lore is the OpenAI-compatible `/v1` endpoint your IDE talks to. It is the only
port you point a client at; `:4000` is LiteLLM's own API and is not part of the
user-facing path.

### What happens on one request

```mermaid
sequenceDiagram
    participant IDE as IDE
    participant L as Lore :3207
    participant LL as LiteLLM :4000
    participant H as Headroom (in-process)
    participant P as Provider

    IDE->>L: POST /v1/chat/completions
    L->>L: resolve project (git remote)
    L->>L: load memory + lat.md sections
    L->>L: build gradient context window
    L->>LL: POST /v1/chat/completions
    LL->>H: pre-call hook
    H->>H: compress messages\n(JSON / code / prose)
    H-->>LL: compressed messages
    LL->>P: route by model_name
    P-->>LL: completion
    LL-->>L: completion (unmodified)
    L->>L: store turn, queue distillation
    L-->>IDE: completion
```

Two things worth noting in that flow: Headroom compresses the **request only**
(responses pass through untouched), and the memory write happens on the way
back so a slow distillation never blocks your reply.

### Session vs worker

This is the part that most affects cost. The **worker** runs three background
pipelines — distillation, curation, query expansion — on every session,
whether or not you chat.

```mermaid
flowchart LR
    TURN["session turn"] --> SESS["session model\nLORE from .lore.json 'model'"]
    TURN --> STORE["temporal store\ndata/lore/lore.db"]
    STORE --> W["worker model\n.lore.json 'workerModel'\n(env fallback LORE_WORKER_MODEL)"]
    W --> D["distillation\n7B ok"]
    W --> C["curation\n32B+ preferred"]
    W --> Q["query expansion\n7B ok"]
    D --> CTX["context window\nnext turn"]
    C --> LTM[".lore.md\nknowledge"]
```

Both models must be the **same provider** (here: `openai` via LiteLLM) —
cross-provider worker calls fail. Point the worker at a local model to keep
this at zero cost; see [Make the worker a local model](#make-the-worker-a-local-model).

### Where state lives

Everything stateful is on the host, so it survives `stop`, `update`, and
`docker compose down`.

```mermaid
flowchart TB
    subgraph bind["host bind mounts"]
        LR["data/lore/\nLore memory DB + vectors"]
        HR["data/headroom/\nHF model cache + CCR store"]
    end
    subgraph proj["your project — bind-mounted at /app"]
        LM["lat.md/\nknowledge graph"]
        LF[".lore.md\nexported knowledge"]
        LJSON[".lore.json\nmodel selection"]
    end
    LORE["ai-lore"]
    LL["ai-litellm"]
    LORE --- LR
    LORE --- LM
    LORE --- LF
    LORE --- LJSON
    LL --- HR
```

The container itself is disposable: `lat.md/`, `.lore.md`, and `.lore.json`
are meant to be committed, while `data/` holds the machine-local DB and is
gitignored.

## IDE / agent setup (BYOK)

The stack is client-agnostic: any editor or coding agent that supports
bring-your-own-key (BYOK) OpenAI-compatible endpoints can use it. Point your
client at Lore's gateway — any API key value works, since LiteLLM runs
auth-disabled and the key is just passed through:

```sh
export OPENAI_BASE_URL=http://localhost:3207/v1      # OpenAI-compatible clients
# or
# export ANTHROPIC_BASE_URL=http://localhost:3207     # Anthropic-protocol clients
```

Use a model name from the Models table above (e.g. `deepseek-v4-flash` for
DeepSeek, or `qwen3:8b` for Ollama). Zed, Cursor, VS Code
Copilot, Claude Code — anything that accepts a custom base URL — works the
same way. These are guidelines, not repo-committed IDE config: adapt to
whatever editor your team uses.

### Knowledge graph access (MCP)

If your IDE supports MCP, register lat's server so the agent queries the graph
with `lat search` / `lat section` instead of grepping. Example — Zed
(`.zed/mcp.json` in the project):

```json
{
  "servers": {
    "lat": { "command": "lat", "args": ["mcp"] }
  }
}
```

Claude Code, Cursor, and friends get hooks + MCP automatically from
`lat init`. For other IDEs, adapt the pattern: `lat mcp` speaks stdio MCP.

Lore's own gateway also prints these instructions on startup
(`docker compose logs lore`).

## lat.md

[`lat.md`](https://www.npmjs.com/package/lat.md) is a markdown knowledge
graph for the codebase — high-level concepts, business logic, and architecture
that your agent reads via `lat search` / `lat section` (or its MCP server).
`ai-stack start` scaffolds it if missing or still just the committed
placeholder intro file; re-run with `sh bin/ai-stack.sh setup-lat`.

```sh
lat search "payment flow"   # semantic search across lat.md sections
lat section "architecture"  # show a section with its links and refs
lat gen agents.md           # generate agent instructions that use lat
lat check                   # validate links + code references (runs on every commit)
lat reindex                 # rebuild the embedding index (lat.md/.cache/, gitignored)
```

`lat init` (which the setup runs) is interactive — it asks which coding agents
you use and wires up hooks/MCP/skills for them. It therefore only runs when
stdin is a terminal; an unattended `start` prints a hint to run
`ai-stack setup-lat` manually instead. Semantic search works offline out of
the box (bundled local embedding model) — no key needed.

**Enforcement:** `setup-lat` installs a git pre-commit hook (`.git/hooks/
pre-commit`) that runs `lat check`. A commit that changes a `// @lat:` anchor
without updating the graph fails — docs can't drift silently, for human edits
as well as agent edits. The install is idempotent: an existing hook that
already runs `lat check` is left alone, and one without it gets `lat check`
appended.

The knowledge base itself (`lat.md/lat.md`) is meant to be committed; only the
generated embedding index (`lat.md/.cache/`) is gitignored.

## Headroom

Headroom runs **inside the LiteLLM container** as a callback — no separate
service. The custom image (`litellm/Dockerfile`) installs `headroom-ai`, and
`litellm/entrypoint.py` registers `HeadroomCallback` as a LiteLLM callback
_before_ the proxy starts. (YAML dotted-path callbacks aren't used: LiteLLM
registers those as the class, not an instance, which silently breaks the async
pre-call hook.)

Before each request is forwarded to a provider, the callback compresses the
messages in-process (JSON tool outputs via SmartCrusher, code via tree-sitter,
prose via the Kompress-v2-base model). Responses pass through unchanged. This
applies to **both** Lore's session model and its background worker model — all
Lore traffic is routed through LiteLLM (see below).

- Local-first: nothing is sent to a Headroom cloud; compression runs on your
  machine in the LiteLLM container.
- User messages are left untouched by default, and code in the last 4
  messages is protected from compression (coding-agent defaults).
- **First compression downloads the model** (`chopratejas/kompress-v2-base` from
  HuggingFace, ~a few hundred MB) and can take a minute. It is cached in
  `data/headroom/` so later starts don't re-download it. On x86 hosts without
  AVX2 (some Docker/QEMU setups), Headroom falls back to non-ONNX compressors
  automatically.
- In callback mode compression is one-way (originals are not retrievable — CCR
  retrieval is a proxy-mode feature), but the CCR originals store still lives on
  the host (`data/headroom/ccr_store.db`), so a container recreate doesn't wipe
  it mid-session.

## Persistence

Everything stateful lives in `data/` on the host — outside the containers, so
it survives `stop`, `update`, and `docker compose down`:

| Dir              | What it holds                                   |
| ---------------- | ----------------------------------------------- |
| `data/lore/`     | Lore memory (SQLite DB + vector embeddings)     |
| `data/headroom/` | Headroom's HF model cache + CCR originals store |

```sh
sqlite3 data/lore/lore.db "SELECT * FROM projects;"
```

`.lore.md` exports land in this repo's root (the container's working directory).
Already have a Lore DB from a previous host install at `~/.local/share/lore`?
Copy it over once before the first start:

```sh
mkdir -p data/lore && cp -R ~/.local/share/lore/. data/lore/
```

### All models route through LiteLLM

Lore's gateway hardcodes a model-prefix → provider table (`claude-*` →
`api.anthropic.com`, `gpt-*`/`deepseek-*` → OpenAI, …) that would bypass
LiteLLM. The Lore Dockerfile (`Dockerfile`) patches that table out, so **every**
session request falls through to `LORE_UPSTREAM_*` (LiteLLM) and gets Headroom
compression. LiteLLM then maps the model name to the real provider via
`config/litellm.yaml`.

The **worker** takes a separate path: `LORE_WORKER_MODEL` splits on `/` into
`provider/model`, and the provider ID selects the protocol. Write the `openai`
provider explicitly. The default `openai/qwen3:8b` speaks the OpenAI
protocol, so the worker sends plain `qwen3:8b` to LiteLLM (→ Ollama), exactly
like the session model sends `deepseek-v4-flash` (→ DeepSeek). Session and worker
can therefore use different real backends (DeepSeek + Ollama) as long as both use
the `openai` provider through LiteLLM — that same-provider constraint is why a
cross-provider worker pairing fails with wrong credentials / wrong API format.

Check it works:

```sh
docker compose logs litellm | grep Headroom   # per-request "Headroom: N->M tokens" lines
```
