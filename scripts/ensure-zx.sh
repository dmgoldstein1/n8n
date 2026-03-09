#!/usr/bin/env bash
# Ensures zx is available in node_modules/.bin/zx.
# If not found, runs pnpm install so the binary is available for subsequent zx calls.

set -euo pipefail

ZX_PATH="node_modules/.bin/zx"

if [ ! -f "$ZX_PATH" ]; then
	pnpm --frozen-lockfile --filter n8n-monorepo install
fi
