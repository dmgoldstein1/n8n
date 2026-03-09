#!/usr/bin/env bash
# Build n8n and runners Docker images locally.
#
# This script simulates the CI build process for local testing.
# Default output: 'n8nio/n8n:local' and 'n8nio/runners:local'
# Override with IMAGE_BASE_NAME and IMAGE_TAG environment variables.
#
# Usage:
#   bash scripts/dockerize-n8n.sh           - Build images only
#   bash scripts/dockerize-n8n.sh --run     - Build and run n8n container with owner creation
#   bash scripts/dockerize-n8n.sh --run-stop - Stop any existing n8n container before running
#
# Environment variables for owner creation (when --run is used):
#   N8N_DATA_VOLUME     - Docker volume name (default: n8n-data)
#   N8N_CREATE_OWNER    - Set to 'false' to disable owner creation (default: true)
#   N8N_OWNER_EMAIL     - Owner email (default: techyactor15@gmail.com)
#   N8N_OWNER_FIRSTNAME - Owner first name (default: Daniel)
#   N8N_OWNER_LASTNAME  - Owner last name (default: Goldstein)
#   N8N_OWNER_HASH      - Pre-hashed bcrypt password (required for owner creation)
#   CONTAINER_ENGINE    - Override container engine: 'docker' or 'podman'

set -euo pipefail

# ===== Colors =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
GRAY='\033[0;90m'
NC='\033[0m'

# ===== Defaults =====
DEFAULT_OWNER_EMAIL="techyactor15@gmail.com"
DEFAULT_OWNER_FIRSTNAME="Daniel"
DEFAULT_OWNER_LASTNAME="Goldstein"
# Default bcrypt hash for password: ExamplePassword123!
DEFAULT_OWNER_HASH='$2a$10$jTnfKXZCiUQwQnG3OOYnVOYHthaNHhK3iPcKq6uMJ8MwcYc80iw5K'

# ===== Script Setup =====
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
	ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
	ROOT_DIR="$SCRIPT_DIR"
fi

N8N_DOCKERFILE="$ROOT_DIR/docker/images/n8n/Dockerfile"
RUNNERS_DOCKERFILE="$ROOT_DIR/docker/images/runners/Dockerfile"
BUILD_CONTEXT="$ROOT_DIR"
COMPILED_APP_DIR="$ROOT_DIR/compiled"
COMPILED_TASK_RUNNER_DIR="$ROOT_DIR/dist/task-runner-javascript"

IMAGE_BASE_NAME="${IMAGE_BASE_NAME:-n8nio/n8n}"
IMAGE_TAG="${IMAGE_TAG:-local}"
N8N_IMAGE="${IMAGE_BASE_NAME}:${IMAGE_TAG}"

RUNNERS_IMAGE_BASE_NAME="${RUNNERS_IMAGE_BASE_NAME:-n8nio/runners}"
RUNNERS_IMAGE="${RUNNERS_IMAGE_BASE_NAME}:${IMAGE_TAG}"

# Parse flags
RUN_MODE=""
for arg in "$@"; do
	case "$arg" in
	--run)       RUN_MODE="run" ;;
	--run-stop)  RUN_MODE="run-stop" ;;
	esac
done

# ===== Helper Functions =====

get_docker_platform() {
	local arch
	arch=$(uname -m)
	case "$arch" in
	x86_64)  echo "linux/amd64" ;;
	aarch64|arm64) echo "linux/arm64" ;;
	*)
		echo -e "${RED}ERROR: Unsupported architecture: $arch. Only x86_64 and arm64 are supported.${NC}" >&2
		exit 1
		;;
	esac
}

format_duration() {
	echo "${1}s"
}

get_image_size() {
	local image_name="$1"
	local size
	size=$(docker images "$image_name" --format "{{.Size}}" 2>/dev/null | head -1)
	echo "${size:-Unknown}"
}

command_exists() {
	command -v "$1" >/dev/null 2>&1
}

is_docker_podman_shim() {
	docker version 2>/dev/null | grep -qi "podman"
}

get_container_engine() {
	local override="${CONTAINER_ENGINE:-}"
	if [ -n "$override" ]; then
		local lower_override
		lower_override=$(echo "$override" | tr '[:upper:]' '[:lower:]')
		if [[ "$lower_override" == "docker" || "$lower_override" == "podman" ]]; then
			echo "$lower_override"
			return
		fi
	fi

	local has_docker=false
	local has_podman=false
	command_exists docker && has_docker=true
	command_exists podman && has_podman=true

	if [ "$has_docker" = true ]; then
		if [ "$has_podman" = true ] && is_docker_podman_shim; then
			echo "podman"
			return
		fi
		echo "docker"
		return
	fi

	if [ "$has_podman" = true ]; then
		echo "podman"
		return
	fi

	echo -e "${RED}ERROR: No supported container engine found. Please install Docker or Podman.${NC}" >&2
	exit 1
}

