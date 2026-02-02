#!/bin/bash
set -e

VERSION=${VERSION:-"5.24.3"}
TOOLS=${TOOLS:-""}
GLOBAL_COMPOSER_HOME="/usr/local/share/composer"

echo "Activating feature 'laravel'"

# Function to check if a command exists
exists() {
  command -v "$1" >/dev/null 2>&1
}

# Ensure composer is installed
if ! exists composer; then
    echo "Composer is not installed. Please install it before using this feature."
    exit 1
fi

# Set global composer home for installation
export COMPOSER_HOME="$GLOBAL_COMPOSER_HOME"
mkdir -p "$COMPOSER_HOME"

# Install Laravel Installer
echo "Installing Laravel Installer..."
if [ "$VERSION" = "latest" ]; then
    composer global require laravel/installer
else
    composer global require laravel/installer:"$VERSION"
fi

# Install extra tools
if [ -n "$TOOLS" ]; then
    echo "Installing extra tools..."
    IFS=',' read -r -a TOOLS_ARRAY <<< "$TOOLS"
    for TOOL in "${TOOLS_ARRAY[@]}"; do
        TOOL=$(echo "$TOOL" | xargs) # trim whitespace
        case "$TOOL" in
            pint)
                echo "Installing Laravel Pint..."
                composer global require laravel/pint
                ;;
            php-cs-fixer)
                echo "Installing PHP-CS-Fixer..."
                composer global require friendsofphp/php-cs-fixer
                ;;
            rector)
                echo "Installing Rector..."
                composer global require rector/rector
                ;;
            *)
                echo "Warning: Unknown tool '$TOOL'. Skipping."
                ;;
        esac
    done
fi

# Fix permissions
chmod -R 755 "$GLOBAL_COMPOSER_HOME"

COMPOSER_PATH_EXPORT='export PATH="/usr/local/share/composer/vendor/bin:${COMPOSER_HOME:-$HOME/.composer}/vendor/bin:${PATH}"'

# Add to bash.bashrc for non-login shells
if [[ "$(cat /etc/bash.bashrc)" != *"$COMPOSER_PATH_EXPORT"* ]]; then
    echo "$COMPOSER_PATH_EXPORT" >> /etc/bash.bashrc
fi

# Add to zshrc if zsh is installed
if [ -f "/etc/zsh/zshrc" ] && [[ "$(cat /etc/zsh/zshrc)" != *"$COMPOSER_PATH_EXPORT"* ]]; then
    echo "$COMPOSER_PATH_EXPORT" >> /etc/zsh/zshrc
fi

# Keep profile.d for login shells
cat << 'EOF' > /etc/profile.d/composer.sh
export PATH="/usr/local/share/composer/vendor/bin:${COMPOSER_HOME:-$HOME/.composer}/vendor/bin:${PATH}"
EOF
chmod +x /etc/profile.d/composer.sh

echo "Done!"
