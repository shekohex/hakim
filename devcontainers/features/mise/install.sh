#!/bin/bash
set -e

# TOOLS is passed as a comma-separated string because type: array options are joined by commas
if [ -z "${TOOLS}" ]; then
    echo "No tools specified to install."
    exit 0
fi

echo "Installing mise tools: ${TOOLS}"

# Ensure global config dir exists (it should be created by the base image or install-mise.sh)
mkdir -p /etc/mise

# We will append to /etc/mise/config.toml
# Configuring MISE_GLOBAL_CONFIG_FILE is safer to ensure commands use the right config
export MISE_GLOBAL_CONFIG_FILE=/etc/mise/config.toml
export MISE_YES=1 

# Split comma-separated string into array
IFS=',' read -ra TOOLS_ARRAY <<< "${TOOLS}"

for tool in "${TOOLS_ARRAY[@]}"; do
    # Trim whitespace just in case
    tool=$(echo "$tool" | xargs)
    if [ -n "$tool" ]; then
        echo "Adding $tool to global config..."
        mise use --global "$tool"
    fi
done

echo "Running mise install..."
mise install
