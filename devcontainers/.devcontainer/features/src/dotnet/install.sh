#!/bin/bash
set -euo pipefail

VERSION=${VERSION:-"9.0"}
ADDITIONAL_VERSIONS=${ADDITIONALVERSIONS:-${ADDITIONAL_VERSIONS:-"10.0-preview"}}

normalize_spec() {
    local spec="$1"
    if [[ "$spec" =~ ^([0-9]+\.[0-9]+)-preview$ ]]; then
        echo "${BASH_REMATCH[1]}"
        return
    fi
    echo "$spec"
}

export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise

if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

tools=("dotnet@$(normalize_spec "$VERSION")")

IFS=',' read -ra additional_specs <<< "$ADDITIONAL_VERSIONS"
for raw in "${additional_specs[@]}"; do
    spec="$(echo "$raw" | xargs)"
    if [ -z "$spec" ] || [ "$spec" = "none" ]; then
        continue
    fi
    spec="$(normalize_spec "$spec")"
    tools+=("dotnet@${spec}")
done

mise use --global "${tools[@]}"

rm -rf /root/.cache/mise

for tool in "${tools[@]}"; do
    mise where "$tool" >/dev/null
done
