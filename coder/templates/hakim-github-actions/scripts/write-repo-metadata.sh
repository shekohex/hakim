#!/usr/bin/env bash
set -euo pipefail

ARG_GIT_URL="$(echo -n "${ARG_GIT_URL:-}" | base64 -d 2>/dev/null || true)"
ARG_GIT_BRANCH="$(echo -n "${ARG_GIT_BRANCH:-}" | base64 -d 2>/dev/null || true)"
ARG_METADATA_PATH="$(echo -n "${ARG_METADATA_PATH:-}" | base64 -d 2>/dev/null || true)"

if [[ -z "$ARG_METADATA_PATH" ]]; then
  exit 0
fi

repo_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
mkdir -p "$(dirname "$ARG_METADATA_PATH")"

python3 - <<'PY' "$ARG_METADATA_PATH" "$repo_dir" "$ARG_GIT_URL" "$ARG_GIT_BRANCH"
import json
import subprocess
import sys

metadata_path, repo_dir, git_url, git_branch = sys.argv[1:5]

def git(*args):
    return subprocess.check_output(["git", "-C", repo_dir, *args], text=True).strip()

metadata = {
    "repo_dir": repo_dir,
    "git_url": git_url,
    "git_branch": git_branch,
    "origin_url": git("remote", "get-url", "origin"),
    "head_sha": git("rev-parse", "HEAD"),
    "head_branch": git("symbolic-ref", "--quiet", "--short", "HEAD"),
}

with open(metadata_path, "w", encoding="ascii") as f:
    json.dump(metadata, f, indent=2)
    f.write("\n")
PY
