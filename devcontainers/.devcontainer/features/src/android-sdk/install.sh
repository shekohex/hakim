#!/bin/bash
set -euo pipefail

SDK_ROOT=${SDKROOT:-${SDK_ROOT:-"/usr/local/share/android-sdk"}}
CMDLINE_TOOLS_VERSION=${CMDLINETOOLSVERSION:-${CMDLINE_TOOLS_VERSION:-"14742923"}}
CMDLINE_TOOLS_SHA1=${CMDLINETOOLSSHA1:-${CMDLINE_TOOLS_SHA1:-"48833c34b761c10cb20bcd16582129395d121b27"}}
BUILD_TOOLS_VERSION=${BUILDTOOLSVERSION:-${BUILD_TOOLS_VERSION:-"36.1.0"}}
PLATFORMS=${PLATFORMS:-"android-36,android-35"}
INCLUDE_SOURCES=${INCLUDESOURCES:-"true"}
INSTALL_EMULATOR=${INSTALLEMULATOR:-"false"}
SYSTEM_IMAGE=${SYSTEMIMAGE:-"system-images;android-36;google_apis;x86_64"}
EXTRA_PACKAGES=${EXTRAPACKAGES:-""}
ACCEPT_LICENSES=${ACCEPTLICENSES:-"true"}

is_true() {
    case "$1" in
    true|TRUE|1|yes|YES|on|ON)
        return 0
        ;;
    *)
        return 1
        ;;
    esac
}

_REMOTE_USER=${_REMOTE_USER:-"coder"}
if [ "${_REMOTE_USER}" = "root" ]; then
    if id "coder" &>/dev/null; then
        _REMOTE_USER="coder"
    elif id "vscode" &>/dev/null; then
        _REMOTE_USER="vscode"
    fi
fi

apt-get update

packages_to_install=(curl unzip ca-certificates)
if is_true "$INSTALL_EMULATOR"; then
    emulator_runtime_candidates=(
        libnss3
        libx11-6
        libx11-xcb1
        libxcb1
        libxcomposite1
        libxcursor1
        libxi6
        libxrender1
        libxtst6
        libxrandr2
        libxdamage1
        libxfixes3
        libxkbcommon0
        libxshmfence1
        libdrm2
        libgbm1
        libgl1
        libpulse0
        libdbus-1-3
        libgtk-3-0
    )

    for pkg in "${emulator_runtime_candidates[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            packages_to_install+=("$pkg")
        fi
    done

    if apt-cache show libasound2 >/dev/null 2>&1; then
        packages_to_install+=("libasound2")
    elif apt-cache show libasound2t64 >/dev/null 2>&1; then
        packages_to_install+=("libasound2t64")
    fi
fi

