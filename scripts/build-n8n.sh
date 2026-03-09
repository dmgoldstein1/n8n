#!/usr/bin/env bash
# Builds the n8n application for production.
#
# Steps:
#   1. Clean previous build output
#   2. Run pnpm install and build
#   3. Generate third-party licenses (unless N8N_SKIP_LICENSES=true)
#   4. Prepare for deployment - clean package.json files
#   5. Create a pruned production deployment in 'compiled'
#
# Environment variables:
#   CI=true                    - enables CI mode (no backups, less verbose)
#   INCLUDE_TEST_CONTROLLER    - keep test controller in CI builds
#   N8N_SKIP_LICENSES=true     - skip third-party license generation

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
IS_CI="${CI:-}"
EXCLUDE_TEST_CONTROLLER=false
if [ "${CI:-}" = "true" ] && [ "${INCLUDE_TEST_CONTROLLER:-}" != "true" ]; then
	EXCLUDE_TEST_CONTROLLER=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IS_IN_SCRIPTS_DIR=false
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
	IS_IN_SCRIPTS_DIR=true
fi

if [ "$IS_IN_SCRIPTS_DIR" = true ]; then
	ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
	ROOT_DIR="$SCRIPT_DIR"
fi

COMPILED_APP_DIR="$ROOT_DIR/compiled"
COMPILED_TASK_RUNNER_DIR="$ROOT_DIR/dist/task-runner-javascript"
CLI_DIR="$ROOT_DIR/packages/cli"

# Patches to keep during deployment
PATCHES_TO_KEEP=("pdfjs-dist" "pkce-challenge" "bull")

# ===== Timer Functions =====
declare -A TIMER_STARTS=()

start_timer() {
	TIMER_STARTS["$1"]=$(date +%s)
}

get_elapsed_time() {
	local start="${TIMER_STARTS[${1}]:-0}"
	local now
	now=$(date +%s)
	echo $((now - start))
}

format_duration() {
	local seconds=$1
	local hours=$(( seconds / 3600 ))
	local minutes=$(( (seconds % 3600) / 60 ))
	local secs=$(( seconds % 60 ))

	if [ "$hours" -gt 0 ]; then
		echo "${hours}h ${minutes}m ${secs}s"
	elif [ "$minutes" -gt 0 ]; then
		echo "${minutes}m ${secs}s"
	else
		echo "${secs}s"
	fi
}

print_header() {
	echo ""
	echo -e "${BLUE}${BOLD}===== $1 =====${NC}"
}

print_divider() {
	echo -e "${GRAY}-----------------------------------------------${NC}"
}

# ===== Main Build Process =====
print_header "n8n Build & Production Preparation"
echo "INFO: Output Directory: $COMPILED_APP_DIR"
print_divider

start_timer "total_build"

# 0. Clean previous build output
echo -e "${YELLOW}INFO: Cleaning previous output directory: $COMPILED_APP_DIR...${NC}"
rm -rf "$COMPILED_APP_DIR"

echo -e "${YELLOW}INFO: Cleaning previous task runner output directory: $COMPILED_TASK_RUNNER_DIR...${NC}"
rm -rf "$COMPILED_TASK_RUNNER_DIR"
print_divider

# 1. Local Application Pre-build
echo -e "${YELLOW}INFO: Starting local application pre-build...${NC}"
start_timer "package_build"

echo -e "${YELLOW}INFO: Running pnpm install and build...${NC}"

(
	cd "$ROOT_DIR"
	pnpm install --frozen-lockfile
	pnpm build --summarize

	# Generate third-party licenses for production builds
	if [ "${N8N_SKIP_LICENSES:-}" != "true" ]; then
		echo -e "${YELLOW}INFO: Generating third-party licenses...${NC}"
		if bash "$SCRIPT_DIR/generate-third-party-licenses.sh"; then
			echo -e "${GREEN}✅ Third-party licenses generated successfully${NC}"
		else
			echo -e "${YELLOW}⚠️  Warning: Third-party license generation failed, continuing build...${NC}"
		fi
	else
		echo -e "${GRAY}INFO: Skipping license generation (N8N_SKIP_LICENSES=true)${NC}"
	fi
)