check_prerequisites() {
	if [ ! -d "$COMPILED_APP_DIR" ]; then
		echo -e "${RED}Error: Compiled app directory not found at $COMPILED_APP_DIR${NC}"
		echo -e "${YELLOW}Please run build-n8n.sh first!${NC}"
		exit 1
	fi

	if [ ! -d "$COMPILED_TASK_RUNNER_DIR" ]; then
		echo -e "${RED}Error: Task runner directory not found at $COMPILED_TASK_RUNNER_DIR${NC}"
		echo -e "${YELLOW}Please run build-n8n.sh first!${NC}"
		exit 1
	fi

	if ! command_exists docker && ! command_exists podman; then
		echo -e "${RED}Error: Neither Docker nor Podman is installed or in PATH${NC}"
		exit 1
	fi
}

build_docker_image() {
	local name="$1"
	local dockerfile_path="$2"
	local full_image_name="$3"
	local platform="$4"

	local start_time
	start_time=$(date +%s)

	local container_engine
	container_engine=$(get_container_engine)

	# Push directly if image name contains a registry (more than two slashes)
	local should_push=false
	local slash_count
	slash_count=$(echo "$full_image_name" | tr -cd '/' | wc -c)
	[ "$slash_count" -ge 2 ] && should_push=true

	# All informational output goes to stderr so it isn't captured when caller uses $()
	echo -e "${YELLOW}INFO: Building $name Docker image using $container_engine...${NC}" >&2
	if [ "$should_push" = true ]; then
		echo -e "${YELLOW}INFO: Registry detected - pushing directly to $full_image_name${NC}" >&2
	fi

	if [ "$container_engine" = "podman" ]; then
		podman build \
			--platform "$platform" \
			--build-arg "TARGETPLATFORM=$platform" \
			-t "$full_image_name" \
			-f "$dockerfile_path" \
			"$BUILD_CONTEXT"
	else
		local output_flag="--load"
		[ "$should_push" = true ] && output_flag="--push"

		docker buildx build \
			--platform "$platform" \
			--build-arg "TARGETPLATFORM=$platform" \
			-t "$full_image_name" \
			-f "$dockerfile_path" \
			--provenance=false \
			"$output_flag" \
			"$BUILD_CONTEXT"
	fi || {
		echo -e "${RED}ERROR: $name Docker build failed${NC}" >&2
		exit 1
	}

	local end_time
	end_time=$(date +%s)
	# Print only the duration to stdout (captured by caller)
	echo "$(( end_time - start_time ))s"
}

display_summary() {
	local n8n_image="$1"
	local n8n_platform="$2"
	local n8n_size="$3"
	local n8n_build_time="$4"
	local runners_image="$5"
	local runners_platform="$6"
	local runners_size="$7"
	local runners_build_time="$8"

	echo ""
	echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"
	echo -e "${GREEN}${BOLD}           DOCKER BUILD COMPLETE${NC}"
	echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"

	for img_info in "${n8n_image}|${n8n_platform}|${n8n_size}|${n8n_build_time}" \
		"${runners_image}|${runners_platform}|${runners_size}|${runners_build_time}"; do
		IFS='|' read -r img_name img_platform img_size img_build_time <<< "$img_info"
		echo -e "${GREEN}✅ Image built: $img_name${NC}"
		echo "   Platform: $img_platform"
		echo "   Size: $img_size"
		echo "   Build time: $img_build_time"
		echo ""
	done

	echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════${NC}"
}

stop_existing_container() {
	local container_name="n8n-n8n-1"
	if docker ps -a --filter "name=$container_name" --format "{{.Names}}" | grep -q "^${container_name}$"; then
		echo -e "${YELLOW}INFO: Stopping existing container: $container_name${NC}"
		docker stop "$container_name" >/dev/null
		docker rm "$container_name" >/dev/null
		echo -e "${GREEN}✅ Removed existing container: $container_name${NC}"
	else
		echo -e "${GRAY}INFO: No existing container to remove${NC}"
	fi
}

