#!/usr/bin/env bash
# docker-helper.sh - Docker availability and management utilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

source "${SCRIPT_DIR}/config.sh"

# Docker image name prefix
DOCKER_IMAGE_PREFIX="${DOCKER_IMAGE_PREFIX:-ssl-check}"

# Check if Docker is installed
check_docker_installed() {
    command -v docker >/dev/null 2>&1
}

# Check if Docker daemon is running
check_docker_running() {
    if ! check_docker_installed; then
        return 1
    fi

    docker info >/dev/null 2>&1
}

# Get Docker version
get_docker_version() {
    if check_docker_installed; then
        docker --version 2>/dev/null | awk '{print $3}' | tr -d ','
    else
        echo "not_installed"
    fi
}

# Check if a Docker image exists locally
image_exists() {
    local image="$1"
    docker image inspect "$image" >/dev/null 2>&1
}

# Build a Docker image for Python version
build_python_image() {
    local version="$1"
    local image_name="${DOCKER_IMAGE_PREFIX}-python:${version}"
    local dockerfile="${PROJECT_ROOT}/docker/python/Dockerfile.${version}"

    log_info "Building Docker image: $image_name"

    # Create Dockerfile if it doesn't exist
    if [[ ! -f "$dockerfile" ]]; then
        create_python_dockerfile "$version"
    fi

    docker build -t "$image_name" -f "$dockerfile" "${PROJECT_ROOT}/python" >/dev/null 2>&1
}

# Create a Python Dockerfile for a specific version
create_python_dockerfile() {
    local version="$1"
    local dockerfile="${PROJECT_ROOT}/docker/python/Dockerfile.${version}"

    mkdir -p "${PROJECT_ROOT}/docker/python"

    cat > "$dockerfile" <<EOF
FROM python:${version}-slim

WORKDIR /app

# Install requests library for additional testing
RUN pip install --no-cache-dir requests 2>/dev/null || true

# Copy the check script
COPY check.py /app/

# Set default command
ENTRYPOINT ["python", "/app/check.py"]
CMD ["https://www.google.com"]
EOF

    log_debug "Created Dockerfile: $dockerfile"
}

# Build a Docker image for .NET version
build_dotnet_image() {
    local version="$1"
    local image_name="${DOCKER_IMAGE_PREFIX}-dotnet:${version}"
    local dockerfile="${PROJECT_ROOT}/docker/dotnet/Dockerfile.${version}"

    log_info "Building Docker image: $image_name"

    # Create Dockerfile if it doesn't exist
    if [[ ! -f "$dockerfile" ]]; then
        create_dotnet_dockerfile "$version"
    fi

    docker build -t "$image_name" -f "$dockerfile" "${PROJECT_ROOT}/dotnet" >/dev/null 2>&1
}

# Create a .NET Dockerfile for a specific version
create_dotnet_dockerfile() {
    local version="$1"
    local dockerfile="${PROJECT_ROOT}/docker/dotnet/Dockerfile.${version}"

    mkdir -p "${PROJECT_ROOT}/docker/dotnet"

    cat > "$dockerfile" <<EOF
FROM mcr.microsoft.com/dotnet/sdk:${version}.0 AS build

WORKDIR /src

# Copy project files
COPY CheckSsl.csproj .
COPY CheckSsl.cs .

# Update the target framework
RUN sed -i 's/<TargetFramework>.*<\/TargetFramework>/<TargetFramework>net${version}.0<\/TargetFramework>/' CheckSsl.csproj

# Build
RUN dotnet publish -c Release -o /app --nologo

# Runtime image
FROM mcr.microsoft.com/dotnet/runtime:${version}.0

WORKDIR /app
COPY --from=build /app .

ENTRYPOINT ["dotnet", "CheckSsl.dll"]
CMD ["https://www.google.com"]
EOF

    log_debug "Created Dockerfile: $dockerfile"
}

# Run a check in a Docker container
# Usage: run_in_docker "python" "3.12" "https://example.com"
run_in_docker() {
    local tool="$1"
    local version="$2"
    local url="${3:-https://www.google.com}"
    local timeout="${4:-$TIMEOUT_SECONDS}"

    if ! check_docker_running; then
        echo '{"error": "Docker is not running"}'
        return 1
    fi

    local image_name="${DOCKER_IMAGE_PREFIX}-${tool}:${version}"

    # Build image if it doesn't exist
    if ! image_exists "$image_name"; then
        case "$tool" in
            python)
                build_python_image "$version"
                ;;
            dotnet)
                build_dotnet_image "$version"
                ;;
            *)
                echo '{"error": "Unknown tool for Docker"}'
                return 1
                ;;
        esac
    fi

    # Run the container
    docker run --rm --network host \
        -e TIMEOUT="$timeout" \
        "$image_name" "$url" "$timeout"
}