echo -e "${GREEN}✅ pnpm install and build completed${NC}"

PACKAGE_BUILD_TIME=$(get_elapsed_time "package_build")
echo -e "${GREEN}✅ Package build completed in $(format_duration "$PACKAGE_BUILD_TIME")${NC}"
print_divider

# 2. Prepare for deployment - clean package.json files
echo -e "${YELLOW}INFO: Performing pre-deploy cleanup on package.json files...${NC}"

# Find and backup package.json files (only locally, not in CI)
PACKAGE_JSON_FILES=()
while IFS= read -r -d '' file; do
	PACKAGE_JSON_FILES+=("$file")
done < <(find "$ROOT_DIR" -name "package.json" \
	-not -path "*/node_modules/*" \
	-not -path "$ROOT_DIR/compiled/*" \
	-type f -print0)

if [ "${CI:-}" != "true" ]; then
	for file in "${PACKAGE_JSON_FILES[@]}"; do
		[ -n "$file" ] && cp "$file" "${file}.bak"
	done
fi

# Run FE trim script
node "$ROOT_DIR/.github/scripts/trim-fe-packageJson.js"

echo -e "${YELLOW}INFO: Performing selective patch cleanup...${NC}"

PACKAGE_JSON_PATH="$ROOT_DIR/package.json"

if [ -f "$PACKAGE_JSON_PATH" ]; then
	PATCHES_LIST=$(printf '%s,' "${PATCHES_TO_KEEP[@]}")
	PATCHES_LIST="${PATCHES_LIST%,}"

	node -e "
const fs = require('fs');
const filePath = '$PACKAGE_JSON_PATH';
const keepList = '$PATCHES_LIST'.split(',');
const content = fs.readFileSync(filePath, 'utf8');
const pkgJson = JSON.parse(content);
if (pkgJson.pnpm && pkgJson.pnpm.patchedDependencies) {
  const filtered = {};
  for (const [key, value] of Object.entries(pkgJson.pnpm.patchedDependencies)) {
    if (keepList.some(prefix => key.startsWith(prefix.trim()))) {
      filtered[key] = value;
    }
  }
  pkgJson.pnpm.patchedDependencies = filtered;
}
fs.writeFileSync(filePath, JSON.stringify(pkgJson, null, 2), 'utf8');
" || { echo -e "${RED}ERROR: Failed to cleanup patches in package.json${NC}"; exit 1; }

	echo -e "${GREEN}✅ Kept backend patches: ${PATCHES_LIST}${NC}"
	echo -e "${GRAY}Removed FE/dev patches not in the keep list: $PATCHES_LIST${NC}"
fi

echo -e "${YELLOW}INFO: Creating pruned production deployment in '$COMPILED_APP_DIR'...${NC}"
start_timer "package_deploy"

mkdir -p "$COMPILED_APP_DIR"

if [ "$EXCLUDE_TEST_CONTROLLER" = true ]; then
	CLI_PKG="$ROOT_DIR/packages/cli/package.json"
	node -e "
const fs = require('fs');
const content = fs.readFileSync('$CLI_PKG', 'utf8');
const pkg = JSON.parse(content);
pkg.files.push('!dist/**/e2e.*');
fs.writeFileSync('$CLI_PKG', JSON.stringify(pkg, null, 2));
"
	echo -e "${GRAY}  - Excluded test controller from packages/cli/package.json${NC}"
fi

(
	cd "$ROOT_DIR"
	NODE_ENV=production DOCKER_BUILD=true \
		pnpm --filter=n8n --prod --legacy deploy --no-optional "$COMPILED_APP_DIR"
)

mkdir -p "$COMPILED_TASK_RUNNER_DIR"

echo -e "${YELLOW}INFO: Creating JavaScript task runner deployment in '$COMPILED_TASK_RUNNER_DIR'...${NC}"

