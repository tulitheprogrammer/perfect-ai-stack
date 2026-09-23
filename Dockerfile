FROM node:24-slim

# Pin the version: the build applies a source patch that targets this
# release's bundled layout.
RUN npm install -g @loreai/gateway@0.40.0

# Lore's local embedding provider (search.embeddings.provider: "local", the
# default) requires '@huggingface/transformers' at runtime, but the gateway
# package does not declare or install it — without it, recall silently degrades
# to FTS-only search on every project:
#   LocalProviderUnavailableError: '@huggingface/transformers' failed to
#   initialize. Recall will use FTS-only search.
#
# Installed globally next to the gateway so Node resolves it from the gateway's
# own directory. It bundles its own onnxruntime-node (with linux/arm64
# binaries) and the all-MiniLM-style embedder, so no extra native setup is
# needed. This must NOT be trimmed: the local provider is what keeps recall
# working offline and without an API key.
#
# Note: @loreai/onnxruntime-linux-arm64 (Lore's optional native fast path)
# SIGSEGVs on Apple Silicon hosts — 'Unknown CPU vendor: 0' — but that is a
# non-issue once this package is present, since transformers uses its own
# onnxruntime-node instead.
RUN npm install -g @huggingface/transformers@4.3.0

# ponytail: lore's gateway hardcodes a model-prefix -> provider route table
# (claude-*/gpt-*/deepseek-*/... -> api.anthropic.com / api.openai.com / ...)
# that wins over LORE_UPSTREAM_* and sends session traffic past LiteLLM (and
# Headroom). The table is not configurable, so patch it out: every model then
# falls through to LORE_UPSTREAM_OPENAI/ANTHROPIC (= LiteLLM). Upgrade path:
# if lore ever adds an official "route everything to upstream" flag, drop this
# patch. Fails the build loudly if the bundled layout changes.
RUN node -e 'const fs=require("fs");const p="/usr/local/lib/node_modules/@loreai/gateway/dist/index.cjs";let s=fs.readFileSync(p,"utf8");const re=/okr=\[[^\]]*\];/;if(!re.test(s))throw new Error("lore okr patch: pattern not found in bundle");fs.writeFileSync(p,s.replace(re,"okr=[];"));console.log("lore okr patch applied")'

EXPOSE 3207
# --host 0.0.0.0 is required: the CLI binds 127.0.0.1 by default, which
# would make the published port unreachable from the host.
CMD ["lore", "start", "--local", "--port", "3207", "--host", "0.0.0.0"]
