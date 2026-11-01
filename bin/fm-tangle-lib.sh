# shellcheck shell=bash
# Shared worktree-tangle guard for the firstmate-on-itself case.
# Usage: . bin/fm-tangle-lib.sh
#
# Firstmate is a treehouse-pooled git repo of itself: crewmate worktrees and
# secondmate homes are all linked `git worktree`s of the same repo, while the
# PRIMARY checkout (the repo root firstmate operates from) is a normal checkout
# on a real branch - normally the default branch, main. The "worktree tangle"
# failure mode is a crewmate spawned to work on firstmate ITSELF branching and
# committing in the primary checkout instead of its own disposable worktree,
# stranding the primary on a feature branch (e.g. fm/readme-restructure-d3).
#
# fm_primary_tangle_branch detects exactly that and nothing else: a NAMED,
# non-default branch checked out in the given root. It is deliberately silent for
# every legitimate state - the primary on its default branch, and detached HEAD,
# which is how every linked worktree and secondmate home legitimately sits on the
# default branch. Detached HEAD on the default is fine; a feature branch in a
# primary checkout is the alarm.
#
# A home with config/self-update-source ("<remote> <branch>") may run its
# primary on that configured branch, so fm_primary_expected_branch treats the
# configured branch exactly as the default branch is treated, while the default
# branch stays healthy too; without the file nothing changes.
# fm_self_update_source_parse is the one parser of that file, shared with
# bin/fm-update.sh, which refuses on a malformed file; every other caller falls
# back to the default branch.

# Resolve the default branch name of the git repo at <dir>: prefer origin/HEAD,
# then fall back to a local main/master. Echoes the name, or returns 1.
fm_default_branch() {
  local dir=$1 ref branch
  ref=$(git -C "$dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  if [ -n "$ref" ]; then
    printf '%s\n' "${ref#origin/}"
    return 0
  fi
  for branch in main master; do
    if git -C "$dir" show-ref --verify --quiet "refs/heads/$branch"; then
      printf '%s\n' "$branch"
      return 0
    fi
  done
  return 1
}

# Parse the self-update source file <file> against the repo at <root>.
# Absent: echo nothing, return 2. Valid: echo "<remote> <branch>", return 0.
# Present but unusable: echo the reason, return 1.
fm_self_update_source_parse() {
  local file=$1 root=$2 content remote branch extra lines
  [ -e "$file" ] || [ -L "$file" ] || return 2
  if [ -L "$file" ] || [ ! -f "$file" ] || [ ! -r "$file" ]; then
    printf '%s\n' "not a readable regular file"
    return 1
  fi
  content=$(cat "$file") || { printf '%s\n' "cannot be read"; return 1; }
  lines=$(printf '%s\n' "$content" | grep -c '')
  if [ "$lines" -ne 1 ]; then
    printf '%s\n' 'expected exactly one line "<remote> <branch>"'
    return 1
  fi
  case "$content" in
    *[[:cntrl:]]*) printf '%s\n' "contains a control character"; return 1 ;;
  esac
  read -r remote branch extra <<EOF
$content
EOF
  if [ -z "$remote" ] || [ -z "$branch" ] || [ -n "$extra" ]; then
    printf '%s\n' 'expected exactly one line "<remote> <branch>"'
    return 1
  fi
  case "$remote" in
    -*|*/*) printf "invalid remote name '%s'\n" "$remote"; return 1 ;;
  esac
  if ! git -C "$root" remote get-url "$remote" >/dev/null 2>&1; then
    printf "remote '%s' does not exist in %s\n" "$remote" "$root"
    return 1
  fi
  case "$branch" in
    -*) printf "invalid branch name '%s'\n" "$branch"; return 1 ;;
  esac
  if ! git check-ref-format "refs/heads/$branch" >/dev/null 2>&1; then
    printf "invalid branch name '%s'\n" "$branch"
    return 1
  fi
  printf '%s %s\n' "$remote" "$branch"
}

# The branch a usable <config>/self-update-source names. Echoes it, or returns 1
# when <config> is empty or the file is absent or unusable.
fm_self_update_source_branch() {
  local root=$1 config=${2:-} parsed
  [ -n "$config" ] || return 1
  parsed=$(fm_self_update_source_parse "$config/self-update-source" "$root") || return 1
  printf '%s\n' "${parsed#* }"
}

# The branch the primary checkout at <root> counts as sitting on correctly: the
# self-update source branch while the primary is on it, otherwise the default
# branch. Echoes the name, or returns 1. Omitting <config> means the default.
fm_primary_expected_branch() {
  local root=$1 config=${2:-} configured cur
  if configured=$(fm_self_update_source_branch "$root" "$config"); then
    cur=$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
    if [ "$cur" = "$configured" ]; then
      printf '%s\n' "$configured"
      return 0
    fi
  fi
  fm_default_branch "$root"
}

# The branch a tangle remediation should restore the primary to: the self-update
# source branch when one is configured, otherwise the default branch.
fm_primary_restore_branch() {
  fm_self_update_source_branch "$1" "${2:-}" || fm_default_branch "$1"
}

# If the git checkout at <root> is tangled - on a NAMED branch that is not its
# expected branch (fm_primary_expected_branch with optional <config>) - echo the
# offending branch name and return 0. For every healthy state (not a git work
# tree, detached HEAD, or already on the expected branch) echo nothing and
# return 1. Detached HEAD is how linked worktrees and secondmate homes
# legitimately sit, so they never trip this; only a feature branch checked out
# in a primary checkout does.
fm_primary_tangle_branch() {
  local root=$1 config=${2:-} cur default
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
  cur=$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)
  [ -n "$cur" ] || return 1
  default=$(fm_primary_expected_branch "$root" "$config") || return 1
  [ "$cur" = "$default" ] && return 1
  printf '%s\n' "$cur"
  return 0
}
