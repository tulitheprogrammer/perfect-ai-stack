# ai-stack

**Shared AI proxy stack** — one command to start/stop your local AI middleware.

Manages **Lore AI Gateway** (context/memory), **Headroom AI Proxy** (rate limiting),
and **LiteLLM** (model routing), plus a **lat.md scaffold** for project documentation.

```
Zed → Lore AI Gateway (:3207) → Headroom (:8787) → LiteLLM (:4000) → DeepSeek API / Ollama
```

## Install

```sh
npm install -g github:tulitheprogrammer/ai-stack
# or local:
npm install -g ./packages/ai-stack
```

Or via git subdirectory in a monorepo:

```sh
npm install -g github:tulitheprogrammer/pluginizer/packages/ai-stack
```

Then:

```sh
ai-stack init          # copy config + scripts to ~/.config/ai-stack/
```

## Usage

| Command              | What it does                                         |
| -------------------- | ---------------------------------------------------- |
| `ai-stack start`     | Start all proxies (Lore, LiteLLM, Headroom)          |
| `ai-stack stop`      | Stop all                                             |
| `ai-stack logs`      | Follow combined logs                                 |
| `ai-stack init`      | (Re)install config to `~/.config/ai-stack/`          |
| `ai-stack setup-lat` | Scaffold `lat.md` knowledge graph in current project |

## Environment

| Variable        | Default                   | Purpose              |
| --------------- | ------------------------- | -------------------- |
| `AI_STACK_DIR`  | `~/.config/ai-stack`      | Config file location |
| `AI_STACK_DATA` | `~/.local/share/ai-stack` | Log & data directory |

## Docs & Diagrams

- [`docs/setup-guide.md`](docs/setup-guide.md) — full installation & configuration walkthrough
- [`docs/diagrams/`](docs/diagrams/) — architecture diagrams (Mermaid)

## lat.md Scaffold

```sh
cd your-project
ai-stack setup-lat
```

Installs `lat.md/`, pre-commit hook, and `.gitignore` entries.

## Contents

```
bin/
  ai-stack.sh             — main CLI
  setup-lat.sh            — lat.md scaffold
config/
  litellm.yaml            — shared LiteLLM model routing
scripts/
  proxy-stack.sh          — proxy launcher (location-independent)
  pre-commit-hook.sh      — template git hook for lat check
docs/
  setup-guide.md          — full setup walkthrough
  diagrams/               — architecture diagrams
```
