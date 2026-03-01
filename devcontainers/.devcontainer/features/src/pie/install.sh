#!/bin/bash
set -euo pipefail

VERSION=${VERSION:-"latest"}
VERIFY_ATTESTATION=${VERIFYATTESTATION:-"false"}
INSTALL_PREREQS=${INSTALLPREREQS:-"true"}
EXTENSIONS=${EXTENSIONS:-""}

declare -a APT_PACKAGES=()
PHP_SOURCE_DIR=""
PIE_TMP_DIR=""

exists() {
    command -v "$1" >/dev/null 2>&1
}

add_apt_package() {
    local pkg="$1"
    local existing
    for existing in "${APT_PACKAGES[@]:-}"; do
        if [ "$existing" = "$pkg" ]; then
            return
        fi
    done
    APT_PACKAGES+=("$pkg")
}

extension_is_loaded() {
    php -r "exit(extension_loaded('$1') ? 0 : 1);" >/dev/null 2>&1
}

extension_name_for_package() {
    local package="$1"
    case "$package" in
        phpredis/phpredis) echo "redis" ;;
        apcu/apcu) echo "apcu" ;;
        imagick/imagick) echo "imagick" ;;
        swoole/swoole) echo "swoole" ;;
        php-memcached/php-memcached) echo "memcached" ;;
        igbinary/igbinary) echo "igbinary" ;;
        pecl/yaml) echo "yaml" ;;
        pecl/pcov) echo "pcov" ;;
        mongodb/mongodb-extension) echo "mongodb" ;;
        xdebug/xdebug) echo "xdebug" ;;
        open-telemetry/ext-opentelemetry) echo "opentelemetry" ;;
        php-amqp/php-amqp) echo "amqp" ;;
        pdezwart/php-amqp) echo "amqp" ;;
        rdkafka/rdkafka) echo "rdkafka" ;;
        *)
            local base
            base="${package##*/}"
            base="${base%-extension}"
            echo "${base//-/_}"
            ;;
    esac
}

enable_extension_ini() {
    local extension="$1"
    local scan_dir
    local ini_file
    local line="extension=${extension}"

    scan_dir="$(php --ini | awk -F': ' '/Scan for additional \.ini files in:/ {print $2}' | xargs)"
    if [ -z "$scan_dir" ] || [ "$scan_dir" = "(none)" ]; then
        ini_file="$(php --ini | awk -F': ' '/Loaded Configuration File:/ {print $2}' | xargs)"
        if [ -z "$ini_file" ] || [ "$ini_file" = "(none)" ]; then
            echo "Unable to locate php.ini to enable ${extension}" >&2
            exit 1
        fi
        if ! grep -Eq "^extension\s*=\s*${extension}(\.so)?$" "$ini_file"; then
            printf "\n%s\n" "$line" >> "$ini_file"
        fi
        return
    fi

    mkdir -p "$scan_dir"
    ini_file="${scan_dir}/99-${extension}.ini"
    if [ -f "$ini_file" ] && grep -Eq "^extension\s*=\s*${extension}(\.so)?$" "$ini_file"; then
        return
    fi
    printf "%s\n" "$line" > "$ini_file"
}

prepare_php_source() {
    local php_version
    local php_tarball
    local source_url

    if [ -n "$PHP_SOURCE_DIR" ] && [ -d "$PHP_SOURCE_DIR/ext" ]; then
        return
    fi

    php_version="$(php -r 'echo PHP_VERSION;')"
    php_version="${php_version%%-*}"
    php_tarball="/tmp/php-${php_version}.tar.gz"
    PHP_SOURCE_DIR="/tmp/php-src-${php_version}"
    source_url="https://www.php.net/distributions/php-${php_version}.tar.gz"

    rm -rf "$PHP_SOURCE_DIR"
    mkdir -p "$PHP_SOURCE_DIR"
    curl -fsSL "$source_url" -o "$php_tarball"
    tar -xzf "$php_tarball" -C "$PHP_SOURCE_DIR" --strip-components=1
}

build_bundled_extension() {
    local extension="$1"
    local source_ext_dir
    local build_dir

    if extension_is_loaded "$extension"; then
        return
    fi

    prepare_php_source
    source_ext_dir="${PHP_SOURCE_DIR}/ext/${extension}"
    if [ ! -d "$source_ext_dir" ]; then
        echo "Bundled extension source not found: ${extension}" >&2
        exit 1
    fi

    build_dir="/tmp/php-bundled-ext-${extension}"
    rm -rf "$build_dir"
    cp -R "$source_ext_dir" "$build_dir"

    pushd "$build_dir" >/dev/null
    phpize
    ./configure "--enable-${extension}"
    make -j"$(nproc)"
    make install
    popd >/dev/null

    enable_extension_ini "$extension"

    if ! extension_is_loaded "$extension"; then
        echo "Failed to load bundled extension: ${extension}" >&2
        exit 1
    fi

    rm -rf "$build_dir"
}

