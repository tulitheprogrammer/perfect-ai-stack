# LoreAI + DeepSeek + Ornith — Final Flow

```mermaid
flowchart TD
    %% ── Actors ──
    USER(["👤 You (User)"])
    ZED(["📝 Zed Editor"])

    %% ── Config ──
    ZED_CONFIG["Zed config\n`model = deepseek-v4-flash`\n`provider = Lore-Gateway`\n`api_url = localhost:3207`"]

    %% ── Fast Path: Real-time Request Pipeline ──
    subgraph FAST_PATH ["⚡ Real-time Request Pipeline"]
        ZED_AGENT["Zed Agent\n(sends prompt via HTTP)"]

        LORE_MW["LoreAI Gateway (localhost:3207)\n            · Context injection from .lore.md
            · Session tracking & dedup
            · Context Budget Monitor
            · Streaming SSE passthrough (no buffering)"]

        CTX_BUDGET["Context Budget Monitor
            · Tracks cumulative tokens
            · Triggers compression at 70%
            · Signals session rotation at 90%"]

        FALLBACK["Fallback Bypass
            · Gateway down / timeout >2s
            · Skip Lore, hit LiteLLM directly
            · Cold response > no response"]
    end

    %% ── Proxy Stack (Middle Layer) ──
    subgraph PROXY_STACK ["🔗 Proxy Stack"]
        HEADROOM["Headroom AI Proxy (localhost:8787)\n            · Rate limiting
            · Request logging"]

        LITELLM["LiteLLM Proxy (localhost:4000)\n            · Model routing / fallback
            · API key management\n            · Cost tracking"]
    end

    %% ── Models ──
    DEEPSEEK["DeepSeek V4 Flash\n        (Cloud API · BYK API Key)\n        Primary model: chat, codegen, reasoning"]

    OLLAMA["Ollama (localhost:11434)\n        Local inference engine"]

    %% ── Storage ──
    subgraph STORAGE ["💾 Lore Data Store"]
        MD_STORE[".lore.md / Knowledge Base\n(session summaries, decisions, gotchas)"]
        VEC_DB["Vector / Recall Index\n(embedding search for fast retrieval)"]
        EVENT_QUEUE["Async Job Queue\n(decouples fast path from slow path)"]
    end

    %% ── Slow Path: Background Workers ──
    subgraph WORKERS ["🛠️ Local Background Engine (Ollama)"]
        WORKER_SCHED["Worker Scheduler
            · Batch: every 5 turns
            · Idle trigger: 30s inactivity
            · Debounce: coalesce rapid turns"]

        ORNITH["robit/ornith:9b  (~5.1 GB RAM)\n            or qwen2.5-coder:7b  (~4.0 GB RAM)\n            ↳ Use qwen2.5-coder if <16 GB system RAM"]

        INSIGHTS["Session Insights\n(extract decisions, gotchas, patterns)"]
        COMPRESS["Context Distillation\n(summarize old turns, prune history)"]
        RECALL_BUILD["Recall Indexing\n(build/update vector embeddings)"]
    end

    %% ── Fast Path: Connections ──
    USER -->|types / asks question| ZED
    ZED --> ZED_AGENT
    ZED_AGENT -->|HTTP POST → Lore-Gateway| ZED_CONFIG
    ZED_CONFIG -->|routes to| LORE_MW

    LORE_MW <-->|read / write active context| MD_STORE
    LORE_MW <-->|fast vector search| VEC_DB
    LORE_MW -->|monitors token usage| CTX_BUDGET

    LORE_MW -->|forward prompt (apiBase: 8787)| HEADROOM
    HEADROOM -->|OpenAI-compatible proxy| LITELLM

    LITELLM -->|model: deepseek-v4-flash| DEEPSEEK
    LITELLM -->|model: robit/ornith:9b| OLLAMA

    DEEPSEEK -->|SSE stream| LITELLM
    OLLAMA -->|SSE stream| LITELLM
    LITELLM -->|SSE stream| HEADROOM
    HEADROOM -->|SSE stream| LORE_MW
    LORE_MW -->|SSE stream (unbuffered)| ZED_AGENT
    ZED_AGENT -->|display result| ZED

    %% Fallback path
    LORE_MW -.->|on timeout / failure| FALLBACK
    FALLBACK -->|direct API call (no context injection)| LITELLM
    LITELLM -->|SSE stream| FALLBACK
    FALLBACK -.->|response| ZED_AGENT

    %% ── Fast → Slow decoupling ──
    LORE_MW -.->|async · log turn| EVENT_QUEUE

    %% ── Slow Path: Connections ──
    EVENT_QUEUE -->|polls for jobs| WORKER_SCHED
    WORKER_SCHED -->|dispatch to| ORNITH

    ORNITH --> INSIGHTS
    ORNITH --> COMPRESS
    ORNITH --> RECALL_BUILD

    INSIGHTS -->|append structured summary| MD_STORE
    COMPRESS -->|prune / compress context| MD_STORE
    RECALL_BUILD -->|update embedding vectors| VEC_DB

    CTX_BUDGET -.->|trigger early compression| COMPRESS
    CTX_BUDGET -.->|trigger session rotation| MD_STORE

    %% ── Styling ──
    style USER fill:#e3f2fd,stroke:#1565c0,color:#000
    style ZED fill:#e3f2fd,stroke:#1565c0,color:#000
    style DEEPSEEK fill:#e8f5e9,stroke:#2e7d32,color:#000
    style ORNITH fill:#fff3e0,stroke:#e65100,color:#000
    style FALLBACK fill:#fce4ec,stroke:#c62828,color:#000
    style CTX_BUDGET fill:#f3e5f5,stroke:#6a1b9a,color:#000
    style HEADROOM fill:#e0f7fa,stroke:#00695c,color:#000
    style LITELLM fill:#e8eaf6,stroke:#283593,color:#000
    style OLLAMA fill:#fff3e0,stroke:#e65100,color:#000
```

## Key Design Decisions

| Layer               | What                                                            | Why                                                                                                             |
| ------------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| **Topology**        | Zed → Lore (3207) → Headroom (8787) → LiteLLM (4000) → DeepSeek | Unified proxy stack: Lore for context/memory, Headroom for rate-limiting, LiteLLM for model routing + key mgmt. |
| **Fallback**        | Lore gateway down → bypass to LiteLLM directly                  | Zero-availability-risk: cold response beats no response. ~2s timeout guard.                                     |
| **Streaming**       | SSE passthrough, fully unbuffered                               | Keeps perceived latency identical to direct DeepSeek. All layers pass through transparently.                    |
| **Fast ↔ Slow**     | Async event queue, not inline processing                        | Worker tasks never block your chat. Zero latency impact on code completions.                                    |
| **Worker schedule** | Batch every 5 turns, idle 30s, debounce coalesce                | Prevents insight/index storm on rapid typing.                                                                   |
| **Context budget**  | Monitor token usage live; compress at 70%, rotate at 90%        | Heads-up approach vs reactive OOM / context overflow.                                                           |
| **Vector index**    | Embedding search for recall (alongside .lore.md)                | Scales past what a flat markdown file can handle efficiently.                                                   |
| **Worker model**    | ornith:9b (5.1 GB) or qwen2.5-coder:7b (4.0 GB)                 | qwen2.5-coder recommended if < 16 GB system RAM. Runs via Ollama → LiteLLM.                                     |
