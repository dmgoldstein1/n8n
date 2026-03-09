#!/usr/bin/env bash
# Runs a binary from a given directory in a cross-platform-friendly way.
# On Linux/macOS the binary is executed directly with a ./ prefix.
#
# Usage:
#   bash scripts/os-normalize.sh --dir <dir> <run>
#   bash scripts/os-normalize.sh --dir <dir> -- <run> [args...]

set -euo pipefail

DIR="."
RUN=""
ARGS=()

# Parse arguments
i=1
while [ $i -le $# ]; do
	arg="${!i}"
	case "$arg" in
	--dir)
		i=$((i + 1))
		DIR="${!i}"
		;;
	--)
		i=$((i + 1))
		RUN="${!i}"
		i=$((i + 1))
		while [ $i -le $# ]; do
			ARGS+=("${!i}")
			i=$((i + 1))
		done
		break
		;;
	*)
		if [ -z "$RUN" ]; then
			RUN="$arg"
		else
			ARGS+=("$arg")
		fi
		;;
	esac
	i=$((i + 1))
done

if [ -z "$DIR" ] || [ -z "$RUN" ]; then
	echo "Usage: $0 --dir <dir> <run>"
	echo "Usage (with args): $0 --dir <dir> -- <run> [args...]"
	exit 2
fi

cd "$DIR" || exit 1

CMD="./$RUN"

echo "$ Running (dir: $DIR) $CMD ${ARGS[*]+"${ARGS[*]}"}"
exec "$CMD" "${ARGS[@]+"${ARGS[@]}"}"
