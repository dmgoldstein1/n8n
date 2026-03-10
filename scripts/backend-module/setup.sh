#!/usr/bin/env bash
# Sets up a new backend module scaffold in packages/cli/src/modules/my-feature
# by copying template files from scripts/backend-module.
#
# Usage: bash scripts/backend-module/setup.sh

set -euo pipefail

MODULE_NAME="my-feature"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "backend-module" ]; then
	ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
else
	ROOT_DIR="$SCRIPT_DIR"
fi

MODULE_DIR="$ROOT_DIR/packages/cli/src/modules/$MODULE_NAME"
TESTS_DIR="$MODULE_DIR/__tests__"
TEMPLATE_DIR="$SCRIPT_DIR"

mkdir -p "$MODULE_DIR"
mkdir -p "$TESTS_DIR"

declare -a TEMPLATE_FILES=(
	"$MODULE_NAME.config.template:$MODULE_DIR/$MODULE_NAME.config.ts"
	"$MODULE_NAME.controller.template:$MODULE_DIR/$MODULE_NAME.controller.ts"
	"$MODULE_NAME.entity.template:$MODULE_DIR/$MODULE_NAME.entity.ts"
	"$MODULE_NAME.module.template:$MODULE_DIR/$MODULE_NAME.module.ts"
	"$MODULE_NAME.repository.template:$MODULE_DIR/$MODULE_NAME.repository.ts"
	"$MODULE_NAME.service.template:$MODULE_DIR/$MODULE_NAME.service.ts"
	"$MODULE_NAME.service.test.template:$TESTS_DIR/$MODULE_NAME.service.test.ts"
)

for entry in "${TEMPLATE_FILES[@]}"; do
	template="${entry%%:*}"
	target="${entry##*:}"
	cp "$TEMPLATE_DIR/$template" "$target"
done

echo "Backend module setup done at: $MODULE_DIR"
