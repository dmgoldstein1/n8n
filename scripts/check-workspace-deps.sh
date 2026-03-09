#!/usr/bin/env bash
# Validates that no package.json files use 'workspace:^'.
# Receives staged/listed package.json file paths as arguments.
# Used as a pre-commit hook via lefthook.

set -euo pipefail

FOUND_ERROR=false

for file in "$@"; do
	# Only process package.json files that exist
	[[ "$file" == *package.json ]] || continue
	[ -f "$file" ] || continue

	if grep -q '"workspace:\^"' "$file"; then
		if [ "$FOUND_ERROR" = false ]; then
			echo ""
			echo "ERROR: Found 'workspace:^' in package.json files."
			echo ""
			echo "Use 'workspace:*' instead to pin exact versions."
			echo "Using 'workspace:^' causes npm to resolve semver ranges when users"
			echo "install from npm, which can lead to version mismatches between"
			echo "@n8n/* packages and break n8n startup."
			echo ""
			FOUND_ERROR=true
		fi
	fi
done

if [ "$FOUND_ERROR" = true ]; then
	exit 1
fi
