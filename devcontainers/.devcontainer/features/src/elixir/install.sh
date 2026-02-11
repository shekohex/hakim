#!/bin/bash
set -e

ERLANG_VERSION=${ERLANG_VERSION:-${ERLANGVERSION:-"27"}}
ELIXIR_VERSION=${ELIXIR_VERSION:-${ELIXIRVERSION:-"1.17"}}
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

# Check glibc version - compile from source if too old (precompiled needs 2.38+)
GLIBC_VERSION=$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo "0")
GLIBC_MAJOR=$(echo "$GLIBC_VERSION" | cut -d. -f1)
GLIBC_MINOR=$(echo "$GLIBC_VERSION" | cut -d. -f2)
NEEDS_COMPILE=false

if [ "$GLIBC_MAJOR" -lt 2 ] || ([ "$GLIBC_MAJOR" -eq 2 ] && [ "$GLIBC_MINOR" -lt 38 ]); then
    echo "GLIBC ${GLIBC_VERSION} detected (< 2.38), will compile Erlang from source"
    NEEDS_COMPILE=true
fi

export MISE_YES=1
export MISE_DATA_DIR=/usr/local/share/mise

if [ -f /etc/profile.d/mise.sh ]; then
    source /etc/profile.d/mise.sh
fi

# Install basic dependencies
apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libncurses-dev \
    libssl-dev \
    openssl \
    && rm -rf /var/lib/apt/lists/*

if [ "$NEEDS_COMPILE" = "true" ]; then
    # Install additional build dependencies for compiling Erlang from source
    apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        autoconf \
        m4 \
        libncurses5-dev \
        libwxgtk3.2-dev \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        libpng-dev \
        libssh-dev \
        unixodbc-dev \
        xsltproc \
        fop \
        libxml2-utils \
        && rm -rf /var/lib/apt/lists/*

    # Install kerl and compile Erlang from source
    KERL_VERSION="4.2.0"
    curl -fsSL "https://raw.githubusercontent.com/kerl/kerl/${KERL_VERSION}/kerl" -o /usr/local/bin/kerl
    chmod +x /usr/local/bin/kerl

    export KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac --without-wx"
    export KERL_BUILD_DOCS="no"

    echo "Installing Erlang/OTP ${ERLANG_VERSION} (compiling from source with kerl)..."
    kerl build "${ERLANG_VERSION}" "${ERLANG_VERSION}"
    kerl install "${ERLANG_VERSION}" /usr/local/share/mise/installs/erlang/${ERLANG_VERSION}

    # Link erlang binaries
    for bin in /usr/local/share/mise/installs/erlang/${ERLANG_VERSION}/bin/*; do
        if [ -f "$bin" ] && [ -x "$bin" ]; then
            ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"
        fi
    done
else
    echo "Installing Erlang/OTP ${ERLANG_VERSION} (using precompiled binaries)..."
    mise use --global erlang@${ERLANG_VERSION}
fi

echo "Installing Elixir ${ELIXIR_VERSION}..."
mise use --global elixir@${ELIXIR_VERSION}

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
    USER_HOME=$(getent passwd "${_REMOTE_USER}" | cut -d: -f6)
    if [ -n "$USER_HOME" ]; then
        mkdir -p "$USER_HOME/.mix" "$USER_HOME/.hex" "$USER_HOME/.cache"
        chown -R "${_REMOTE_USER}":"${_REMOTE_USER}" "$USER_HOME/.mix" "$USER_HOME/.hex" "$USER_HOME/.cache"
        echo "Installing Hex package manager for ${_REMOTE_USER}..."
        su - "${_REMOTE_USER}" -c "MIX_HOME=\"${USER_HOME}/.mix\" HEX_HOME=\"${USER_HOME}/.hex\" MIX_ARCHIVES=\"${USER_HOME}/.mix/archives\" mix local.hex --force"
        echo "Installing Rebar build tool for ${_REMOTE_USER}..."
        su - "${_REMOTE_USER}" -c "MIX_HOME=\"${USER_HOME}/.mix\" HEX_HOME=\"${USER_HOME}/.hex\" MIX_ARCHIVES=\"${USER_HOME}/.mix/archives\" mix local.rebar --force"
    fi
fi

echo "Elixir feature installation complete!"
