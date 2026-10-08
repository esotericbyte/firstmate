# shellcheck shell=bash
# fm-node-pin-lib.sh - apply a checkout's `.node-version` pin through fnm.
# Usage: . bin/fm-node-pin-lib.sh
#
# This file is the single owner of how Firstmate selects Node for its own
# processes. A checkout's `.node-version` names the Node version Firstmate needs
# (fork-notes/requirements.md explains why). The pin is applied only to the
# process environment Firstmate controls: the pinned version's bin directory
# is placed so `node` and every global npm tool fnm installed under that version
# resolve there ahead of the Node the caller would otherwise use. Nothing outside the
# repository is read for configuration or written: the user's shell startup
# files, fnm's default alias, and other projects keep their own Node.
#
# The pin is a preference, never a requirement. When the checkout has no
# readable `.node-version`, its first line is not a plain version
# (`[v]MAJOR[.MINOR[.PATCH]]`), `fnm` is not on PATH, or fnm has no installed
# version matching it, every function here leaves PATH unchanged and returns 1,
# so the process keeps whatever Node it already had.
#
# Resolution asks fnm itself (`fnm exec --using=<version>`), so fnm's own version
# matching and data-directory discovery apply; no fnm layout is assumed here.
#
# Callers:
#   bin/fm-sessionstart-run.sh  persists the pin into a Claude primary's later
#                               shell commands through CLAUDE_ENV_FILE
#   bin/fm-supervision-host.sh  applies the pin to the host and the engine it runs
#   bin/fm-spawn.sh             exports the pin into a worker pane before launch
#                               when the worker runs in a checkout of this repo
#                               (fm_node_pin_worker_bin); a worker on any other
#                               project keeps its pane's own Node

# fm_node_pin_version <dir>
# Print the validated version named by <dir>/.node-version, or return 1.
fm_node_pin_version() {
  local file="$1/.node-version" line
  [ -f "$file" ] && [ -r "$file" ] || return 1
  IFS= read -r line <"$file" || [ -n "$line" ] || return 1
  line=${line%$'\r'}
  line=${line#"${line%%[![:space:]]*}"}
  line=${line%"${line##*[![:space:]]}"}
  [[ "$line" =~ ^v?[0-9]+(\.[0-9]+){0,2}$ ]] || return 1
  printf '%s\n' "$line"
}

# fm_node_pin_bin <dir>
# Print the bin directory of the fnm-installed Node matching <dir>'s pin, or
# return 1 without output when any part of the pin is unavailable.
fm_node_pin_bin() {
  local version node_path
  version=$(fm_node_pin_version "$1") || return 1
  command -v fnm >/dev/null 2>&1 || return 1
  node_path=$(fnm exec --using="$version" -- sh -c 'command -v node' 2>/dev/null) || return 1
  case "$node_path" in
    /*/node) ;;
    *) return 1 ;;
  esac
  [ -x "$node_path" ] || return 1
  printf '%s\n' "${node_path%/node}"
}

# fm_node_pin_apply <dir>
# Export PATH with <dir>'s pinned Node bin directory inserted immediately before
# the first PATH entry holding an executable `node`, so entries ahead of that
# one (such as a test's stub directory) keep their precedence. When that entry
# already is the pinned directory PATH is left as it is; when no entry holds a
# `node` the pinned directory is appended.
fm_node_pin_apply() {
  local bin entry rest new=
  bin=$(fm_node_pin_bin "$1") || return 1
  rest=${PATH:-}
  while [ -n "$rest" ]; do
    entry=${rest%%:*}
    if [ -n "$entry" ] && [ -x "$entry/node" ] && [ ! -d "$entry/node" ]; then
      [ "$entry" = "$bin" ] && return 0
      PATH="$new$bin:$rest"
      export PATH
      return 0
    fi
    new="$new$entry:"
    case "$rest" in
      *:*) rest=${rest#*:} ;;
      *) rest= ;;
    esac
  done
  PATH="${PATH:+$PATH:}$bin"
  export PATH
}

# fm_node_pin_worker_bin <worker-dir> <firstmate-root>
# Print the pinned bin directory for a worker launched in <worker-dir>, but only
# when <worker-dir> is a checkout of the same repository as <firstmate-root>
# (they share one git common directory). The pin is read from <worker-dir>, so
# the worker runs on the Node its own checkout names.
fm_node_pin_worker_bin() {
  local worker_common root_common
  worker_common=$(cd "$1" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  root_common=$(cd "$2" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  worker_common=$(cd "$worker_common" 2>/dev/null && pwd -P) || return 1
  root_common=$(cd "$root_common" 2>/dev/null && pwd -P) || return 1
  [ "$worker_common" = "$root_common" ] || return 1
  fm_node_pin_bin "$1"
}