install_pie_binary() {
    local version_tag
    local pie_url

    PIE_TMP_DIR="$(mktemp -d)"
    if [ "$VERSION" = "latest" ]; then
        pie_url="https://github.com/php/pie/releases/latest/download/pie.phar"
    else
        version_tag="${VERSION#v}"
        pie_url="https://github.com/php/pie/releases/download/${version_tag}/pie.phar"
    fi

    curl -fsSL "$pie_url" -o "${PIE_TMP_DIR}/pie.phar"

    if [ "$VERIFY_ATTESTATION" = "true" ]; then
        if ! exists gh; then
            echo "gh CLI is required for verifyAttestation=true" >&2
            exit 1
        fi
        gh attestation verify --owner php "${PIE_TMP_DIR}/pie.phar"
    fi

    install -m 0755 "${PIE_TMP_DIR}/pie.phar" /usr/local/bin/pie
}

install_pie_extension() {
    local extension_spec="$1"
    local package_name="$1"
    local extension_name

    package_name="${package_name%%:*}"
    extension_name="$(extension_name_for_package "$package_name")"

    if extension_is_loaded "$extension_name"; then
        return
    fi

    pie install "$extension_spec"

    if ! extension_is_loaded "$extension_name"; then
        enable_extension_ini "$extension_name"
    fi

    if ! extension_is_loaded "$extension_name"; then
        echo "Failed to load PIE extension ${extension_name} from ${extension_spec}" >&2
        exit 1
    fi
}

collect_dependencies_from_extension() {
    local extension_spec="$1"
    local package_name="$1"

    package_name="${package_name%%:*}"
    case "$package_name" in
        imagick/imagick)
            add_apt_package "libmagickwand-dev"
            ;;
        php-memcached/php-memcached)
            add_apt_package "libmemcached-dev"
            add_apt_package "libsasl2-dev"
            add_apt_package "zlib1g-dev"
            ;;
        pecl/yaml)
            add_apt_package "libyaml-dev"
            ;;
        rdkafka/rdkafka)
            add_apt_package "librdkafka-dev"
            ;;
        php-amqp/php-amqp|pdezwart/php-amqp)
            add_apt_package "librabbitmq-dev"
            ;;
    esac
}

cleanup() {
    if [ -n "$PIE_TMP_DIR" ] && [ -d "$PIE_TMP_DIR" ]; then
        rm -rf "$PIE_TMP_DIR"
    fi
    if [ -n "$PHP_SOURCE_DIR" ] && [ -d "$PHP_SOURCE_DIR" ]; then
        rm -rf "$PHP_SOURCE_DIR"
    fi
}

trap cleanup EXIT

if ! exists php; then
    echo "PHP is required before installing PIE" >&2
    exit 1
fi

if [ "$INSTALL_PREREQS" = "true" ]; then
    add_apt_package "git"
    add_apt_package "unzip"
    add_apt_package "autoconf"
    add_apt_package "automake"
    add_apt_package "libtool"
    add_apt_package "m4"
    add_apt_package "make"
    add_apt_package "gcc"
    add_apt_package "pkg-config"
fi

if [ -n "$EXTENSIONS" ]; then
    IFS=',' read -r -a EXTENSION_LIST <<< "$EXTENSIONS"
    for extension_spec in "${EXTENSION_LIST[@]}"; do
        extension_spec="$(echo "$extension_spec" | xargs)"
        if [ -z "$extension_spec" ]; then
            continue
        fi
        collect_dependencies_from_extension "$extension_spec"
    done
fi

if [ "${#APT_PACKAGES[@]}" -gt 0 ]; then
    apt-get update
    apt-get install -y --no-install-recommends "${APT_PACKAGES[@]}"
    rm -rf /var/lib/apt/lists/*
fi

install_pie_binary

if ! exists pie; then
    echo "PIE installation failed" >&2
    exit 1
fi

pie --version

if [ -n "$EXTENSIONS" ]; then
    IFS=',' read -r -a EXTENSION_LIST <<< "$EXTENSIONS"
    for extension_spec in "${EXTENSION_LIST[@]}"; do
        extension_spec="$(echo "$extension_spec" | xargs)"
        if [ -z "$extension_spec" ]; then
            continue
        fi
        case "$extension_spec" in
            sockets|pcntl)
                build_bundled_extension "$extension_spec"
                ;;
            *)
                install_pie_extension "$extension_spec"
                ;;
        esac
    done
fi
