#!/usr/bin/env bash
# fm-no-ruby-check.sh - reject Ruby uses anywhere in the firstmate repository.
#
# Usage:
#   bin/fm-no-ruby-check.sh
#   bin/fm-no-ruby-check.sh --root <repo>
#
# Firstmate's tests and scripts read YAML with mikefarah yq v4 (see
# fm_require_yq in tests/lib.sh), never Ruby. This check fails when any tracked
# text file names the lowercase `ruby` command or Ruby tooling, or when any
# tracked *.rb file exists, so a sync that brings Ruby back fails before merge.
# It reads tracked content only, including staged and working-tree edits of
# tracked files, and skips binary files and this check and its test.
# bin/fm-lint.sh runs it against this repository.
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      [ "$#" -ge 2 ] || { echo "fm-no-ruby-check: --root needs a path" >&2; exit 2; }
      ROOT=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "fm-no-ruby-check: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "fm-no-ruby-check: not a git repository: $ROOT" >&2; exit 2; }

# This check and its test name Ruby on purpose.
hits=$(git -C "$ROOT" grep -n -I -E \
  -e '(^|[^[:alnum:]_.-])(ruby|setup-ruby|bundle exec|gem install)([^[:alnum:]_-]|$)' \
  -- ':!bin/fm-no-ruby-check.sh' ':!tests/fm-no-ruby-check.test.sh' || true)
rb_files=$(git -C "$ROOT" ls-files -- '*.rb' || true)

if [ -n "$hits" ] || [ -n "$rb_files" ]; then
  echo "fm-no-ruby-check: Ruby use found; read YAML with yq (fm_require_yq in tests/lib.sh) instead:" >&2
  [ -z "$hits" ] || printf '%s\n' "$hits" >&2
  [ -z "$rb_files" ] || printf '%s\n' "$rb_files" | sed 's/$/: tracked Ruby source/' >&2
  exit 1
fi
echo "fm-no-ruby-check: ok"
