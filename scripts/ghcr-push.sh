#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GHCR_OWNER="${GHCR_OWNER:?GHCR_OWNER must be set}"
GHCR_REGISTRY="${GHCR_REGISTRY:-ghcr.io}"

mapfile -t plugin_dirs < <("$SCRIPT_DIR/find-latest-plugins.sh" "$REPO_ROOT/plugins")

echo "Pushing ${#plugin_dirs[@]} plugin images"

for dir in "${plugin_dirs[@]}"; do
    rel="${dir#"$REPO_ROOT"/plugins/}"
    owner="$(echo "$rel" | cut -d/ -f1)"
    plugin_name="$(echo "$rel" | cut -d/ -f2)"
    version="$(echo "$rel" | cut -d/ -f3)"

    image="${GHCR_REGISTRY}/${GHCR_OWNER}/plugins-${owner}-${plugin_name}:${version}"

    echo "Pushing: ${image}"
    docker push "$image"
    echo "Pushed: ${image}"
done

echo "All pushes complete."

