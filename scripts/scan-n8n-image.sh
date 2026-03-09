#!/usr/bin/env bash
# Scans the n8n Docker image for vulnerabilities using Trivy.
#
# Environment variables:
#   IMAGE_BASE_NAME     - Image base name (default: n8nio/n8n)
#   IMAGE_TAG           - Image tag (default: local)
#   TRIVY_IMAGE         - Trivy image to use (default: aquasec/trivy:latest)
#   TRIVY_SEVERITY      - Severities to scan (default: CRITICAL,HIGH,MEDIUM,LOW)
#   TRIVY_FORMAT        - Output format (default: table)
#   TRIVY_OUTPUT        - Output file path (optional)
#   TRIVY_TIMEOUT       - Scan timeout (default: 10m)
#   TRIVY_IGNORE_UNFIXED - Set to 'true' to ignore unpatched vulnerabilities
#   TRIVY_SCANNERS      - Scanners to use (default: vuln)
#   TRIVY_QUIET         - Set to 'true' for quiet output
#   TRIVY_VEX           - Path to VEX file (default: security/vex.openvex.json)
#   TRIVY_IGNORE_POLICY - Path to ignore policy (default: security/trivy-ignore-policy.rego)

set -euo pipefail

# ===== Colors =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
GRAY='\033[0;90m'
NC='\033[0m'

# ===== Configuration =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
	ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
	ROOT_DIR="$SCRIPT_DIR"
fi

IMAGE_BASE_NAME="${IMAGE_BASE_NAME:-n8nio/n8n}"
IMAGE_TAG="${IMAGE_TAG:-local}"
# Pin to a specific Trivy version to avoid mutable-tag risk.
# Override with TRIVY_IMAGE env var if you need a different version.
TRIVY_IMAGE="${TRIVY_IMAGE:-aquasec/trivy:0.69.2}"
SEVERITY="${TRIVY_SEVERITY:-CRITICAL,HIGH,MEDIUM,LOW}"
OUTPUT_FORMAT="${TRIVY_FORMAT:-table}"
OUTPUT_FILE="${TRIVY_OUTPUT:-}"
SCAN_TIMEOUT="${TRIVY_TIMEOUT:-10m}"
IGNORE_UNFIXED="${TRIVY_IGNORE_UNFIXED:-false}"
SCANNERS="${TRIVY_SCANNERS:-vuln}"
QUIET="${TRIVY_QUIET:-false}"

FULL_IMAGE_NAME="${IMAGE_BASE_NAME}:${IMAGE_TAG}"

# Resolve and validate file path (must be within repo root).
# Uses node's path.resolve for portability (realpath -m / readlink -f differ on macOS).
# Path is passed via an environment variable to avoid any shell-injection risk.
resolve_within_root() {
	local env_var="$1"
	local default_rel="$2"
	local env_val="${!env_var:-}"

	local resolved
	if [ -n "$env_val" ]; then
		resolved=$(N8N_RESOLVE_INPUT="$env_val" node -p "require('path').resolve(process.env.N8N_RESOLVE_INPUT)" 2>/dev/null) || resolved="$env_val"
	else
		resolved="$ROOT_DIR/$default_rel"
	fi

	# Strict containment: resolved must equal root or start with root + /
	# This prevents "$ROOT_DIR-other/..." from passing a prefix-only check.
	if [ "$resolved" != "$ROOT_DIR" ] && [[ "$resolved" != "$ROOT_DIR/"* ]]; then
		echo -e "${RED}Error: $env_var must resolve within the repository root${NC}" >&2
		exit 1
	fi

	echo "$resolved"
}

VEX_FILE=$(resolve_within_root "TRIVY_VEX" "security/vex.openvex.json")
IGNORE_POLICY_FILE=$(resolve_within_root "TRIVY_IGNORE_POLICY" "security/trivy-ignore-policy.rego")

print_header() {
	[ "$QUIET" = "true" ] && return
	echo ""
	echo -e "${BLUE}${BOLD}===== $1 =====${NC}"
}

