"""LiteLLM proxy entrypoint with the Headroom compression callback wired in.

Headroom must be registered as an *instance* (`litellm.callbacks =
[HeadroomCallback()]`), not via the YAML `callbacks` dotted-path form: LiteLLM
registers YAML custom callbacks as the class itself, and its async hook
dispatcher then fails with `object HeadroomCallback can't be used in 'await'
expression`, silently disabling compression.
"""
import logging
import sys

from headroom.integrations.litellm_callback import HeadroomCallback

import litellm

# Per-request compression stats ("Headroom: N->M tokens ...") show up in
# `docker compose logs litellm`. LiteLLM's logging setup mutes the headroom
# logger, so give it an explicit stderr handler.
hdr_logger = logging.getLogger("headroom")
hdr_logger.setLevel(logging.INFO)
hdr_logger.addHandler(logging.StreamHandler())
hdr_logger.propagate = False

litellm.callbacks = [HeadroomCallback()]

from litellm.proxy.proxy_cli import run_server  # noqa: E402

sys.exit(run_server())
