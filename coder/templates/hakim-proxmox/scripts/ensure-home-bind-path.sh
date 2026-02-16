#!/usr/bin/env bash
set -euo pipefail

for required in install mktemp rm chmod ssh setsid; do
  command -v "$required" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$required" >&2
    exit 1
  }
done

PVE_NODE_NAME="${PVE_NODE_NAME}"
PVE_BIND_PATH="${PVE_BIND_PATH}"
PVE_ROOT_PASSWORD="${PVE_ROOT_PASSWORD}"

if [[ -z "${PVE_ROOT_PASSWORD}" ]]; then
  printf 'PVE_ROOT_PASSWORD is required\n' >&2
  exit 1
fi

askpass_file="$(mktemp)"
cleanup() {
  rm -f "${askpass_file}"
}
trap cleanup EXIT

cat >"${askpass_file}" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${PVE_ROOT_PASSWORD}"
EOF

chmod 0700 "${askpass_file}"

DISPLAY=:0 \
SSH_ASKPASS="${askpass_file}" \
SSH_ASKPASS_REQUIRE=force \
PVE_ROOT_PASSWORD="${PVE_ROOT_PASSWORD}" \
setsid -w \
ssh \
  -o StrictHostKeyChecking=accept-new \
  -o PreferredAuthentications=password \
  -o PubkeyAuthentication=no \
  -o NumberOfPasswordPrompts=1 \
  "root@${PVE_NODE_NAME}" \
  "install -d -m 0755 -o 101000 -g 101000 \"${PVE_BIND_PATH}\""
