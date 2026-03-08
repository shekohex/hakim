#!/bin/bash
set -euo pipefail

ARG_GIT_USER_NAME=$(echo -n "${ARG_GIT_USER_NAME:-}" | base64 -d 2> /dev/null || echo "")
ARG_GIT_USER_EMAIL=$(echo -n "${ARG_GIT_USER_EMAIL:-}" | base64 -d 2> /dev/null || echo "")
ARG_GIT_GLOBAL_GITCONFIG=$(echo -n "${ARG_GIT_GLOBAL_GITCONFIG:-}" | base64 -d 2> /dev/null || echo "")
ARG_GIT_CREDENTIAL_HELPER=${ARG_GIT_CREDENTIAL_HELPER:-store}

if [ -z "$ARG_GIT_USER_NAME" ] && [ -z "$ARG_GIT_USER_EMAIL" ] && [ -z "$ARG_GIT_GLOBAL_GITCONFIG" ] && [ -z "$ARG_GIT_CREDENTIAL_HELPER" ]; then
  exit 0
fi

include_file="$HOME/.config/hakim/gitconfig"
mkdir -p "$(dirname "$include_file")"
touch "$include_file"

if ! git config --global --get-all include.path | grep -Fx "$include_file" > /dev/null 2>&1; then
  git config --global --add include.path "$include_file"
fi

tmp_file=$(mktemp)
{
  if [ -n "$ARG_GIT_USER_NAME" ] || [ -n "$ARG_GIT_USER_EMAIL" ]; then
    echo "[user]"
    if [ -n "$ARG_GIT_USER_NAME" ]; then
      echo "  name = $ARG_GIT_USER_NAME"
    fi
    if [ -n "$ARG_GIT_USER_EMAIL" ]; then
      echo "  email = $ARG_GIT_USER_EMAIL"
    fi
  fi

  if [ "$ARG_GIT_CREDENTIAL_HELPER" = "libsecret" ]; then
    echo "[credential]"
    echo "  helper = /usr/local/bin/git-credential-libsecret"
  fi

  if [ "$ARG_GIT_CREDENTIAL_HELPER" = "store" ]; then
    echo "[credential]"
    echo "  helper = store"
  fi

  if [ -n "$ARG_GIT_GLOBAL_GITCONFIG" ]; then
    printf "%s\n" "$ARG_GIT_GLOBAL_GITCONFIG"
  fi
} > "$tmp_file"

mv "$tmp_file" "$include_file"
