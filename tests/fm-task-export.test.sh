#!/usr/bin/env bash
# Behavior tests for bin/fm-task-export.sh: it writes every open backlog task,
# merged with its census record and recommendation history, to tasks.json.
#
# Each case builds a home with a real tasks-axi backlog and census files, runs
# the export, and reads the JSON it wrote. The suite proves the state mapping,
# that Done rows are left out, that a task without a census record keeps its
# census fields empty instead of guessed, that latest_recommendation is the
# newest history entry, and that a bad census file leaves the old output alone.
set -u

# shellcheck source=tests/lib.sh disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

EXPORT="$ROOT/bin/fm-task-export.sh"
WRAPPER="$ROOT/bin/fm-tasks-axi.sh"
TMP_ROOT=$(fm_test_tmproot fm-task-export)

unset TASKS_AXI_FILE TASKS_AXI_BACKEND FM_HOME FM_ROOT_OVERRIDE FM_DATA_OVERRIDE

for tool in tasks-axi jq yq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "skip: $tool not found; fm-task-export cases not run"
    exit 0
  fi
done

make_home() {  # <name>; prints the home directory
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/data/task-census/records" "$home/data/task-census/recommendations" \
    "$home/data/docstrap/docs/triage/tasks"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  printf '%s\n' "$home"
}

axi() {  # <home> <tasks-axi args...>
  local home=$1
  shift
  FM_HOME="$home" "$WRAPPER" "$@" >/dev/null || fail "tasks-axi $* failed"
}

run_export() {  # <home>
  FM_HOME="$1" "$EXPORT" >/dev/null
}

task_field() {  # <home> <id> <jq path>
  jq -c --arg id "$2" ".tasks[] | select(.id == \$id) | $3" \
    "$1/data/docstrap/docs/triage/tasks.json"
}

test_states_and_open_rows() {
  local home
  home=$(make_home states)
  axi "$home" add t-queued "queued, with \"quotes\"" --repo alpha
  axi "$home" add t-held "held task"
  axi "$home" hold t-held --reason "pick one?" --kind captain
  axi "$home" add t-blocked "blocked task" --repo beta
  axi "$home" block t-blocked --by t-queued
  axi "$home" block t-blocked --by t-held
  axi "$home" add t-flight "in flight task"
  axi "$home" start t-flight
  axi "$home" add t-done "done task"
  axi "$home" "done" t-done
  run_export "$home" || fail "export failed"

  assert_equals "4" "$(jq '.tasks | length' "$home/data/docstrap/docs/triage/tasks.json")" \
    "export must hold exactly the open tasks"
  assert_equals "" "$(task_field "$home" t-done .id)" "a Done task must be left out"
  assert_equals '"queued"' "$(task_field "$home" t-queued .state)" "plain row state"
  assert_equals '"held"' "$(task_field "$home" t-held .state)" "held row state"
  assert_equals '"blocked"' "$(task_field "$home" t-blocked .state)" "blocked row state"
  assert_equals '"in_flight"' "$(task_field "$home" t-flight .state)" "in-flight row state"
  assert_equals '"pick one?"' "$(task_field "$home" t-held .hold_reason)" "hold reason"
  assert_equals '""' "$(task_field "$home" t-queued .hold_reason)" "unheld row has no hold reason"
  assert_equals '["t-queued","t-held"]' "$(task_field "$home" t-blocked .blocked_by)" "blockers"
  assert_equals '"queued, with \"quotes\""' "$(task_field "$home" t-queued .title)" "title"
  assert_equals '"alpha"' "$(task_field "$home" t-queued .project)" "project from repo"
  assert_equals '"none"' "$(task_field "$home" t-held .project)" "a row with no repo"
  assert_equals "\"$(date +%Y-%m-%d)\"" "$(task_field "$home" t-queued .filed)" "filed date"
  pass "fm-task-export.sh maps backlog state and leaves Done rows out"
}

test_census_merge_and_empty_fields() {
  local home
  home=$(make_home census)
  axi "$home" add t-rec "has a record" --repo alpha
  axi "$home" add t-bare "has no record"
  cat > "$home/data/task-census/records/t-rec.yaml" <<'EOF'
id: t-rec
unit: apps/players
last_activity: '2026-10-01'
work: docs+code
stuck: captain
plan: docs/plan.md
alignment: drifted
done_elsewhere: likely
done_evidence: abc123 did it
duplicate_of:
- t-bare
recommendation: reshape
EOF
  touch "$home/data/docstrap/docs/triage/tasks/t-rec.md"
  run_export "$home" || fail "export failed"

  assert_equals '{"unit":"apps/players","last_activity":"2026-10-01","work":"docs+code","stuck":"captain","alignment":"drifted","plan":"docs/plan.md","done_elsewhere":"likely","done_evidence":"abc123 did it","duplicate_of":["t-bare"],"page":"tasks/t-rec"}' \
    "$(task_field "$home" t-rec '{unit,last_activity,work,stuck,alignment,plan,done_elsewhere,done_evidence,duplicate_of,page}')" \
    "census fields must come from the record"
  assert_equals '{"unit":"","last_activity":"","work":"","stuck":"","alignment":"","plan":"","done_elsewhere":"","done_evidence":"","duplicate_of":[],"page":""}' \
    "$(task_field "$home" t-bare '{unit,last_activity,work,stuck,alignment,plan,done_elsewhere,done_evidence,duplicate_of,page}')" \
    "a task without a record must keep its census fields empty"
  assert_equals 'null' "$(task_field "$home" t-rec .latest_recommendation)" \
    "a record alone must not invent a recommendation history"
  pass "fm-task-export.sh merges census records and leaves unrecorded fields empty"
}

test_latest_recommendation() {
  local home
  home=$(make_home recs)
  axi "$home" add t-rec "has history"
  cat > "$home/data/task-census/recommendations/t-rec.yaml" <<'EOF'
- action: hold
  note: first look
  date: "2026-10-13"
  by: firstmate
- action: dispatch
  note: captain ruled
  date: "2026-10-20"
  by: captain
- action: ask
  note: older entry appended late
  date: "2026-10-15"
  by: firstmate
EOF
  run_export "$home" || fail "export failed"

  assert_equals '{"action":"dispatch","note":"captain ruled","date":"2026-10-20","by":"captain"}' \
    "$(task_field "$home" t-rec .latest_recommendation)" "latest must be the newest-dated entry"
  assert_equals '3' "$(task_field "$home" t-rec '.recommendations | length')" "full history"
  pass "fm-task-export.sh reports the newest recommendation as latest"
}

test_bad_census_keeps_old_output() {
  local home out before
  home=$(make_home bad)
  axi "$home" add t-one "one task"
  run_export "$home" || fail "first export failed"
  out="$home/data/docstrap/docs/triage/tasks.json"
  before=$(cat "$out")
  printf 'action: not a list\n' > "$home/data/task-census/recommendations/t-one.yaml"
  if FM_HOME="$home" "$EXPORT" >/dev/null 2>&1; then
    fail "a malformed history must make the export fail"
  fi
  assert_equals "$before" "$(cat "$out")" "a failed export must leave the old file in place"
  assert_equals "" "$(find "$(dirname "$out")" -maxdepth 1 -name '.tasks.json.*')" \
    "a failed export must leave no temporary file"
  pass "fm-task-export.sh refuses a malformed history without touching tasks.json"
}

test_states_and_open_rows
test_census_merge_and_empty_fields
test_latest_recommendation
test_bad_census_keeps_old_output
