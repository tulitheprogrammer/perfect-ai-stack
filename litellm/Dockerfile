# LiteLLM proxy + Headroom compression callback (in-process, local-first).
#
# Pin the digest, not the floating `main-latest` tag. The tag moves silently:
# a routine rebuild jumped us onto a release that hard-refuses to start
# without LITELLM_MASTER_KEY (see docker-compose.yml), which is exactly the
# kind of break that only shows up when someone happens to rebuild.
#
# This is the multi-arch manifest list digest, so it resolves correctly on both
# arm64 and amd64. Bumping = `docker buildx imagetools inspect \
# ghcr.io/berriai/litellm:main-latest`, paste the new Digest, and re-run the
# checks in README's "Updating" note (models, generation, Headroom log lines).
FROM ghcr.io/berriai/litellm:main-latest@sha256:3def0387871a732a6d18b009576c4bf4313c54d448fa938a58f51cf189d1fa33

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
