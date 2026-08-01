# perfect-ai-stack

**AI proxy stack** — LiteLLM (with Headroom compression) + Lore in Docker.

```
Zed -> Lore (:3207) -> LiteLLM + Headroom (:4000) -> DeepSeek / Anthropic / OpenAI / Ollama (host)
```

## Prerequisites

- Docker Desktop (running):

  ```sh
  open -a Docker
  # wait for the whale icon in the menu bar to stop animating
  ```

- Docker + Docker Compose (v2)
- API keys in environment (see below)

## Quick start

> **If you previously ran Lore on the host**, clear the old env vars first —
> stale `LORE_UPSTREAM_OPENAI` / `LORE_UPSTREAM_ANTHROPIC` /
> `LORE_WORKER_UPSTREAM` (`http://localhost:8787/v1`) override the compose
> defaults and point inside the container at nothing. Also remove them from
> your shell profile.
>
> ```sh
> unset LORE_UPSTREAM_OPENAI LORE_UPSTREAM_ANTHROPIC LORE_WORKER_UPSTREAM LORE_WORKER_MODEL LORE_WORKER_API_KEY
> ```

```sh
git clone git@github.com:tulitheprogrammer/perfect-ai-stack.git
cd perfect-ai-stack

# Interactive setup
sh bin/ai-stack.sh wizard

# Start the stack
sh bin/ai-stack.sh start
```

First start pulls the LiteLLM base image and builds both containers — allow a
few minutes. The first model request also downloads Headroom's compression
model (~275 MB) once, cached in `data/headroom/`.

## Commands

| Command                        | What it does                                                   |
| ------------------------------ | -------------------------------------------------------------- |
| `sh bin/ai-stack.sh wizard`    | Interactive setup for env vars                                 |
| `sh bin/ai-stack.sh start`     | Build + start LiteLLM + Lore (Docker)                          |
| `sh bin/ai-stack.sh stop`      | Stop both                                                      |
| `sh bin/ai-stack.sh logs`      | Follow logs (all services)                                     |
| `sh bin/ai-stack.sh ps`        | Show status                                                    |
| `sh bin/ai-stack.sh update`    | Rebuild LiteLLM (with Headroom) + Lore from latest base images |
| `sh bin/ai-stack.sh setup-lat` | Scaffold the lat.md knowledge graph (runs on `start` too)      |

## Environment Variables

All vars have sensible defaults — API keys are only needed if you use cloud models.

### Where to put API keys

Either export them in your shell profile (`~/.zshrc`, `~/.bashrc`):

```sh
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-ant-..."
```

or write them to a repo-local `.env` file (auto-loaded by Docker Compose,
gitignored). The wizard (`ai-stack.sh wizard`) can generate this for you:

```sh
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
```

Don't set any `LORE_*` variables — the compose defaults point Lore at LiteLLM
and that's where you want it (see the stale-env warning in Quick start).

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
| `LORE_UPSTREAM_OPENAI`    | OpenAI-compatible upstream      | `http://litellm:4000/v1`        |
| `LORE_UPSTREAM_ANTHROPIC` | Anthropic upstream              | `http://litellm:4000/v1`        |
| `LORE_WORKER_UPSTREAM`    | Upstream for background workers | `http://litellm:4000/v1`        |
| `LORE_WORKER_MODEL`       | Background worker model         | `llama3.1:8b`                   |
| `LORE_WORKER_API_KEY`     | Key used for worker calls       | `sk-litellm-master` (any works) |
| `LORE_DEBUG`              | Enable debug logging            | `true`                          |

`LORE_WORKER_MODEL` must exist in LiteLLM's `model_list` (`config/litellm.yaml`)
— change both if your Ollama uses a different tag.

The upstream defaults point at LiteLLM inside the Docker network — override
them only if you want Lore to skip LiteLLM.

### Ollama-only (no API keys)

Requires Ollama running on the host (`docker-compose` reaches it at
`host.docker.internal:11434`) with the models you use pulled (`llama3` and
`llama3.1:8b`):

```sh
brew install ollama && ollama serve
ollama pull llama3
ollama pull llama3.1:8b
```

Then:

```sh
sh bin/ai-stack.sh start
```

No keys needed — `local-llama` and `llama3.1:8b` route through LiteLLM to
Ollama on the host.

## Models

| Model name          | Backend       |
| ------------------- | ------------- |
| `claude-3-5-sonnet` | Anthropic API |
| `gpt-4o`            | OpenAI API    |
| `deepseek-v4-flash` | DeepSeek API  |
| `deepseek-v4-pro`   | DeepSeek API  |
| `local-llama`       | Ollama (host) |
| `llama3.1:8b`       | Ollama (host) |

## Architecture

```
┌──────────┐     ┌──────────┐     ┌────────────────────┐     ┌──────────────┐
│  Zed     │ ──> │  Lore    │ ──> │  LiteLLM + Headroom│ ──> │  DeepSeek    │
│  Editor  │     │ (:3207)  │     │  (Docker:4000)     │     │  Anthropic   │
│          │     │ (Docker) │     │                    │ ──> │  OpenAI      │
└──────────┘     └──────────┘     └────────────────────┘     │  Ollama      │
                                                              └──────────────┘
```

## Point your agent at the stack

Point your client (Zed, Claude Code, any OpenAI-compatible tool) at Lore's
gateway. Any API key value works — LiteLLM runs auth-disabled, so the key is
just passed through:

```sh
export OPENAI_BASE_URL=http://localhost:3207/v1      # OpenAI-compatible clients
# or
# export ANTHROPIC_BASE_URL=http://localhost:3207     # Anthropic-protocol clients
```

Use a model name from the Models table above (e.g. `v4-flash` for DeepSeek,
`claude-3-5-sonnet`, or `local-llama` for Ollama). Lore's own gateway also
prints these instructions on startup (`docker compose logs lore`).

## lat.md

[`lat.md`](https://www.npmjs.com/package/lat.md) is a markdown knowledge
graph for the codebase — high-level concepts, business logic, and architecture
that your agent reads via `lat search` / `lat expand` (or its MCP server).
`ai-stack start` scaffolds it (`lat.md/lat.md`) if missing; re-run with
`sh bin/ai-stack.sh setup-lat`.

```sh
lat search "payment flow"   # semantic search across lat.md sections
lat gen agents.md            # generate agent instructions that use lat
lat reindex                  # rebuild the embedding index (lat.md/.cache/, gitignored)
```

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
compression — same for the worker, which already used `LORE_WORKER_UPSTREAM`.
LiteLLM then maps the model name to the real provider via `config/litellm.yaml`.

Check it works:

```sh
docker compose logs litellm | grep Headroom   # per-request "Headroom: N->M tokens" lines
```

## Legacy

The old shell-based approach is archived in [`legacy/`](legacy/).
