#!/bin/sh
# Pre-commit hook: run lat check to prevent doc-code drift.
# Installed by `ai-stack setup-lat` (idempotent — re-runs are no-ops).
exec lat check 2>&1
