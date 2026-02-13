#!/bin/bash

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

# Install basic dependencies (needed for both methods)
apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libncurses-dev \
    libssl-dev \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Try precompiled Erlang first (faster, works on newer glibc)
echo "Attempting to install Erlang/OTP ${ERLANG_VERSION} using precompiled binaries..."
if mise use --global erlang@${ERLANG_VERSION} 2>/dev/null; then
    echo "Successfully installed precompiled Erlang"
else
    echo "Precompiled Erlang failed (likely glibc version mismatch), compiling from source..."
    
    # Install build dependencies for compiling Erlang from source
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

    # Install kerl
    KERL_VERSION="4.2.0"
    curl -fsSL "https://raw.githubusercontent.com/kerl/kerl/${KERL_VERSION}/kerl" -o /usr/local/bin/kerl
    chmod +x /usr/local/bin/kerl

    export KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac --without-wx"
    export KERL_BUILD_DOCS="no"

    echo "Compiling Erlang/OTP ${ERLANG_VERSION} from source with kerl..."
    kerl build "${ERLANG_VERSION}" "${ERLANG_VERSION}" || {
        echo "ERROR: kerl build failed for Erlang ${ERLANG_VERSION}"
        echo "Trying with latest stable version..."
        kerl build "27.2" "27.2"
        kerl install "27.2" /usr/local/share/mise/installs/erlang/${ERLANG_VERSION}
    }
    kerl install "${ERLANG_VERSION}" /usr/local/share/mise/installs/erlang/${ERLANG_VERSION}

    # Link erlang binaries to /usr/local/bin
    for bin in /usr/local/share/mise/installs/erlang/${ERLANG_VERSION}/bin/*; do
        if [ -f "$bin" ] && [ -x "$bin" ]; then
            ln -sf "$bin" "/usr/local/bin/$(basename "$bin")"
        fi
    done
fi

echo "Installing Elixir ${ELIXIR_OTP_VERSION}..."
mise use --global "elixir@${ELIXIR_OTP_VERSION}"

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
