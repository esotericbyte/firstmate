#!/usr/bin/env bash
# tests/fm-node-pin.test.sh - a checkout's .node-version pin reaches the
# processes Firstmate controls through fnm, and nothing else.
#
# fnm is replaced by a fake that implements the one call the pin makes,
# `fnm exec --using=<version> -- <command...>`, against fixture install
# directories, so every case runs without fnm or a second Node installed. The
# pin library is exercised through its sourced functions, the Claude session
# path through bin/fm-sessionstart-run.sh, and the worker path through a real
# fm-spawn launch whose pane input is captured.
set -u

# shellcheck source=tests/fixtures.sh
. "$(dirname "${BASH_SOURCE[0]}")/fixtures.sh"

TMP_ROOT=$(fm_test_tmproot fm-node-pin)
FNM_ROOT="$TMP_ROOT/fnm"
FNM_BIN="$TMP_ROOT/fnm-bin"
PIN_BIN="$FNM_ROOT/v24.18.0/bin"

# A fake fnm with v24.18.0 installed: `--using` resolves 24, 24.18 and v24.18.0
# and runs the command with that version's bin directory first on PATH, as fnm
# does; any other version is refused the way fnm refuses an uninstalled one.
mkdir -p "$PIN_BIN" "$FNM_BIN"
printf '#!/bin/sh\necho v24.18.0\n' >"$PIN_BIN/node"
chmod +x "$PIN_BIN/node"
cat >"$FNM_BIN/fnm" <<SH
#!/bin/sh
[ "\$1" = exec ] || exit 2
case "\$2" in
  --using=24|--using=v24|--using=24.18|--using=v24.18|--using=24.18.0|--using=v24.18.0) ;;
  *) echo "error: Requested version \${2#--using=} is not currently installed" >&2; exit 1 ;;
esac
[ "\$3" = -- ] || exit 2
shift 3
PATH="$PIN_BIN:\$PATH" exec "\$@"
SH
chmod +x "$FNM_BIN/fnm"

LIB="$ROOT/bin/fm-node-pin-lib.sh"

commit_all() {  # <repo> <message>
  git -C "$1" add -A &&
    git -C "$1" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm "$2"
}

checkout_with_pin() {  # <dir> <.node-version content>
  mkdir -p "$1"
  printf '%s' "$2" >"$1/.node-version"
  printf '%s\n' "$1"
}

# Run one library call in a clean bash and print its exit status and the PATH it
# leaves behind.
lib_call() {  # <path> <function> <args...>
  local path=$1
  shift
  PATH="$path" /bin/bash -c '. "$1"; shift; "$@"; rc=$?; printf "rc=%s\nPATH=%s\n" "$rc" "$PATH"' \
    lib-call "$LIB" "$@"
}

test_version_forms() {
  local dir out
  for form in '24' $'24\n' $'v24.18.0\r\n' '  24.18  ' $'24\nlts/iron\n'; do
    dir=$(checkout_with_pin "$TMP_ROOT/form-$RANDOM" "$form")
    out=$(lib_call "$FNM_BIN:/usr/bin:/bin" fm_node_pin_bin "$dir")
    assert_contains "$out" "rc=0" "a plain version line should resolve: $(printf '%q' "$form")"
    assert_contains "$out" "$PIN_BIN" "the pinned bin directory should be printed for $(printf '%q' "$form")"
  done
  for form in 'lts/iron' 'node' '' $'\n24\n' '24; rm -rf /' '>=24'; do
    dir=$(checkout_with_pin "$TMP_ROOT/bad-$RANDOM" "$form")
    out=$(lib_call "$FNM_BIN:/usr/bin:/bin" fm_node_pin_bin "$dir")
    assert_contains "$out" "rc=1" "a non-version first line should not resolve: $(printf '%q' "$form")"
  done
  out=$(lib_call "$FNM_BIN:/usr/bin:/bin" fm_node_pin_bin "$TMP_ROOT/no-such-checkout")
  assert_contains "$out" "rc=1" "a checkout without .node-version should not resolve"
  pass "only a plain [v]MAJOR[.MINOR[.PATCH]] first line is accepted as a pin"
}

