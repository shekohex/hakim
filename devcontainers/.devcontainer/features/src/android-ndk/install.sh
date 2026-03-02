#!/bin/bash
set -euo pipefail

SDK_ROOT=${SDKROOT:-${SDK_ROOT:-"/usr/local/share/android-sdk"}}
NDK_VERSION=${VERSION:-"29.0.14206865"}
CMAKE_VERSION=${CMAKEVERSION:-${CMAKE_VERSION:-"4.1.2"}}
ADDITIONAL_CMAKE_VERSIONS=${ADDITIONALCMAKEVERSIONS:-${ADDITIONAL_CMAKE_VERSIONS:-"3.22.1"}}
EXTRA_PACKAGES=${EXTRAPACKAGES:-""}
BOOTSTRAP_CMDLINE_TOOLS_VERSION=${BOOTSTRAPCMDLINETOOLSVERSION:-${BOOTSTRAP_CMDLINE_TOOLS_VERSION:-"14742923"}}
BOOTSTRAP_CMDLINE_TOOLS_SHA1=${BOOTSTRAPCMDLINETOOLSSHA1:-${BOOTSTRAP_CMDLINE_TOOLS_SHA1:-"48833c34b761c10cb20bcd16582129395d121b27"}}

if ! command -v java >/dev/null 2>&1; then
    apt-get update
    java_pkg=""
    for pkg in openjdk-21-jdk-headless openjdk-21-jdk openjdk-17-jdk-headless openjdk-17-jdk default-jdk-headless default-jdk; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            java_pkg="$pkg"
            break
        fi
    done
    if [ -z "$java_pkg" ]; then
        echo "Unable to locate any suitable JDK package" >&2
        exit 1
    fi
    apt-get install -y --no-install-recommends "$java_pkg" ca-certificates
    rm -rf /var/lib/apt/lists/*
fi

if [ ! -x "${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" ]; then
    apt-get update
    apt-get install -y --no-install-recommends curl unzip ca-certificates
    rm -rf /var/lib/apt/lists/*

    install -d "${SDK_ROOT}" "${SDK_ROOT}/cmdline-tools"
    tmp_zip="/tmp/commandlinetools-linux-${BOOTSTRAP_CMDLINE_TOOLS_VERSION}_latest.zip"
    curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-${BOOTSTRAP_CMDLINE_TOOLS_VERSION}_latest.zip" -o "$tmp_zip"
    printf '%s  %s\n' "$BOOTSTRAP_CMDLINE_TOOLS_SHA1" "$tmp_zip" | sha1sum -c -

    tmp_extract="/tmp/android-cmdline-tools-ndk"
    rm -rf "$tmp_extract"
    mkdir -p "$tmp_extract"
    unzip -q "$tmp_zip" -d "$tmp_extract"

    rm -rf "${SDK_ROOT}/cmdline-tools/latest"
    mv "$tmp_extract/cmdline-tools" "${SDK_ROOT}/cmdline-tools/latest"
    rm -rf "$tmp_extract" "$tmp_zip"
fi

SDKMANAGER="${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
if [ ! -x "$SDKMANAGER" ]; then
    if command -v sdkmanager >/dev/null 2>&1; then
        SDKMANAGER="$(command -v sdkmanager)"
    else
        echo "sdkmanager is required. Install android-sdk feature first." >&2
        exit 1
    fi
fi

packages=("ndk;${NDK_VERSION}")

if [ -n "$CMAKE_VERSION" ] && [ "$CMAKE_VERSION" != "none" ]; then
    packages+=("cmake;${CMAKE_VERSION}")
fi

IFS=',' read -ra additional_cmake_specs <<< "$ADDITIONAL_CMAKE_VERSIONS"
for raw_version in "${additional_cmake_specs[@]}"; do
    version="$(echo "$raw_version" | xargs)"
    if [ -z "$version" ] || [ "$version" = "none" ]; then
        continue
    fi
    packages+=("cmake;${version}")
done

IFS=',' read -ra extra_specs <<< "$EXTRA_PACKAGES"
for raw_package in "${extra_specs[@]}"; do
    extra_package="$(echo "$raw_package" | xargs)"
    if [ -n "$extra_package" ]; then
        packages+=("$extra_package")
    fi
done

set +o pipefail
yes | "$SDKMANAGER" --sdk_root="${SDK_ROOT}" --licenses >/dev/null
set -o pipefail

"$SDKMANAGER" --sdk_root="${SDK_ROOT}" "${packages[@]}"

NDK_HOME_PATH="${SDK_ROOT}/ndk/${NDK_VERSION}"
if [ ! -d "$NDK_HOME_PATH" ]; then
    echo "NDK was not installed at expected path: ${NDK_HOME_PATH}" >&2
    exit 1
fi

if [ -n "$CMAKE_VERSION" ] && [ -x "${SDK_ROOT}/cmake/${CMAKE_VERSION}/bin/cmake" ]; then
    cat <<EOF > /usr/local/bin/cmake
#!/bin/bash
exec "${SDK_ROOT}/cmake/${CMAKE_VERSION}/bin/cmake" "\$@"
EOF
    chmod +x /usr/local/bin/cmake

    for cmake_bin in ctest cpack ninja; do
        if [ -x "${SDK_ROOT}/cmake/${CMAKE_VERSION}/bin/${cmake_bin}" ]; then
            cat <<EOF > "/usr/local/bin/${cmake_bin}"
#!/bin/bash
exec "${SDK_ROOT}/cmake/${CMAKE_VERSION}/bin/${cmake_bin}" "\$@"
EOF
            chmod +x "/usr/local/bin/${cmake_bin}"
        fi
    done
fi

cat <<EOF > /etc/profile.d/android-ndk.sh
export ANDROID_NDK_HOME="${NDK_HOME_PATH}"
export NDK_HOME="${NDK_HOME_PATH}"
if [[ ":\$PATH:" != *":\$ANDROID_NDK_HOME:"* ]]; then
    export PATH="\$ANDROID_NDK_HOME:\$PATH"
fi
if [[ ":\$PATH:" != *":\$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:"* ]]; then
    export PATH="\$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:\$PATH"
fi
EOF
chmod +x /etc/profile.d/android-ndk.sh

ANDROID_NDK_ENV_EXPORT="export ANDROID_NDK_HOME=\"${NDK_HOME_PATH}\"\nexport NDK_HOME=\"${NDK_HOME_PATH}\""
if ! grep -q "ANDROID_NDK_HOME=" /etc/bash.bashrc; then
    echo -e "$ANDROID_NDK_ENV_EXPORT" >> /etc/bash.bashrc
fi
if [ -f /etc/zsh/zshrc ] && ! grep -q "ANDROID_NDK_HOME=" /etc/zsh/zshrc; then
    echo -e "$ANDROID_NDK_ENV_EXPORT" >> /etc/zsh/zshrc
fi

if [ -x "${NDK_HOME_PATH}/ndk-build" ]; then
    cat <<EOF > /usr/local/bin/ndk-build
#!/bin/bash
exec "${NDK_HOME_PATH}/ndk-build" "\$@"
EOF
    chmod +x /usr/local/bin/ndk-build
fi

"${NDK_HOME_PATH}/ndk-build" --version
