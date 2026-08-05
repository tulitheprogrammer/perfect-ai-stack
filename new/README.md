# perfect-ai-stack

**AI proxy stack** — LiteLLM (with Headroom compression) + Lore in Docker,
plus a per-repo lat.md knowledge graph scaffolded with git-hook enforcement.

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

# Start the stack (also scaffolds lat.md + installs the pre-commit hook)
sh bin/ai-stack.sh start
```

First start pulls the LiteLLM base image and builds both containers — allow a
few minutes. The first model request also downloads Headroom's compression
model (~275 MB) once, cached in `data/headroom/`.

## Commands

| Command                              | What it does                                                          |
| ------------------------------------ | --------------------------------------------------------------------- |
| `sh bin/ai-stack.sh wizard`          | Interactive setup for env vars                                        |
| `sh bin/ai-stack.sh start`           | Build + start LiteLLM + Lore (Docker); scaffold lat.md + hook         |
| `sh bin/ai-stack.sh stop`            | Stop both                                                             |
| `sh bin/ai-stack.sh logs`            | Follow logs (all services)                                            |
| `sh bin/ai-stack.sh ps`              | Show status                                                           |
| `sh bin/ai-stack.sh update`          | Rebuild LiteLLM (with Headroom) + Lore from latest base images        |
| `sh bin/ai-stack.sh setup-lat [dir]` | Scaffold lat.md + hook in `[dir]` (default: cwd); runs on `start` too |

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

| Variable             | Purpose                  | Default              |
| -------------------- | ------------------------ | -------------------- |
| `ANTHROPIC_API_KEY`  | Claude 3.5 Sonnet        | only if using Claude |
| `OPENAI_API_KEY`     | DeepSeek / GPT-4o        | only if using cloud  |
| `LITELLM_MASTER_KEY` | Enables dashboard + auth | `sk-litellm-master`  |

#### LiteLLM auth & dashboard

The stack runs LiteLLM **auth-enabled**: `LITELLM_MASTER_KEY` (default
`sk-litellm-master`) both enables the Admin dashboard at
`http://localhost:4000/ui` and requires every API caller to present a valid
key. There is no key database — the whole single-user stack uses this one
key.

- **Log in**: username `admin`, password = the master key (`sk-litellm-master`
  by default). Configure via `LITELLM_UI_USERNAME` / `LITELLM_UI_PASSWORD`.
- **Worker**: the background worker already inherits the master key via
  `LORE_WORKER_API_KEY=${LITELLM_MASTER_KEY}` — it authenticates with the
  same key, so it works with auth on.
- **Clients**: your agent's key (whatever it sends through Lore) must equal
  the master key, since auth is on. It's a local single-user stack — change
  the key if you'll ever expose port `4000`.

### Lore (Docker)

| Variable                  | Purpose                         | Default                       |
| ------------------------- | ------------------------------- | ----------------------------- |
| `LORE_UPSTREAM_OPENAI`    | OpenAI-compatible upstream      | `http://litellm:4000/v1`      |
| `LORE_UPSTREAM_ANTHROPIC` | Anthropic upstream              | `http://litellm:4000/v1`      |
| `LORE_WORKER_UPSTREAM`    | Upstream for background workers | `http://litellm:4000/v1`      |
| `LORE_WORKER_MODEL`       | Background worker model         | `llama3.1:8b`                 |
| `LORE_WORKER_API_KEY`     | Key used for worker calls       | inherits `LITELLM_MASTER_KEY` |
| `LORE_DEBUG`              | Enable debug logging            | `true`                        |

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

## IDE / agent setup (BYOK)

The stack is client-agnostic: any editor or coding agent that supports
bring-your-own-key (BYOK) OpenAI-compatible endpoints can use it. Point your
client at Lore's gateway. With auth on, the key you configure in the client
must equal `LITELLM_MASTER_KEY` (default `sk-litellm-master`) — it is
forwarded through Lore to LiteLLM:

```sh
export OPENAI_BASE_URL=http://localhost:3207/v1      # OpenAI-compatible clients
# or
# export ANTHROPIC_BASE_URL=http://localhost:3207     # Anthropic-protocol clients
```

Use a model name from the Models table above (e.g. `v4-flash` for DeepSeek,
`claude-3-5-sonnet`, or `local-llama` for Ollama). Zed, Cursor, VS Code
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
compression — same for the worker, which already used `LORE_WORKER_UPSTREAM`.
LiteLLM then maps the model name to the real provider via `config/litellm.yaml`.

Check it works:

```sh
docker compose logs litellm | grep Headroom   # per-request "Headroom: N->M tokens" lines
```