run_n8n_container() {
	local container_name="n8n-n8n-1"
	local volume_name="${N8N_DATA_VOLUME:-n8n-data}"

	# Default to creating owner unless explicitly disabled
	local create_owner="true"
	if [ "${N8N_CREATE_OWNER:-}" = "false" ]; then
		create_owner="false"
	fi

	local owner_email="${N8N_OWNER_EMAIL:-$DEFAULT_OWNER_EMAIL}"
	local owner_firstname="${N8N_OWNER_FIRSTNAME:-$DEFAULT_OWNER_FIRSTNAME}"
	local owner_lastname="${N8N_OWNER_LASTNAME:-$DEFAULT_OWNER_LASTNAME}"
	local owner_hash="${N8N_OWNER_HASH:-$DEFAULT_OWNER_HASH}"

	echo -e "${BLUE}${BOLD}===== Running n8n Container =====${NC}"
	echo "INFO: Container name: $container_name"
	echo "INFO: Volume: $volume_name"
	echo "INFO: Image: $N8N_IMAGE"
	echo "INFO: Create owner: $create_owner"
	if [ "$create_owner" = "true" ]; then
		echo "INFO: Owner email: $owner_email"
	fi
	echo -e "${GRAY}-----------------------------------------------${NC}"

	# Stop existing container if in run-stop mode
	if [ "$RUN_MODE" = "run-stop" ]; then
		stop_existing_container
	fi

	# Check if volume exists, create if not
	if docker volume inspect "$volume_name" >/dev/null 2>&1; then
		echo -e "${GRAY}INFO: Volume '$volume_name' exists${NC}"
	else
		echo -e "${YELLOW}INFO: Creating volume: $volume_name${NC}"
		docker volume create "$volume_name"
	fi

	# Run the container
	docker run -d \
		--name "$container_name" \
		-p 5678:5678 \
		-v "${volume_name}:/home/node/.n8n" \
		-e "N8N_CREATE_OWNER=$create_owner" \
		-e "N8N_OWNER_EMAIL=$owner_email" \
		-e "N8N_OWNER_FIRSTNAME=$owner_firstname" \
		-e "N8N_OWNER_LASTNAME=$owner_lastname" \
		-e "N8N_OWNER_HASH=$owner_hash" \
		-e "NSOLID_APPNAME=n8n" \
		-e "NSOLID_TAGS=production,n8n,workflow-automation" \
		-e "NSOLID_TRACING_ENABLED=1" \
		-e "NSOLID_OTLP=otlp" \
		-e "NODE_ENV=production" \
		"$N8N_IMAGE"

	echo -e "${GREEN}✅ Container started: $container_name${NC}"
	echo -e "${GREEN}   n8n UI: http://localhost:5678${NC}"

	if [ "$create_owner" = "true" ]; then
		echo -e "${GREEN}   Owner email: $owner_email${NC}"
	fi
}

# ===== Main =====
PLATFORM=$(get_docker_platform)

main() {
	if [ -n "$RUN_MODE" ]; then
		echo -e "${BLUE}${BOLD}===== Building n8n Docker Image =====${NC}"
		echo "INFO: n8n Image: $N8N_IMAGE"
		echo "INFO: Platform: $PLATFORM"
		echo -e "${GRAY}-----------------------------------------------${NC}"

		check_prerequisites

		N8N_BUILD_TIME=$(build_docker_image "n8n" "$N8N_DOCKERFILE" "$N8N_IMAGE" "$PLATFORM")
		N8N_IMAGE_SIZE=$(get_image_size "$N8N_IMAGE")

		echo -e "${GREEN}✅ n8n image built: $N8N_IMAGE${NC}"
		echo "   Size: $N8N_IMAGE_SIZE"
		echo "   Build time: $N8N_BUILD_TIME"
		echo ""

		run_n8n_container
		return
	fi

	# Build-only mode
	echo -e "${BLUE}${BOLD}===== Docker Build for n8n & Runners =====${NC}"
	echo "INFO: n8n Image: $N8N_IMAGE"
	echo "INFO: Runners Image: $RUNNERS_IMAGE"
	echo "INFO: Platform: $PLATFORM"
	echo -e "${GRAY}-----------------------------------------------${NC}"

	check_prerequisites

	N8N_BUILD_TIME=$(build_docker_image "n8n" "$N8N_DOCKERFILE" "$N8N_IMAGE" "$PLATFORM")
	RUNNERS_BUILD_TIME=$(build_docker_image "runners" "$RUNNERS_DOCKERFILE" "$RUNNERS_IMAGE" "$PLATFORM")

	N8N_IMAGE_SIZE=$(get_image_size "$N8N_IMAGE")
	RUNNERS_IMAGE_SIZE=$(get_image_size "$RUNNERS_IMAGE")

	# Write docker build manifest
	BUILD_TS=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
	cat > "$BUILD_CONTEXT/docker-build-manifest.json" << EOF
{
  "buildTime": "$BUILD_TS",
  "platform": "$PLATFORM",
  "images": [
    {
      "imageName": "$N8N_IMAGE",
      "size": "$N8N_IMAGE_SIZE",
      "buildTime": "$N8N_BUILD_TIME"
    },
    {
      "imageName": "$RUNNERS_IMAGE",
      "size": "$RUNNERS_IMAGE_SIZE",
      "buildTime": "$RUNNERS_BUILD_TIME"
    }
  ]
}
EOF

	display_summary \
		"$N8N_IMAGE" "$PLATFORM" "$N8N_IMAGE_SIZE" "$N8N_BUILD_TIME" \
		"$RUNNERS_IMAGE" "$PLATFORM" "$RUNNERS_IMAGE_SIZE" "$RUNNERS_BUILD_TIME"
}

main