test_apply_prepends_once() {
  local dir out
  dir=$(checkout_with_pin "$TMP_ROOT/apply" '24')
  out=$(PATH="$FNM_BIN:/usr/bin:/bin" /bin/bash -c '
    . "$1"
    fm_node_pin_apply "$2" || exit 9
    first=$PATH
    fm_node_pin_apply "$2" || exit 9
    [ "$PATH" = "$first" ] || { echo "second apply changed PATH: $PATH"; exit 8; }
    command -v node
    printf "PATH=%s\n" "$PATH"' apply "$LIB" "$dir")
  expect_code 0 $? "applying the pin should succeed: $out"
  assert_contains "$out" "$PIN_BIN/node" "node should resolve to the pinned version after apply"
  assert_contains "$out" "PATH=$PIN_BIN:$FNM_BIN:/usr/bin:/bin" \
    "apply should put the pinned bin directory first and keep the rest of PATH in order"
  pass "applying the pin puts the pinned Node first on PATH and is idempotent"
}

test_absent_pin_leaves_path_unchanged() {
  local dir out
  dir=$(checkout_with_pin "$TMP_ROOT/absent" '24')
  # fnm missing from PATH entirely.
  out=$(lib_call "/usr/bin:/bin" fm_node_pin_apply "$dir")
  assert_contains "$out" "rc=1" "apply without fnm should report no pin"
  assert_contains "$out" "PATH=/usr/bin:/bin" "apply without fnm should leave PATH unchanged"
  # fnm present, version not installed.
  dir=$(checkout_with_pin "$TMP_ROOT/uninstalled" '25')
  out=$(lib_call "$FNM_BIN:/usr/bin:/bin" fm_node_pin_apply "$dir")
  assert_contains "$out" "rc=1" "apply for an uninstalled version should report no pin"
  assert_contains "$out" "PATH=$FNM_BIN:/usr/bin:/bin" \
    "apply for an uninstalled version should leave PATH unchanged"
  pass "a missing fnm or an uninstalled pinned version leaves PATH exactly as it was"
}

test_worker_pin_requires_same_repository() {
  local repo wt other out
  repo="$TMP_ROOT/worker-repo"
  wt="$TMP_ROOT/worker-wt"
  other="$TMP_ROOT/other-project"
  fm_git_init_commit "$repo"
  printf '24\n' >"$repo/.node-version"
  commit_all "$repo" pin
  git -C "$repo" worktree add -q "$wt" -b worker-branch
  fm_git_init_commit "$other"
  printf '24\n' >"$other/.node-version"
  out=$(lib_call "$FNM_BIN:/usr/bin:/bin" fm_node_pin_worker_bin "$wt" "$repo")
  assert_contains "$out" "rc=0" "a worktree of the same repository should get the pin"
  assert_contains "$out" "$PIN_BIN" "the worker pin should name the pinned bin directory"
  out=$(lib_call "$FNM_BIN:/usr/bin:/bin" fm_node_pin_worker_bin "$other" "$repo")
  assert_contains "$out" "rc=1" "another project's checkout should not get this repository's pin, even with its own .node-version"
  pass "the worker pin applies only to checkouts sharing the root's repository"
}

test_claude_env_file_persists_pin_once() {
  local root env_file out
  root=$(checkout_with_pin "$TMP_ROOT/session-root" '24')
  env_file="$TMP_ROOT/claude-env"
  : >"$env_file"
  # The fixture root is no primary home, so the wrapper stands down right after
  # the pin step and never runs a session start.
  for _ in 1 2; do
    FM_ROOT_OVERRIDE="$root" FM_HOME="$root" CLAUDE_ENV_FILE="$env_file" \
      PATH="$FNM_BIN:/usr/bin:/bin" "$ROOT/bin/fm-sessionstart-run.sh" --source startup </dev/null >/dev/null 2>&1
    expect_code 0 $? "the session-open wrapper should exit 0"
  done
  [ "$(wc -l <"$env_file" | tr -d ' ')" = 1 ] \
    || fail "two session opens should leave exactly one pin line, got: $(cat "$env_file")"
  out=$(PATH="/usr/bin:/bin" /bin/bash -c '. "$1"; command -v node; . "$1"; printf "PATH=%s\n" "$PATH"' env "$env_file")
  assert_contains "$out" "$PIN_BIN/node" "a Claude shell command should resolve node to the pinned version"
  assert_contains "$out" "PATH=$PIN_BIN:/usr/bin:/bin" "re-sourcing the env file should not prepend twice"
  # No fnm: the env file is left untouched.
  : >"$env_file"
  FM_ROOT_OVERRIDE="$root" FM_HOME="$root" CLAUDE_ENV_FILE="$env_file" \
    PATH="/usr/bin:/bin" "$ROOT/bin/fm-sessionstart-run.sh" --source startup </dev/null >/dev/null 2>&1
  [ ! -s "$env_file" ] || fail "without fnm the env file should stay empty, got: $(cat "$env_file")"
  pass "a Claude session gets one idempotent pin line in CLAUDE_ENV_FILE, and none without fnm"
}

# Build a fixture Firstmate repository from this checkout's bin/, so a spawn run
# from it treats a worktree of the fixture as a checkout of its own repository.
make_fixture_firstmate() {  # <dir>
  local dir=$1
  fm_git_init_commit "$dir"
  cp -R "$ROOT/bin" "$dir/bin"
  printf '24\n' >"$dir/.node-version"
  commit_all "$dir" fixture
}

spawn_from() {  # <code-root> <home> <pane-path> <fakebin> <args...>
  local code=$1 home=$2 pane=$3 fakebin=$4
  shift 4
  mkdir -p "$home/user-home"
  FM_ROOT_OVERRIDE='' FM_HOME="$home" HOME="$home/user-home" CLAUDE_CONFIG_DIR='' \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_PROJECTS_OVERRIDE="$home/projects" FM_CONFIG_OVERRIDE="$home/config" \
    FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$pane" TMUX="${TMUX:-fake,1,0}" \
    PATH="$fakebin:$FNM_BIN:$PATH" \
    "$code/bin/fm-spawn.sh" "$@" 2>&1
}

pin_export_line() { grep '^export PATH=' "$1" | grep -F "$PIN_BIN" || true; }

test_spawn_pins_firstmate_worker_only() {
  local case_dir fm wt home fakebin panelog launchlog out status line gotmp pin other otherwt
  case_dir="$TMP_ROOT/spawn"
  fm="$case_dir/firstmate"
  wt="$case_dir/fm-wt"
  home="$case_dir/home"
  panelog="$case_dir/pane.log"
  launchlog="$case_dir/launch.log"
  make_fixture_firstmate "$fm"
  git -C "$fm" worktree add -q "$wt" -b fm-wt
  fakebin=$(fm_test_make_spawn_fakebin "$case_dir/fake")
  fm_test_spawn_home "$home" codex
  fm_test_spawn_brief "$home" pin-ship-a1
  : >"$panelog"
  : >"$launchlog"
  out=$(FM_FAKE_LAUNCH_LOG="$launchlog" FM_FAKE_PANE_LOG="$panelog" \
    spawn_from "$fm" "$home" "$wt" "$fakebin" pin-ship-a1 "$fm" --mode no-mistakes --yolo off)
  status=$?
  expect_code 0 "$status" "a firstmate ship spawn should succeed: $out"
  line=$(pin_export_line "$panelog")
  [ -n "$line" ] || fail "a worker in a firstmate checkout should receive the pin export; pane got: $(cat "$panelog")"
  gotmp=$(grep -n '^export GOTMPDIR=' "$panelog" | tail -1 | cut -d: -f1)
  pin=$(grep -n '^export PATH=' "$panelog" | grep -F "$PIN_BIN" | tail -1 | cut -d: -f1)
  [ "$pin" -gt "$gotmp" ] || fail "the pin export should ride the pre-launch exports (gotmp=$gotmp pin=$pin)"
  out=$(PATH="/usr/bin:/bin" /bin/sh -c "$line
command -v node")
  assert_equals "$PIN_BIN/node" "$out" "the exported pane PATH should resolve node to the pinned version"

  other="$case_dir/other-project"
  otherwt="$case_dir/other-wt"
  fm_git_worktree "$other" "$otherwt" other-wt
  printf '24\n' >"$otherwt/.node-version"
  commit_all "$otherwt" pin
  fm_test_spawn_brief "$home" pin-other-a1
  : >"$panelog"
  : >"$launchlog"
  out=$(FM_FAKE_LAUNCH_LOG="$launchlog" FM_FAKE_PANE_LOG="$panelog" \
    spawn_from "$fm" "$home" "$otherwt" "$fakebin" pin-other-a1 "$other" --mode no-mistakes --yolo off)
  status=$?
  expect_code 0 "$status" "another project's ship spawn should succeed: $out"
  grep -q '^export GOTMPDIR=' "$panelog" || fail "the other-project pane log is missing its pre-launch exports"
  [ -z "$(grep '^export PATH=' "$panelog" || true)" ] \
    || fail "a worker on another project should keep its pane's own Node; pane got: $(cat "$panelog")"
  pass "spawn exports the pin into a firstmate worker's pane and leaves other projects' workers alone"
}

test_version_forms
test_apply_prepends_once
test_absent_pin_leaves_path_unchanged
test_worker_pin_requires_same_repository
test_claude_env_file_persists_pin_once
test_spawn_pins_firstmate_worker_only