(
	cd "$ROOT_DIR"
	NODE_ENV=production DOCKER_BUILD=true \
		pnpm --filter=@n8n/task-runner --prod --legacy deploy --no-optional "$COMPILED_TASK_RUNNER_DIR"
)

PACKAGE_DEPLOY_TIME=$(get_elapsed_time "package_deploy")

# Restore package.json files (only locally, not in CI)
if [ "${CI:-}" != "true" ]; then
	for file in "${PACKAGE_JSON_FILES[@]}"; do
		if [ -n "$file" ] && [ -f "${file}.bak" ]; then
			mv "${file}.bak" "$file"
		fi
	done
fi

# Calculate output sizes
COMPILED_APP_SIZE=$(du -sh "$COMPILED_APP_DIR" | cut -f1)
COMPILED_TASK_RUNNER_SIZE=$(du -sh "$COMPILED_TASK_RUNNER_DIR" | cut -f1)

# Copy third-party licenses if they exist
LICENSES_SOURCE="$CLI_DIR/THIRD_PARTY_LICENSES.md"
if [ -f "$LICENSES_SOURCE" ]; then
	cp "$LICENSES_SOURCE" "$COMPILED_APP_DIR/THIRD_PARTY_LICENSES.md"
fi

# Generate build manifests
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
TOTAL_BUILD_TIME=$(get_elapsed_time "total_build")

cat > "$COMPILED_APP_DIR/build-manifest.json" << EOF
{
  "buildTime": "$BUILD_TIME",
  "artifactSize": "$COMPILED_APP_SIZE",
  "buildDuration": {
    "packageBuild": $PACKAGE_BUILD_TIME,
    "packageDeploy": $PACKAGE_DEPLOY_TIME,
    "total": $TOTAL_BUILD_TIME
  }
}
EOF

cat > "$COMPILED_TASK_RUNNER_DIR/build-manifest.json" << EOF
{
  "buildTime": "$BUILD_TIME",
  "artifactSize": "$COMPILED_TASK_RUNNER_SIZE",
  "buildDuration": {
    "packageBuild": $PACKAGE_BUILD_TIME,
    "packageDeploy": $PACKAGE_DEPLOY_TIME,
    "total": $TOTAL_BUILD_TIME
  }
}
EOF

echo -e "${GREEN}✅ Package deployment completed in $(format_duration "$PACKAGE_DEPLOY_TIME")${NC}"
echo "INFO: Size of $COMPILED_APP_DIR: $COMPILED_APP_SIZE"
print_divider

# ===== Final Output =====
echo ""
echo -e "${GREEN}${BOLD}================ BUILD SUMMARY ================${NC}"
echo -e "${GREEN}✅ n8n built successfully!${NC}"
echo ""
echo -e "${BLUE}📦 Build Output:${NC}"
echo -e "${GREEN}   n8n:${NC}"
echo "   Directory:      $COMPILED_APP_DIR"
echo "   Size:           $COMPILED_APP_SIZE"
echo ""
echo -e "${GREEN}   task-runner-javascript:${NC}"
echo "   Directory:      $COMPILED_TASK_RUNNER_DIR"
echo "   Size:           $COMPILED_TASK_RUNNER_SIZE"
echo ""
echo -e "${BLUE}⏱️  Build Times:${NC}"
echo "   Package Build:  $(format_duration "$PACKAGE_BUILD_TIME")"
echo "   Package Deploy: $(format_duration "$PACKAGE_DEPLOY_TIME")"
echo -e "${GRAY}   -----------------------------${NC}"
echo -e "${BOLD}   Total Time:     $(format_duration "$TOTAL_BUILD_TIME")${NC}"
echo ""
echo -e "${BLUE}📋 Build Manifests:${NC}"
echo "   $COMPILED_APP_DIR/build-manifest.json"
echo "   $COMPILED_TASK_RUNNER_DIR/build-manifest.json"
echo -e "${GREEN}${BOLD}==============================================${NC}"
