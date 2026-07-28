#!/bin/sh
# Pre-commit hook: run lat check to prevent doc-code drift.
# Installed by `ai-stack setup-lat` or inlined by setup-lat.sh.
exec lat check 2>&1
