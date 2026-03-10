#!/usr/bin/env bash
#
# Build Docker images for latest plugin versions and tag them for GHCR.
#
# Usage: GHCR_OWNER=myuser ./scripts/ghcr-build.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GHCR_OWNER="${GHCR_OWNER:?GHCR_OWNER must be set (e.g. your GitHub username)}"
GHCR_REGISTRY="${GHCR_REGISTRY:-ghcr.io}"
DOCKER_BUILDER="${DOCKER_BUILDER:-bufbuild-plugins}"

# Ensure buildx builder exists
docker buildx inspect "$DOCKER_BUILDER" &>/dev/null || \
    docker buildx create --use --bootstrap --name="$DOCKER_BUILDER" >/dev/null

cleanup() {
    docker buildx rm "$DOCKER_BUILDER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Find all latest plugin directories
mapfile -t plugin_dirs < <("$SCRIPT_DIR/find-latest-plugins.sh" "$REPO_ROOT/plugins")

echo "Found ${#plugin_dirs[@]} plugins to build"

for dir in "${plugin_dirs[@]}"; do
    # Extract owner/plugin/version from path: plugins/<owner>/<plugin>/<version>
    rel="${dir#"$REPO_ROOT"/plugins/}"
    owner="$(echo "$rel" | cut -d/ -f1)"
    plugin_name="$(echo "$rel" | cut -d/ -f2)"
    version="$(echo "$rel" | cut -d/ -f3)"

    image="${GHCR_REGISTRY}/${GHCR_OWNER}/plugins-${owner}-${plugin_name}:${version}"

    echo "Building: ${owner}/${plugin_name}:${version} -> ${image}"
    docker buildx build \
        --load \
        --builder "$DOCKER_BUILDER" \
        --label "build.buf.plugins.config.owner=${owner}" \
        --label "build.buf.plugins.config.name=${plugin_name}" \
        --label "build.buf.plugins.config.version=${version}" \
        --label "org.opencontainers.image.source=https://github.com/${GHCR_OWNER}/plugins" \
        --label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --progress plain \
        -t "$image" \
        "$dir"

    echo "Built: ${image}"
done

echo "All builds complete."

