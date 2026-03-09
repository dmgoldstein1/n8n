#!/usr/bin/env bash
# Formats files outside of /packages using prettier (for .yml) and biome (for .js/.json/.ts).
# Skips .git, node_modules, packages, and .turbo directories.

set -euo pipefail

PRETTIER="node_modules/.bin/prettier"
BIOME="node_modules/.bin/biome"

for bin in "$PRETTIER" "$BIOME"; do
	if [ ! -f "$bin" ]; then
		echo "$(basename "$bin") not found at path: $bin"
		echo "Please run \`pnpm i\` first"
		exit 1
	fi
done

PRETTIER_CONFIG=".prettierrc.js"
BIOME_CONFIG="biome.jsonc"
PRETTIER_IGNORE=".prettierignore"

ROOT_DIRS_TO_SKIP=(".git" "node_modules" "packages" ".turbo")

PRETTIER_TARGETS=()
BIOME_TARGETS=()

# Build -prune flags for find to skip root-level directories
PRUNE_ARGS=()
for dir in "${ROOT_DIRS_TO_SKIP[@]}"; do
	PRUNE_ARGS+=(-path "./$dir" -prune -o)
done

# Collect files for prettier (.yml)
while IFS= read -r -d '' file; do
	PRETTIER_TARGETS+=("$file")
done < <(find . "${PRUNE_ARGS[@]}" -name "*.yml" -type f -print0 2>/dev/null)

# Collect files for biome (.js, .json, .ts)
while IFS= read -r -d '' file; do
	BIOME_TARGETS+=("$file")
done < <(find . "${PRUNE_ARGS[@]}" \( -name "*.js" -o -name "*.json" -o -name "*.ts" \) -type f -print0 2>/dev/null)

if [ ${#PRETTIER_TARGETS[@]} -gt 0 ]; then
	"$PRETTIER" \
		--config "$PRETTIER_CONFIG" \
		--ignore-path "$PRETTIER_IGNORE" \
		--write \
		"${PRETTIER_TARGETS[@]}"
fi

if [ ${#BIOME_TARGETS[@]} -gt 0 ]; then
	"$BIOME" format --write "--config-path=$BIOME_CONFIG" "${BIOME_TARGETS[@]}"
fi
