# perfect-ai-stack

**AI proxy stack** — LiteLLM in Docker, Lore on the host.

```
Zed -> Lore (:3207) -> LiteLLM (:4000) -> DeepSeek / Anthropic / OpenAI / Ollama (host)
```

## Prerequisites

- Docker Desktop (running):
  ```sh
  open -a Docker
  # wait for the whale icon in the menu bar to stop animating
  ```

- Docker + Docker Compose (v2)
- `lore` CLI: `npm install -g @byk/lore` (optional — LiteLLM works standalone)
- API keys in environment (see below)

## Quick start

```sh
git clone git@github.com:tulitheprogrammer/perfect-ai-stack.git
cd perfect-ai-stack

# Interactive setup
sh bin/ai-stack.sh wizard

# Start the stack
sh bin/ai-stack.sh start
```

## Commands

| Command               | What it does                               |
|-----------------------|--------------------------------------------|
| `sh bin/ai-stack.sh wizard` | Interactive setup for env vars        |
| `sh bin/ai-stack.sh start`  | Start LiteLLM (Docker) + Lore (host)  |
| `sh bin/ai-stack.sh stop`   | Stop both                              |
| `sh bin/ai-stack.sh logs`   | Follow LiteLLM logs                   |
| `sh bin/ai-stack.sh ps`     | Show status                            |

## Environment Variables

All vars have sensible defaults — API keys are only needed if you use cloud models.

### LiteLLM

| Variable             | Purpose                  | Default             |
|----------------------|--------------------------|---------------------|
| `ANTHROPIC_API_KEY`  | Claude 3.5 Sonnet        | only if using Claude|
| `OPENAI_API_KEY`     | DeepSeek / GPT-4o        | only if using cloud |
| `LITELLM_MASTER_KEY` | LiteLLM admin key        | `sk-litellm-master` |

### Lore (host CLI)

| Variable             | Purpose                  | Default               |
|----------------------|--------------------------|-----------------------|
| `LORE_LLM_KEY`       | Key Lore uses for LLM    | falls back to `OPENAI_API_KEY` |
| `LORE_CHAT_MODEL`    | Model for chat sessions  | `claude-3-5-sonnet`   |
| `LORE_WORKER_MODEL`  | Model for background workers | `local-llama`     |
| `LORE_WORKER_API_KEY`| API key for worker model | falls back to `LORE_LLM_KEY` |
| `LORE_DEBUG`         | Enable debug logging     | `true`                |

### Ollama-only (no API keys)

```sh
LORE_CHAT_MODEL=local-llama \
LORE_WORKER_MODEL=local-llama \
sh bin/ai-stack.sh start
```

## Models

| Model name          | Backend         |
|---------------------|-----------------|
| `claude-3-5-sonnet` | Anthropic API   |
| `gpt-4o`            | OpenAI API      |
| `deepseek-v4-flash` | DeepSeek API    |
| `deepseek-v4-pro`   | DeepSeek API    |
| `local-llama`       | Ollama (host)   |

## Architecture

```
┌──────────┐     ┌──────────┐     ┌────────────────┐     ┌──────────────┐
│  Zed     │ ──> │  Lore    │ ──> │  LiteLLM       │ ──> │  DeepSeek    │
│  Editor  │     │  (:3207) │     │  (Docker:4000)  │     │  Anthropic   │
│          │     │  (host)  │     │                │ ──> │  OpenAI      │
└──────────┘     └──────────┘     └────────────────┘     │  Ollama      │
                                                          └──────────────┘
```

## Legacy

The old shell-based approach is archived in [`legacy/`](legacy/).
