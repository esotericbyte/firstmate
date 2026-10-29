#!/usr/bin/env bash
# Regression tests for bin/fm-no-ruby-check.sh, the guard that keeps Ruby out
# of the firstmate repository in favor of yq.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CHECK="$ROOT/bin/fm-no-ruby-check.sh"
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-no-ruby-check.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

run_expect_failure() {
  local expected=$1
  shift
  local out rc
  out=$("$@" 2>&1)
  rc=$?
  [ "$rc" -eq 1 ] || fail "expected exit 1 containing '$expected', got $rc: $out"
  assert_contains "$out" "$expected" "failure did not name '$expected'"
}

new_fixture_repo() {
  local repo="$TMP_ROOT/$1"
  mkdir -p "$repo/bin" "$repo/tests" "$repo/.github/workflows"
  git -C "$repo" init -q
  printf '%s\n' '#!/usr/bin/env bash' 'yq -o=json . config.yml | jq .' >"$repo/tests/clean.test.sh"
  git -C "$repo" add tests
  printf '%s\n' "$repo"
}

test_clean_fixture_passes() {
  local repo out
  repo=$(new_fixture_repo clean)
  printf '%s\n' '# Parse YAML; Ruby is not used here.' >"$repo/bin/tool.sh"
  git -C "$repo" add bin
  out=$("$CHECK" --root "$repo" 2>&1) || fail "clean fixture rejected: $out"
  assert_contains "$out" "fm-no-ruby-check: ok" "clean fixture did not report ok"
  pass "yq-only scripts and capitalized prose mentions pass"
}

test_ruby_uses_fail() {
  local repo
  repo=$(new_fixture_repo test-use)
  printf '%s\n' "ruby -ryaml -e 'puts YAML.load_file(ARGV[0])' ci.yml" >>"$repo/tests/clean.test.sh"
  git -C "$repo" add tests
  run_expect_failure "tests/clean.test.sh:3:" "$CHECK" --root "$repo"

  repo=$(new_fixture_repo bin-guard)
  printf '%s\n' 'command -v ruby >/dev/null || exit 1' >"$repo/bin/tool.sh"
  git -C "$repo" add bin
  run_expect_failure "bin/tool.sh:1:" "$CHECK" --root "$repo"

  repo=$(new_fixture_repo workflow)
  printf '%s\n' '      - uses: ruby/setup-ruby@v1' >"$repo/.github/workflows/ci.yml"
  git -C "$repo" add .github
  run_expect_failure ".github/workflows/ci.yml:1:" "$CHECK" --root "$repo"

  repo=$(new_fixture_repo skill)
  mkdir -p "$repo/skills/tool"
  printf '%s\n' 'ruby -ryaml -e 1 config.yml' >"$repo/skills/tool/run.sh"
  git -C "$repo" add skills
  run_expect_failure "skills/tool/run.sh:1:" "$CHECK" --root "$repo"

  repo=$(new_fixture_repo rb-source)
  printf '%s\n' 'require "yaml"' >"$repo/tests/parse.rb"
  git -C "$repo" add tests
  run_expect_failure "tests/parse.rb: tracked Ruby source" "$CHECK" --root "$repo"
  pass "ruby commands anywhere in the tree, Ruby setup actions, and tracked .rb files fail naming the location"
}

test_untracked_files_are_ignored() {
  local repo out
  repo=$(new_fixture_repo untracked)
  printf '%s\n' 'ruby -e 1' >"$repo/tests/scratch.sh"
  out=$("$CHECK" --root "$repo" 2>&1) || fail "untracked scratch was rejected: $out"
  pass "untracked files do not fail the check"
}

test_clean_fixture_passes
test_ruby_uses_fail
test_untracked_files_are_ignored
