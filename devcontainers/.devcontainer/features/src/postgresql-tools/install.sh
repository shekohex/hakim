#!/bin/bash

VERSION=${VERSION:-"17"}

echo "Activating feature 'postgresql-tools'"
echo "Installing PostgreSQL client tools (version: ${VERSION})..."

if [ "$VERSION" = "latest" ]; then
    echo "Installing latest PostgreSQL client from distro repository..."
    apt-get update
    apt-get install -y --no-install-recommends postgresql-client
else
    echo "Installing PostgreSQL ${VERSION} client from PGDG repository..."
    
    DISTRO=$(lsb_release -cs 2>/dev/null || echo "trixie")
    ARCH=$(dpkg --print-architecture)
    
    apt-get install -y --no-install-recommends curl ca-certificates gnupg lsb-release
    
    echo "Adding PostgreSQL GPG key..."
    install -d /etc/apt/keyrings
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
        gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
    chmod 644 /etc/apt/keyrings/postgresql.gpg
    
    echo "Adding PGDG repository..."
    echo "deb [signed-by=/etc/apt/keyrings/postgresql.gpg arch=${ARCH}] https://apt.postgresql.org/pub/repos/apt ${DISTRO}-pgdg main" \
        > /etc/apt/sources.list.d/postgresql.list
    
    # Retry apt-get update a few times in case of mirror sync issues
    UPDATE_SUCCESS=false
    for i in 1 2 3; do
        echo "Attempt $i: Running apt-get update..."
        if apt-get update; then
            UPDATE_SUCCESS=true
            break
        fi
        echo "apt-get update failed, waiting 30 seconds before retry..."
        sleep 30
    done
    
    if [ "$UPDATE_SUCCESS" != "true" ]; then
        echo "ERROR: apt-get update failed after 3 attempts" >&2
        exit 1
    fi
    
    echo "Installing postgresql-client-${VERSION}..."
    apt-get install -y --no-install-recommends postgresql-client-${VERSION}
    
    # Create symlinks for convenience if not using alternatives
    PG_BINDIR="/usr/lib/postgresql/${VERSION}/bin"
    if [ -d "$PG_BINDIR" ]; then
        for bin in psql pg_dump pg_dumpall pg_restore pg_isready pg_basebackup; do
            if [ -f "${PG_BINDIR}/${bin}" ]; then
                ln -sf "${PG_BINDIR}/${bin}" "/usr/local/bin/${bin}"
            fi
        done
    fi
fi

rm -rf /var/lib/apt/lists/*

echo "Verifying PostgreSQL client installation..."
psql --version

echo "PostgreSQL tools feature installation complete!"
