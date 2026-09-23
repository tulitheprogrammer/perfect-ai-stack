# LiteLLM proxy + Headroom compression callback (in-process, local-first).
FROM ghcr.io/berriai/litellm:main-latest

# The official image ships a venv at /app/.venv with no pip/uv, so bootstrap
# pip via ensurepip, then install headroom-ai into the same venv.
#
# Extras:
#   [proxy] -> Kompress-v2-base text compression on ONNX (no torch) + content detection
#   [code]  -> AST-aware code compression via tree-sitter
#
# Pin headroom-ai: it hooks LiteLLM's internal pre-call callback API, so an
# unannounced minor bump can silently change or break compression. Bump it
# deliberately and re-check the "Headroom: N->M" log lines, rather than letting
# every rebuild drift it.
RUN /app/.venv/bin/python -m ensurepip --upgrade \
    && /app/.venv/bin/python -m pip install --no-cache-dir "headroom-ai[proxy,code]==0.38.0"

# Registers HeadroomCallback as an instance before the proxy starts (see
# entrypoint.py for why the YAML callback form doesn't work).
COPY entrypoint.py /app/headroom_entrypoint.py
ENTRYPOINT ["/app/.venv/bin/python", "/app/headroom_entrypoint.py"]
