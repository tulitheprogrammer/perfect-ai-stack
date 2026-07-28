# perfect-ai-stack

**Shared AI proxy stack** — one command to start/stop your local AI middleware.

Manages **Lore AI Gateway** (context/memory), **Headroom AI Proxy** (rate limiting),
and **LiteLLM** (model routing), plus a **lat.md scaffold** for project documentation.

```
Zed → Lore AI Gateway (:3207) → Headroom (:8787) → LiteLLM (:4000) → DeepSeek API / Ollama
```

## Install

```sh
npm install -g github:tulitheprogrammer/perfect-ai-stack
```

## Usage

No setup or config copy needed — scripts resolve everything relative to their install path.

| Command | What it does |
|---------|-------------|
| `ai-stack start` | Start all proxies (Lore, LiteLLM, Headroom) |
| `ai-stack stop` | Stop all |
| `ai-stack logs` | Follow combined logs from $PWD/logs/ |
| `ai-stack setup-lat` | Scaffold lat.md in current project |

## Docs & Diagrams

- [docs/setup-guide.md](docs/setup-guide.md) — full installation guide
- [docs/diagrams/](docs/diagrams/) — architecture diagrams

## lat.md Scaffold

```sh
cd your-project
ai-stack setup-lat
```

Copies pre-commit hook, inits lat.md/, updates .gitignore.
