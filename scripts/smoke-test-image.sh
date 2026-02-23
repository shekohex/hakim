#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET=""
IMAGE=""
VARIANT=""
CONFIG_FILE=""

if [[ "${CI:-}" != "true" && "${GITHUB_ACTIONS:-}" != "true" ]]; then
  echo "[smoke] Skipping smoke tests: CI environment not detected."
  exit 0
fi

function usage() {
  cat <<'EOF'
Usage: scripts/smoke-test-image.sh --target <base|tooling|variant> --image <image-ref> [--variant <name>] [--config <path>]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --image)
      IMAGE="$2"
      shift 2
      ;;
    --variant)
      VARIANT="$2"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET" || -z "$IMAGE" ]]; then
  usage
  exit 1
fi

if [[ "$TARGET" == "variant" && -z "$VARIANT" ]]; then
  echo "--variant is required when --target variant is used" >&2
  exit 1
fi

if [[ "$TARGET" == "variant" && -z "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$ROOT_DIR/devcontainers/.devcontainer/images/$VARIANT/.devcontainer/devcontainer.json"
fi

if [[ "$TARGET" == "variant" && ! -f "$CONFIG_FILE" ]]; then
  echo "Variant config not found: $CONFIG_FILE" >&2
  exit 1
fi

function log() {
  echo "[smoke][$TARGET${VARIANT:+:$VARIANT}] $*"
}

function docker_root() {
  local cmd="$1"
  docker run --rm --pull never --entrypoint bash "$IMAGE" -lc "set -euo pipefail; export PATH=\"\$PATH:/usr/local/share/mise/shims:/usr/local/bin:/usr/local/sbin\"; $cmd"
}

function docker_coder() {
  local cmd="$1"
  docker run --rm --pull never --entrypoint bash --user coder --workdir /home/coder "$IMAGE" -lc "set -euo pipefail; export HOME=/home/coder; export PATH=\"\$PATH:/usr/local/share/mise/shims:/usr/local/bin:/usr/local/sbin\"; $cmd"
}

function assert_contains() {
  local value="$1"
  local expected="$2"
  local label="$3"
  if [[ "$value" != *"$expected"* ]]; then
    echo "Assertion failed for $label: expected to contain '$expected' but got '$value'" >&2
    exit 1
  fi
}

function read_arg() {
  local file="$1"
  local arg="$2"
  local line
  if command -v rg >/dev/null 2>&1; then
    line="$(rg -N "^ARG ${arg}=" "$file" | head -n1 || true)"
  else
    line="$(grep -E "^ARG ${arg}=" "$file" | head -n1 || true)"
  fi
  if [[ -z "$line" ]]; then
    echo "Could not find ARG ${arg} in ${file}" >&2
    exit 1
  fi
  echo "${line#*=}"
}

function check_coder_runtime() {
  docker_root 'id coder >/dev/null'
  docker_coder 'test -w "$HOME"; mkdir -p "$HOME/.cache/hakim-smoke"; touch "$HOME/.cache/hakim-smoke/ok"'
}

function check_base() {
  local base_file="$ROOT_DIR/devcontainers/base/Dockerfile"
  local coder_expected
  local code_server_expected
  local chrome_expected
  local coder_version
  local code_server_version
  local chrome_version

  coder_expected="$(read_arg "$base_file" "CODER_VERSION")"
  code_server_expected="$(read_arg "$base_file" "CODE_SERVER_VERSION")"
  chrome_expected="$(read_arg "$base_file" "GOOGLE_CHROME_VERSION")"

  check_coder_runtime

  coder_version="$(docker_root 'coder --version')"
  assert_contains "$coder_version" "$coder_expected" "coder version"

  code_server_version="$(docker_root 'code-server --version | head -n1')"
  assert_contains "$code_server_version" "$code_server_expected" "code-server version"

  chrome_version="$(docker_root 'google-chrome-stable --version')"
  assert_contains "$chrome_version" "$chrome_expected" "chrome version"

  docker_root 'chromedriver --version'
  docker_root 'docker --version'
  docker_root 'docker compose version'
  docker_root 'mise --version'
  docker_root 'nvim --version | head -n1'
  docker_root 'rg --version | head -n1'
  docker_root 'fd --version'
}

function check_tooling() {
  local tooling_file="$ROOT_DIR/devcontainers/tooling/Dockerfile"
  local node_expected
  local bun_expected
  local uv_expected
  local python_expected
  local opencode_expected
  local node_version
  local bun_version
  local uv_version
  local python_version
  local opencode_version

  node_expected="$(read_arg "$tooling_file" "NODE_VERSION")"
  bun_expected="$(read_arg "$tooling_file" "BUN_VERSION")"
  uv_expected="$(read_arg "$tooling_file" "UV_VERSION")"
  python_expected="$(read_arg "$tooling_file" "UV_PYTHON_VERSION")"
  opencode_expected="$(read_arg "$tooling_file" "OPENCODE_VERSION")"

  check_coder_runtime

  node_version="$(docker_coder 'node --version')"
  assert_contains "$node_version" "v${node_expected}" "node version"

  bun_version="$(docker_coder 'bun --version')"
  assert_contains "$bun_version" "$bun_expected" "bun version"

  uv_version="$(docker_coder 'uv --version')"
  assert_contains "$uv_version" "$uv_expected" "uv version"

  python_version="$(docker_coder 'python --version')"
  assert_contains "$python_version" "$python_expected" "python version"

  opencode_version="$(docker_coder 'opencode --version')"
  assert_contains "$opencode_version" "$opencode_expected" "opencode version"

  docker_coder 'tmpdir="$(mktemp -d)"; cd "$tmpdir"; node -e "console.log(\"ok\")" | rg "^ok$" >/dev/null'
  docker_coder 'tmpdir="$(mktemp -d)"; cd "$tmpdir"; bun -e "console.log(\"ok\")" | rg "^ok$" >/dev/null'
}

function check_variant_common() {
  check_coder_runtime
  docker_coder 'test -f "$HOME/.config/nvim/lua/config/lazy.lua"'
  docker_coder 'test "$(stat -c %U "$HOME/.config/nvim")" = "coder"'
  docker_coder 'nvim --version | head -n1'
}

function check_rust() {
  local expected_rust
  local rust_version

  expected_rust="$(jq -r 'first(.features | to_entries[] | select(.key | test("/rust$")) | .value.version) // empty' "$CONFIG_FILE")"

  check_variant_common

  rust_version="$(docker_coder 'rustc --version')"
  if [[ -n "$expected_rust" ]]; then
    assert_contains "$rust_version" "$expected_rust" "rustc version"
  fi

  docker_coder 'cargo --version'
  docker_coder 'rustup --version'
  docker_coder 'test -w "$HOME/.cargo"; test -w "$HOME/.rustup"'
  docker_coder 'tmpdir="$(mktemp -d)"; cd "$tmpdir"; cargo new --vcs none smoke_rust >/dev/null; cd smoke_rust; cargo check --quiet'
}

function check_php() {
  local expected_php
  local expected_laravel
  local php_version
  local laravel_version

  expected_php="$(jq -r '.features["ghcr.io/devcontainers/features/php:1"].version // empty' "$CONFIG_FILE")"
  expected_laravel="$(jq -r 'first(.features | to_entries[] | select(.key | test("/laravel$")) | .value.version) // empty' "$CONFIG_FILE")"

  check_variant_common

  php_version="$(docker_coder 'php -v | head -n1')"
  if [[ -n "$expected_php" ]]; then
    assert_contains "$php_version" "PHP ${expected_php}" "php version"
  fi

  docker_coder 'composer --version'

  laravel_version="$(docker_coder 'laravel --version')"
  if [[ -n "$expected_laravel" ]]; then
    assert_contains "$laravel_version" "$expected_laravel" "laravel installer version"
  fi

  docker_coder 'tmpdir="$(mktemp -d)"; cd "$tmpdir"; composer init --name hakim/smoke --no-interaction >/dev/null; php -r "echo \"ok\";" | rg "^ok$" >/dev/null'
}

function check_elixir() {
  local expected_erlang
  local expected_elixir
  local expected_phoenix
  local expected_postgresql
  local expected_otp_major
  local actual_otp
  local actual_elixir
  local actual_phoenix
  local actual_psql

  expected_erlang="$(jq -r 'first(.features | to_entries[] | select(.key | test("/elixir$")) | .value.erlangVersion) // empty' "$CONFIG_FILE")"
  expected_elixir="$(jq -r 'first(.features | to_entries[] | select(.key | test("/elixir$")) | .value.elixirVersion) // empty' "$CONFIG_FILE")"
  expected_phoenix="$(jq -r 'first(.features | to_entries[] | select(.key | test("/phoenix$")) | .value.version) // empty' "$CONFIG_FILE")"
  expected_postgresql="$(jq -r 'first(.features | to_entries[] | select(.key | test("/postgresql-tools$")) | .value.version) // empty' "$CONFIG_FILE")"

  check_variant_common

  actual_otp="$(docker_coder 'erl -noshell -eval "io:format(\"~s\", [erlang:system_info(otp_release)]), halt()."')"
  if [[ -n "$expected_erlang" ]]; then
    expected_otp_major="${expected_erlang%%.*}"
    assert_contains "$actual_otp" "$expected_otp_major" "erlang otp version"
  fi

  actual_elixir="$(docker_coder 'elixir --version | awk "/Elixir / { print \$2; exit }"')"
  if [[ -n "$expected_elixir" ]]; then
    assert_contains "$actual_elixir" "$expected_elixir" "elixir version"
  fi

  actual_phoenix="$(docker_coder 'mix phx.new --version')"
  if [[ -n "$expected_phoenix" && "$expected_phoenix" != "latest" ]]; then
    assert_contains "$actual_phoenix" "$expected_phoenix" "phoenix installer version"
  fi

  actual_psql="$(docker_coder 'psql --version')"
  if [[ -n "$expected_postgresql" && "$expected_postgresql" != "latest" ]]; then
    assert_contains "$actual_psql" "$expected_postgresql" "postgresql client version"
  fi

  docker_coder 'test -w "$HOME/.mix"; test -w "$HOME/.hex"'
  docker_coder 'tmpdir="$(mktemp -d)"; cd "$tmpdir"; mix new smoke_elixir >/dev/null; cd smoke_elixir; mix test >/dev/null'
}

function check_dotnet() {
  local expected_dotnet
  local expected_additional
  local dotnet_sdks
  local additional_major

  expected_dotnet="$(jq -r 'first(.features | to_entries[] | select(.key | test("/dotnet$")) | .value.version) // empty' "$CONFIG_FILE")"
  expected_additional="$(jq -r 'first(.features | to_entries[] | select(.key | test("/dotnet$")) | .value.additionalVersions) // empty' "$CONFIG_FILE")"

  check_variant_common

  docker_coder 'dotnet --info >/dev/null'

  dotnet_sdks="$(docker_coder 'dotnet --list-sdks')"
  if [[ -n "$expected_dotnet" ]]; then
    assert_contains "$dotnet_sdks" "${expected_dotnet}." "dotnet sdk version"
  fi

  if [[ -n "$expected_additional" ]]; then
    additional_major="${expected_additional%%-*}"
    assert_contains "$dotnet_sdks" "${additional_major}." "additional dotnet sdk version"
  fi

  docker_coder 'tmpdir="$(mktemp -d)"; cd "$tmpdir"; dotnet new console -n smoke_dotnet >/dev/null; cd smoke_dotnet; dotnet build --nologo >/dev/null'
}

function check_js() {
  local tooling_file="$ROOT_DIR/devcontainers/tooling/Dockerfile"
  local node_expected
  local bun_expected
  local node_version
  local bun_version

  node_expected="$(read_arg "$tooling_file" "NODE_VERSION")"
  bun_expected="$(read_arg "$tooling_file" "BUN_VERSION")"

  check_variant_common

  node_version="$(docker_coder 'node --version')"
  assert_contains "$node_version" "v${node_expected}" "node version"

  bun_version="$(docker_coder 'bun --version')"
  assert_contains "$bun_version" "$bun_expected" "bun version"

  docker_coder 'npm --version'
  docker_coder 'opencode --version'
  docker_coder 'uv --version'
  docker_coder 'python --version'
  docker_coder 'tmpdir="$(mktemp -d)"; cd "$tmpdir"; node -e "console.log(\"ok\")" | rg "^ok$" >/dev/null'
}

log "Starting smoke checks for $IMAGE"

case "$TARGET" in
  base)
    check_base
    ;;
  tooling)
    check_tooling
    ;;
  variant)
    case "$VARIANT" in
      rust)
        check_rust
        ;;
      php)
        check_php
        ;;
      elixir)
        check_elixir
        ;;
      dotnet)
        check_dotnet
        ;;
      js)
        check_js
        ;;
      *)
        echo "Unsupported variant: $VARIANT" >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Unsupported target: $TARGET" >&2
    exit 1
    ;;
esac

log "Smoke checks passed for $IMAGE"
