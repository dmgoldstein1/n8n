#!/usr/bin/env bash
# Resets the repository by deleting all untracked files except for a few exceptions,
# then reinstalls dependencies and rebuilds.
#
# Usage:
#   bash scripts/reset.sh           - interactive (prompts for confirmation)
#   bash scripts/reset.sh -f        - skip confirmation
#   bash scripts/reset.sh --force   - skip confirmation

set -euo pipefail

EXCLUDE_PATTERNS=("/.vscode/" "/.idea/" ".env" "/.claude/")

EXCLUDE_FLAGS=()
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
	EXCLUDE_FLAGS+=("-e" "$pattern")
done

# Check for --force / -f flags
SKIP_CONFIRMATION=false
for arg in "$@"; do
	if [[ "$arg" == "--force" || "$arg" == "-f" ]]; then
		SKIP_CONFIRMATION=true
		break
	fi
done

PATTERNS_STR=""
for pattern in "${EXCLUDE_PATTERNS[@]}"; do
	PATTERNS_STR="${PATTERNS_STR:+$PATTERNS_STR, }\"$pattern\""
done

echo "This will delete all untracked files except for those matching the following patterns: $PATTERNS_STR."

if [ "$SKIP_CONFIRMATION" = false ]; then
	read -r -p "❓ Do you want to continue? (y/n) " answer
	if [[ ! "${answer:-}" =~ ^[yY]$|^$ ]]; then
		echo "Aborting..."
		exit 0
	fi
fi

echo "🧹 Cleaning untracked files..."
git clean -fxd "${EXCLUDE_FLAGS[@]}"

# Remove node_modules in case git clean didn't cover it
rm -rf node_modules

echo "⏬ Running pnpm install..."
pnpm install

echo "🏗️ Running pnpm build..."
pnpm build