print_summary() {
	[ "$QUIET" = "true" ] && return
	local status="$1"
	local scan_time="$2"
	local message="$3"

	echo ""
	echo -e "${BLUE}${BOLD}===== Scan Summary =====${NC}"
	if [ "$status" = "success" ]; then
		echo -e "${GREEN}${BOLD}$message${NC}"
		echo -e "${GREEN}   Scan time: ${scan_time}s${NC}"
	else
		echo -e "${YELLOW}${BOLD}$message${NC}"
		echo -e "${YELLOW}   Scan time: ${scan_time}s${NC}"
	fi

	if [ -n "$OUTPUT_FILE" ]; then
		local resolved_path
		if [[ "$OUTPUT_FILE" = /* ]]; then
			resolved_path="$OUTPUT_FILE"
		else
			resolved_path="$ROOT_DIR/$OUTPUT_FILE"
		fi
		echo -e "${GREEN}   Report saved to: $resolved_path${NC}"
	fi

	echo ""
	echo -e "${GRAY}Scan Configuration:${NC}"
	echo -e "${GRAY}  • Target Image: $FULL_IMAGE_NAME${NC}"
	echo -e "${GRAY}  • Severity Levels: $SEVERITY${NC}"
	echo -e "${GRAY}  • Scanners: $SCANNERS${NC}"
	echo -e "${GRAY}  • VEX file: $VEX_FILE${NC}"
	echo -e "${GRAY}  • Ignore policy: $IGNORE_POLICY_FILE${NC}"
	[ "$IGNORE_UNFIXED" = "true" ] && echo -e "${GRAY}  • Ignored unfixed: yes${NC}"
	echo -e "${BLUE}${BOLD}========================${NC}"
}

# ===== Main =====
print_header "Trivy Security Scan for n8n Image"

# Check docker
if ! command -v docker >/dev/null 2>&1; then
	echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
	exit 1
fi

# Check image exists
if ! docker image inspect "$FULL_IMAGE_NAME" >/dev/null 2>&1; then
	echo -e "${RED}Error: Docker image '$FULL_IMAGE_NAME' not found${NC}"
	echo -e "${YELLOW}Please run dockerize-n8n.sh first!${NC}"
	exit 1
fi

# Pull latest Trivy image silently
docker pull "$TRIVY_IMAGE" >/dev/null 2>&1 || true

# Build Trivy command arguments
TRIVY_ARGS=(
	run --rm
	-v /var/run/docker.sock:/var/run/docker.sock
	-v "${VEX_FILE}:/vex.openvex.json:ro"
	-v "${IGNORE_POLICY_FILE}:/trivy-ignore-policy.rego:ro"
	"$TRIVY_IMAGE"
	image
	--severity "$SEVERITY"
	--format "$OUTPUT_FORMAT"
	--timeout "$SCAN_TIMEOUT"
	--scanners "$SCANNERS"
	--no-progress
	--vex /vex.openvex.json
	--ignore-policy /trivy-ignore-policy.rego
)

[ "$IGNORE_UNFIXED" = "true" ] && TRIVY_ARGS+=(--ignore-unfixed)
[ "$QUIET" = "true" ] && [ "$OUTPUT_FORMAT" = "table" ] && TRIVY_ARGS+=(--quiet)

# Handle output file
if [ -n "$OUTPUT_FILE" ]; then
	resolved_output_path="$OUTPUT_FILE"
	[[ "$OUTPUT_FILE" != /* ]] && resolved_output_path="$ROOT_DIR/$OUTPUT_FILE"
	mkdir -p "$(dirname "$resolved_output_path")"
	TRIVY_ARGS+=(--output /tmp/trivy-output -v "${resolved_output_path}:/tmp/trivy-output")
fi

TRIVY_ARGS+=("$FULL_IMAGE_NAME")

# Run scan
START_TIME=$(date +%s)

if docker "${TRIVY_ARGS[@]}"; then
	END_TIME=$(date +%s)
	SCAN_TIME=$(( END_TIME - START_TIME ))
	print_summary "success" "$SCAN_TIME" "✅ Security scan completed successfully"
	exit 0
else
	EXIT_CODE=$?
	END_TIME=$(date +%s)
	SCAN_TIME=$(( END_TIME - START_TIME ))

	if [ "$EXIT_CODE" -eq 1 ]; then
		print_summary "warning" "$SCAN_TIME" "⚠️  Vulnerabilities found!"
		exit 1
	else
		echo -e "${RED}❌ Scan failed${NC}"
		exit "$EXIT_CODE"
	fi
fi
