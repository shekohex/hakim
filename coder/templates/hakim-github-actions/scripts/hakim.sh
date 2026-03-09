#!/usr/bin/env bash
set -euo pipefail

command_name="${1:-help}"
if [[ $# -gt 0 ]]; then
  shift
fi

print_help() {
  cat <<'EOF'
Hakim workspace helper

Usage:
  hakim help
  hakim status
  hakim stop
  hakim yield [repo-path]
  hakim mcp

Commands:
  stop   Stop the current workspace with `coder stop`.
  yield  Verify your repo is pushed, then stop the current workspace.
  status Show detected workspace, auth, and repo details.
  mcp    Show how to expose Coder lifecycle tools through the experimental MCP server.

Recommended flow:
  1. Commit your work.
  2. Push your branch.
  3. Run `hakim yield`.

`hakim yield` checks:
  - a Git repo exists
  - working tree is clean
  - HEAD is not detached
  - upstream is configured
  - there are no unpushed commits

If you intentionally want to stop without Git safety checks, run `hakim stop`.

Auth notes:
  - Hakim uses the Coder CLI under the hood.
  - Keep the template's `Enable Coder Login` option enabled, or run `coder login "$CODER_URL"` first.
EOF
}

workspace_ref() {
  if [[ -n "${HAKIM_WORKSPACE_OWNER:-}" ]]; then
    printf '%s/%s' "$HAKIM_WORKSPACE_OWNER" "${HAKIM_WORKSPACE_NAME:-unknown}"
    return
  fi

  printf '%s' "${HAKIM_WORKSPACE_NAME:-unknown}"
}

repo_metadata_file() {
  printf '%s' "${HAKIM_REPO_METADATA_FILE:-$HOME/.local/share/hakim/repo.json}"
}

resolve_repo_root() {
  local candidate="${1:-}"

  if [[ -n "$candidate" ]] && git -C "$candidate" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$candidate" rev-parse --show-toplevel
    return
  fi

  if [[ -n "${HAKIM_PROJECT_DIR:-}" ]] && git -C "$HAKIM_PROJECT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    git -C "$HAKIM_PROJECT_DIR" rev-parse --show-toplevel
    return
  fi

  if [[ -f "$(repo_metadata_file)" ]]; then
    repo_root="$(sed -n 's/.*"repo_dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$(repo_metadata_file)" | head -n 1)"
    if [[ -n "$repo_root" ]] && git -C "$repo_root" rev-parse --show-toplevel >/dev/null 2>&1; then
      git -C "$repo_root" rev-parse --show-toplevel
      return
    fi
  fi

  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return
  fi

  return 1
}

require_coder_auth() {
  if coder whoami >/dev/null 2>&1; then
    return
  fi

  printf 'Coder CLI is not authenticated for workspace control.\n' >&2
  if [[ -n "${CODER_URL:-}" ]]; then
    printf 'Run `coder login "%s"` and try again.\n' "$CODER_URL" >&2
  else
    printf "Enable the template's `Enable Coder Login` option or log in manually.\n" >&2
  fi
  exit 1
}

print_status() {
  local repo_root auth_state

  if coder whoami >/dev/null 2>&1; then
    auth_state='ready'
  else
    auth_state='missing'
  fi

  printf 'workspace: %s\n' "$(workspace_ref)"
  printf 'coder auth: %s\n' "$auth_state"
  printf 'project dir: %s\n' "${HAKIM_PROJECT_DIR:-<unset>}"
  printf 'repo metadata: %s\n' "$(repo_metadata_file)"
  if [[ -n "${HAKIM_GIT_URL:-}" ]]; then
    printf 'git url: %s\n' "$HAKIM_GIT_URL"
  fi
  if [[ -n "${HAKIM_GIT_BRANCH:-}" ]]; then
    printf 'git branch: %s\n' "$HAKIM_GIT_BRANCH"
  fi

  if repo_root="$(resolve_repo_root 2>/dev/null)"; then
    printf 'repo root: %s\n' "$repo_root"
    printf 'repo branch: %s\n' "$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null || printf '<detached>')"
  else
    printf 'repo root: <not detected>\n'
  fi
}

check_yield_git_state() {
  local repo_root="$1"
  local branch upstream ahead_count

  if [[ -n "$(git -C "$repo_root" status --porcelain --untracked-files=all)" ]]; then
    printf 'Refusing to yield: working tree is not clean in %s. Commit, stash, or discard your changes first.\n' "$repo_root" >&2
    exit 1
  fi

  branch="$(git -C "$repo_root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "$branch" ]]; then
    printf 'Refusing to yield: HEAD is detached in %s. Check out a branch and push it first.\n' "$repo_root" >&2
    exit 1
  fi

  upstream="$(git -C "$repo_root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
  if [[ -z "$upstream" ]]; then
    printf 'Refusing to yield: branch `%s` has no upstream. Push with `git push -u origin %s` first.\n' "$branch" "$branch" >&2
    exit 1
  fi

  if [[ -n "${HAKIM_GIT_BRANCH:-}" ]] && [[ "$branch" != "$HAKIM_GIT_BRANCH" ]]; then
    printf 'Refusing to yield: current branch `%s` does not match configured branch `%s`.\n' "$branch" "$HAKIM_GIT_BRANCH" >&2
    exit 1
  fi

  ahead_count="$(git -C "$repo_root" rev-list --count '@{upstream}..HEAD' 2>/dev/null || printf '0')"
  if [[ "$ahead_count" != '0' ]]; then
    printf 'Refusing to yield: branch `%s` is %s commit(s) ahead of `%s`. Push first.\n' "$branch" "$ahead_count" "$upstream" >&2
    exit 1
  fi
}

stop_workspace() {
  require_coder_auth
  printf 'Stopping workspace %s...\n' "$(workspace_ref)"
  exec coder stop -y "$(workspace_ref)"
}

yield_workspace() {
  local repo_root

  require_coder_auth

  if ! repo_root="$(resolve_repo_root "${1:-}" 2>/dev/null)"; then
    printf 'No Git repository detected. Use `hakim stop` to stop without Git safety checks.\n' >&2
    exit 1
  fi

  check_yield_git_state "$repo_root"
  printf 'Yield checks passed for %s. Stopping workspace %s...\n' "$repo_root" "$(workspace_ref)"
  exec coder stop -y "$(workspace_ref)"
}

print_mcp_info() {
  cat <<'EOF'
Coder exposes an experimental MCP server with workspace lifecycle tools.

Useful command:
  coder exp mcp server

Hakim currently uses `coder stop` directly for reliable in-workspace shutdown.
Use the MCP server when you want external AI tools to manage workspace lifecycle.
EOF
}

case "$command_name" in
  help|-h|--help)
    print_help
    ;;
  status)
    print_status
    ;;
  stop)
    stop_workspace
    ;;
  yield)
    yield_workspace "${1:-}"
    ;;
  mcp)
    print_mcp_info
    ;;
  *)
    print_help >&2
    exit 1
    ;;
esac
