#!/usr/bin/env bash
# Skip lefthook install in CI or Docker build environments.
# Otherwise installs lefthook git hooks for the local development environment.

set -euo pipefail

if [ -n "${CI:-}" ] || [ -n "${DOCKER_BUILD:-}" ]; then
	exit 0
fi

pnpm lefthook install