# Prompt user about Docker usage for missing version
# Usage: prompt_docker_usage "Python" "3.12"
prompt_docker_usage() {
    local tool="$1"
    local version="$2"

    if ! check_docker_running; then
        echo "Docker is not available."
        echo "Would you like to skip testing $tool $version? [y/n]: "
        read -r response
        case "${response,,}" in
            y|yes) return 1 ;;
            *) return 2 ;;  # User wants to abort
        esac
    fi

    echo "$tool $version is not installed locally."
    echo "Options:"
    echo "  1) Use Docker to test (recommended)"
    echo "  2) Skip this version"
    echo "  3) Cancel"
    echo -n "Choice [1-3]: "

    read -r choice
    case "$choice" in
        1) return 0 ;;  # Use Docker
        2) return 1 ;;  # Skip
        *) return 2 ;;  # Cancel
    esac
}

# Build all Docker images
build_all_images() {
    log_info "Building all Docker images..."

    # Python versions
    for ver in "${PYTHON_VERSIONS[@]}"; do
        log_info "Building Python $ver image..."
        build_python_image "$ver" || log_warning "Failed to build Python $ver image"
    done

    # .NET versions
    for ver in "${DOTNET_VERSIONS[@]}"; do
        log_info "Building .NET $ver image..."
        build_dotnet_image "$ver" || log_warning "Failed to build .NET $ver image"
    done

    log_success "All images built"
}

# List built images
list_images() {
    echo "SSL Diagnostics Docker Images:"
    echo ""
    docker images --filter "reference=${DOCKER_IMAGE_PREFIX}-*" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}"
}

# Clean up Docker images
cleanup_images() {
    log_info "Removing SSL diagnostics Docker images..."

    docker images --filter "reference=${DOCKER_IMAGE_PREFIX}-*" -q | \
        xargs -r docker rmi -f 2>/dev/null || true

    log_success "Cleanup complete"
}

# Clean up dangling images and build cache
deep_cleanup() {
    cleanup_images

    log_info "Removing dangling images..."
    docker image prune -f >/dev/null 2>&1 || true

    log_info "Removing build cache..."
    docker builder prune -f >/dev/null 2>&1 || true

    log_success "Deep cleanup complete"
}

# Show Docker status
show_docker_status() {
    echo "Docker Status:"
    echo ""

    if ! check_docker_installed; then
        echo "  Docker: NOT INSTALLED"
        echo ""
        echo "To install Docker:"
        echo "  macOS:  brew install --cask docker"
        echo "  Linux:  https://docs.docker.com/engine/install/"
        return
    fi

    echo "  Docker: $(get_docker_version)"

    if check_docker_running; then
        echo "  Status: RUNNING"
    else
        echo "  Status: NOT RUNNING"
        echo ""
        echo "Please start Docker Desktop or the Docker daemon."
        return
    fi

    echo ""
    echo "SSL Diagnostics Images:"

    local image_count
    image_count=$(docker images --filter "reference=${DOCKER_IMAGE_PREFIX}-*" -q | wc -l)

    if [[ "$image_count" -eq 0 ]]; then
        echo "  No images built yet."
        echo "  Run: $0 --build-all"
    else
        docker images --filter "reference=${DOCKER_IMAGE_PREFIX}-*" \
            --format "  {{.Repository}}:{{.Tag}} ({{.Size}})"
    fi
}

# Debug logging
log_debug() {
    if [[ "${VERBOSE:-1}" -ge 3 ]]; then
        echo "[DEBUG] $1" >&2
    fi
}

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --status|-s)
            show_docker_status
            ;;
        --build-all|-b)
            build_all_images
            ;;
        --build)
            tool="${2:-}"
            version="${3:-}"
            if [[ -z "$tool" || -z "$version" ]]; then
                echo "Usage: $0 --build TOOL VERSION"
                echo "Example: $0 --build python 3.12"
                exit 1
            fi
            case "$tool" in
                python)
                    build_python_image "$version"
                    ;;
                dotnet)
                    build_dotnet_image "$version"
                    ;;
                *)
                    echo "Unknown tool: $tool"
                    exit 1
                    ;;
            esac
            ;;
        --run)
            tool="${2:-}"
            version="${3:-}"
            url="${4:-https://www.google.com}"
            if [[ -z "$tool" || -z "$version" ]]; then
                echo "Usage: $0 --run TOOL VERSION [URL]"
                exit 1
            fi
            run_in_docker "$tool" "$version" "$url"
            ;;
        --list|-l)
            list_images
            ;;
        --cleanup|-c)
            cleanup_images
            ;;
        --deep-cleanup)
            deep_cleanup
            ;;
        --help|-h)
            cat <<EOF
Docker Helper for SSL Diagnostics

Usage: $0 [OPTIONS]

Options:
  --status, -s         Show Docker status and built images
  --build-all, -b      Build all Docker images
  --build TOOL VER     Build image for specific tool and version
  --run TOOL VER [URL] Run check in Docker container
  --list, -l           List built images
  --cleanup, -c        Remove SSL diagnostics images
  --deep-cleanup       Remove images and prune build cache
  --help, -h           Show this help message

Examples:
  $0 --status
  $0 --build python 3.12
  $0 --run python 3.12 https://example.com
  $0 --build-all
EOF
            ;;
        *)
            show_docker_status
            ;;
    esac
fi
