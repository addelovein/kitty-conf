# Kitty-specific bash helpers

__title_git_branch() {
  command -v git >/dev/null 2>&1 || return
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return
  [[ "$branch" = "HEAD" ]] && branch=""
  [[ -n "$branch" ]] && printf '%s' "$branch"
}
