#!/usr/bin/env sh

if ! command -v curl > /dev/null; then
  echo "curl is not installed"
  exit 1
fi

if ! command -v jq > /dev/null; then
  echo "jq is not installed"
  exit 1
fi

mkdir -p ~/.ssh

echo "Downloading SSH key"

ssh_key=$(curl --request GET \
  --url "${CODER_AGENT_URL}/api/v2/workspaceagents/me/gitsshkey" \
  --header "Coder-Session-Token: ${CODER_AGENT_TOKEN}" \
  --silent --show-error)

jq --raw-output ".public_key" > ~/.ssh/id_ed25519.pub << EOF
$ssh_key
EOF

echo "Got public key: $(cat ~/.ssh/id_ed25519.pub)"

jq --raw-output ".private_key" > ~/.ssh/id_ed25519 << EOF
$ssh_key
EOF

chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519
chmod 644 ~/.ssh/id_ed25519.pub
