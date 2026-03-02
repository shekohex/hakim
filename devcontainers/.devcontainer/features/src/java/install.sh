#!/bin/bash
set -euo pipefail

VERSION=${VERSION:-"17"}

apt-get update

install_pkg=""
case "${VERSION}" in
17)
    for pkg in openjdk-17-jdk openjdk-17-jdk-headless; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            install_pkg="$pkg"
            break
        fi
    done
    if [ -z "$install_pkg" ]; then
        for pkg in openjdk-21-jdk openjdk-21-jdk-headless default-jdk default-jdk-headless; do
            if apt-cache show "$pkg" >/dev/null 2>&1; then
                install_pkg="$pkg"
                break
            fi
        done
    fi
    ;;
21)
    for pkg in openjdk-21-jdk openjdk-21-jdk-headless default-jdk default-jdk-headless; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            install_pkg="$pkg"
            break
        fi
    done
    ;;
*)
    echo "Unsupported Java version: ${VERSION}" >&2
    exit 1
    ;;
esac

if [ -z "$install_pkg" ]; then
    echo "No package found for Java ${VERSION}" >&2
    exit 1
fi

apt-get install -y --no-install-recommends "$install_pkg"
rm -rf /var/lib/apt/lists/*

JAVA_BIN="$(readlink -f "$(command -v javac)")"
JAVA_HOME="$(dirname "$(dirname "$JAVA_BIN")")"

cat <<EOF > /etc/profile.d/java.sh
export JAVA_HOME="${JAVA_HOME}"
if [[ ":\$PATH:" != *":\$JAVA_HOME/bin:"* ]]; then
    export PATH="\$JAVA_HOME/bin:\$PATH"
fi
EOF
chmod +x /etc/profile.d/java.sh

java -version
javac -version
