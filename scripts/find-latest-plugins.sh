#!/usr/bin/env bash
#
# Find all plugins and their latest versions under plugins/.
# For each owner/plugin, output only the highest semver directory.
#
set -euo pipefail

PLUGINS_DIR="${1:-plugins}"

declare -A latest_version latest_path

while IFS= read -r yaml_file; do
    dir="$(dirname "$yaml_file")"
    version="$(basename "$dir")"
    plugin_dir="$(dirname "$dir")"
    plugin_key="$(basename "$(dirname "$plugin_dir")")/$(basename "$plugin_dir")"

    # Compare semver: strip leading 'v', use sort -V
    current="${latest_version[$plugin_key]:-}"
    if [[ -z "$current" ]] || [[ "$(printf '%s\n%s' "${current#v}" "${version#v}" | sort -V | tail -1)" == "${version#v}" ]]; then
        latest_version[$plugin_key]="$version"
        latest_path[$plugin_key]="$dir"
    fi
done < <(find "$PLUGINS_DIR" -name "buf.plugin.yaml" -type f | sort)

for key in $(printf '%s\n' "${!latest_path[@]}" | sort); do
    echo "${latest_path[$key]}"
done