apt-get install -y --no-install-recommends "${packages_to_install[@]}"
rm -rf /var/lib/apt/lists/*

install -d "${SDK_ROOT}" "${SDK_ROOT}/cmdline-tools"

tmp_zip="/tmp/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip"
curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" -o "$tmp_zip"
printf '%s  %s\n' "$CMDLINE_TOOLS_SHA1" "$tmp_zip" | sha1sum -c -

tmp_extract="/tmp/android-cmdline-tools"
rm -rf "$tmp_extract"
mkdir -p "$tmp_extract"
unzip -q "$tmp_zip" -d "$tmp_extract"

rm -rf "${SDK_ROOT}/cmdline-tools/latest"
mv "$tmp_extract/cmdline-tools" "${SDK_ROOT}/cmdline-tools/latest"
rm -rf "$tmp_extract" "$tmp_zip"

SDKMANAGER="${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
    echo "sdkmanager not found after command-line tools installation" >&2
    exit 1
fi

packages=("platform-tools")

if [ -n "$BUILD_TOOLS_VERSION" ] && [ "$BUILD_TOOLS_VERSION" != "none" ]; then
    packages+=("build-tools;${BUILD_TOOLS_VERSION}")
fi

IFS=',' read -ra platform_specs <<< "$PLATFORMS"
for raw_platform in "${platform_specs[@]}"; do
    platform="$(echo "$raw_platform" | xargs)"
    if [ -z "$platform" ]; then
        continue
    fi
    api_level="${platform}"
    if [[ "$platform" == platforms\;* ]]; then
        packages+=("${platform}")
        api_level="${platform#platforms;}"
    else
        packages+=("platforms;${platform}")
    fi
    if is_true "$INCLUDE_SOURCES"; then
        packages+=("sources;${api_level}")
    fi
done

if is_true "$INSTALL_EMULATOR"; then
    packages+=("emulator")
    if [ -n "$SYSTEM_IMAGE" ]; then
        packages+=("$SYSTEM_IMAGE")
    fi
fi

IFS=',' read -ra extra_specs <<< "$EXTRA_PACKAGES"
for raw_package in "${extra_specs[@]}"; do
    extra_package="$(echo "$raw_package" | xargs)"
    if [ -n "$extra_package" ]; then
        packages+=("$extra_package")
    fi
done

if is_true "$ACCEPT_LICENSES"; then
    set +o pipefail
    yes | "$SDKMANAGER" --sdk_root="${SDK_ROOT}" --licenses >/dev/null
    set -o pipefail
fi

"$SDKMANAGER" --sdk_root="${SDK_ROOT}" "${packages[@]}"

ln -sf "${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" /usr/local/bin/sdkmanager
ln -sf "${SDK_ROOT}/cmdline-tools/latest/bin/avdmanager" /usr/local/bin/avdmanager
if [ -x "${SDK_ROOT}/platform-tools/adb" ]; then
    ln -sf "${SDK_ROOT}/platform-tools/adb" /usr/local/bin/adb
fi
if [ -x "${SDK_ROOT}/emulator/emulator" ]; then
    ln -sf "${SDK_ROOT}/emulator/emulator" /usr/local/bin/android-emulator
    ln -sf "${SDK_ROOT}/emulator/emulator" /usr/local/bin/emulator
fi

if [ -f "./android-emulator-manager" ]; then
    install -m 0755 "./android-emulator-manager" /usr/local/bin/android-emulator-manager
fi

cat <<EOF > /etc/profile.d/android-sdk.sh
export ANDROID_SDK_ROOT="${SDK_ROOT}"
export ANDROID_HOME="${SDK_ROOT}"
if [[ ":\$PATH:" != *":\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:"* ]]; then
    export PATH="\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$PATH"
fi
if [[ ":\$PATH:" != *":\$ANDROID_SDK_ROOT/platform-tools:"* ]]; then
    export PATH="\$ANDROID_SDK_ROOT/platform-tools:\$PATH"
fi
if [[ ":\$PATH:" != *":\$ANDROID_SDK_ROOT/emulator:"* ]]; then
    export PATH="\$ANDROID_SDK_ROOT/emulator:\$PATH"
fi
EOF
chmod +x /etc/profile.d/android-sdk.sh

ANDROID_SDK_ENV_EXPORT="export ANDROID_SDK_ROOT=\"${SDK_ROOT}\"\nexport ANDROID_HOME=\"${SDK_ROOT}\""
if ! grep -q "ANDROID_SDK_ROOT=" /etc/bash.bashrc; then
    echo -e "$ANDROID_SDK_ENV_EXPORT" >> /etc/bash.bashrc
fi
if [ -f /etc/zsh/zshrc ] && ! grep -q "ANDROID_SDK_ROOT=" /etc/zsh/zshrc; then
    echo -e "$ANDROID_SDK_ENV_EXPORT" >> /etc/zsh/zshrc
fi

if id "${_REMOTE_USER}" >/dev/null 2>&1; then
    chown -R "${_REMOTE_USER}:${_REMOTE_USER}" "${SDK_ROOT}"
fi

sdkmanager --version
adb version
