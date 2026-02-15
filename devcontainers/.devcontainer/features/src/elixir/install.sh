#!/bin/bash
set -euo pipefail

ERLANG_VERSION=${ERLANG_VERSION:-${ERLANGVERSION:-"28.3.1"}}
ELIXIR_VERSION=${ELIXIR_VERSION:-${ELIXIRVERSION:-"1.19.5"}}
OTP_MAJOR=${ERLANG_VERSION%%.*}
ELIXIR_OTP_VERSION="${ELIXIR_VERSION}-otp-${OTP_MAJOR}"
SEED_USER_HOME=${SEEDUSERHOME:-"true"}

_REMOTE_USER=${_REMOTE_USER:-"coder"}

if [ "${_REMOTE_USER}" = "root" ]; then
    if id "coder" &>/dev/null; then
        _REMOTE_USER="coder"
    elif id "vscode" &>/dev/null; then
        _REMOTE_USER="vscode"
    fi
fi

echo "Activating feature 'elixir'"
echo "Installing Erlang ${ERLANG_VERSION} and Elixir ${ELIXIR_VERSION} via Mise..."

export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise

if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libncurses-dev \
    libssl-dev \
    openssl \
    && rm -rf /var/lib/apt/lists/*

CURRENT_OTP=""
if command -v erl >/dev/null 2>&1; then
    CURRENT_OTP=$(erl -noshell -eval 'io:format("~s", [erlang:system_info(otp_release)]), halt().' 2>/dev/null || true)
fi

CURRENT_ELIXIR=""
if command -v elixir >/dev/null 2>&1; then
    CURRENT_ELIXIR=$(elixir --version 2>/dev/null | awk '/Elixir / {print $2; exit}')
fi

if [ "$CURRENT_OTP" = "$OTP_MAJOR" ] && [ "$CURRENT_ELIXIR" = "$ELIXIR_VERSION" ]; then
    echo "Requested Erlang/Elixir already active, skipping Mise install"
else
    echo "Installing Erlang ${ERLANG_VERSION}..."
    mise use --global "erlang@${ERLANG_VERSION}"

    echo "Installing Elixir ${ELIXIR_OTP_VERSION}..."
    mise use --global "elixir@${ELIXIR_OTP_VERSION}"
fi

rm -rf /root/.cache/mise

echo "Symlinking binaries to /usr/local/bin..."
for bin_path in $(mise bin-paths); do
    for bin_file in "$bin_path"/*; do
        if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then
            ln -sf "$bin_file" "/usr/local/bin/$(basename "$bin_file")"
        fi
    done
done

echo "Verifying installations..."
source /etc/profile.d/mise.sh
erl -version || true
elixir --version

MIX_ENV_EXPORT='export MIX_HOME="$HOME/.mix"\nexport HEX_HOME="$HOME/.hex"\nexport MIX_ARCHIVES="$MIX_HOME/archives"'

if [[ "$(cat /etc/bash.bashrc)" != *"$MIX_ENV_EXPORT"* ]]; then
    echo -e "$MIX_ENV_EXPORT" >> /etc/bash.bashrc
fi

if [ -f "/etc/zsh/zshrc" ] && [[ "$(cat /etc/zsh/zshrc)" != *"$MIX_ENV_EXPORT"* ]]; then
    echo -e "$MIX_ENV_EXPORT" >> /etc/zsh/zshrc
fi

cat << 'EOF' > /etc/profile.d/elixir-mix.sh
export MIX_HOME="$HOME/.mix"
export HEX_HOME="$HOME/.hex"
export MIX_ARCHIVES="$MIX_HOME/archives"
EOF
chmod +x /etc/profile.d/elixir-mix.sh

if [ "$SEED_USER_HOME" = "true" ]; then
    MIX_TIMEOUT_CMD=""
    if command -v timeout >/dev/null 2>&1; then
        MIX_TIMEOUT_CMD="timeout 120"
    fi

    USER_HOME=$(getent passwd "${_REMOTE_USER}" | cut -d: -f6)
    if [ -n "$USER_HOME" ]; then
        SEED_MARKER="/usr/local/share/mise/.seeded-elixir-${_REMOTE_USER}"
        if [ -f "$SEED_MARKER" ]; then
            echo "Elixir user-home seed already completed for ${_REMOTE_USER}, skipping"
            echo "Elixir feature installation complete!"
            exit 0
        fi

        mkdir -p "$USER_HOME/.mix" "$USER_HOME/.hex" "$USER_HOME/.cache"
        chown -R "${_REMOTE_USER}":"${_REMOTE_USER}" "$USER_HOME/.mix" "$USER_HOME/.hex" "$USER_HOME/.cache"

        if ls "${USER_HOME}/.mix/archives"/hex-*.ez >/dev/null 2>&1; then
            echo "Hex already seeded for ${_REMOTE_USER}, skipping"
        else
            echo "Installing Hex package manager for ${_REMOTE_USER}..."
            hex_ok=false
            for attempt in 1 2; do
                if su -s /bin/bash "${_REMOTE_USER}" -c "MIX_HOME=\"${USER_HOME}/.mix\" HEX_HOME=\"${USER_HOME}/.hex\" MIX_ARCHIVES=\"${USER_HOME}/.mix/archives\" ${MIX_TIMEOUT_CMD} mix local.hex --force"; then
                    hex_ok=true
                    break
                fi
                echo "Hex install attempt ${attempt} failed"
                sleep 3
            done
            if [ "$hex_ok" != "true" ]; then
                echo "Failed to seed Hex for ${_REMOTE_USER}" >&2
                exit 1
            fi
        fi

        if ls "${USER_HOME}/.mix/elixir"/*/rebar3 >/dev/null 2>&1; then
            echo "Rebar already seeded for ${_REMOTE_USER}, skipping"
        else
            echo "Installing Rebar build tool for ${_REMOTE_USER}..."
            rebar_ok=false
            for attempt in 1 2; do
                if su -s /bin/bash "${_REMOTE_USER}" -c "MIX_HOME=\"${USER_HOME}/.mix\" HEX_HOME=\"${USER_HOME}/.hex\" MIX_ARCHIVES=\"${USER_HOME}/.mix/archives\" ${MIX_TIMEOUT_CMD} mix local.rebar --force"; then
                    rebar_ok=true
                    break
                fi
                echo "Rebar install attempt ${attempt} failed"
                sleep 3
            done
            if [ "$rebar_ok" != "true" ]; then
                echo "Failed to seed Rebar for ${_REMOTE_USER}" >&2
                exit 1
            fi
        fi

        touch "$SEED_MARKER"
    fi
fi

echo "Elixir feature installation complete!"
