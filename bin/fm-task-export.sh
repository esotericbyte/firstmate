#!/usr/bin/env bash
# fm-task-export.sh - write the open backlog, with census fields and recommendation history, to tasks.json.
#
# Usage: fm-task-export.sh [--out <path>]
#        fm-task-export.sh --help
#
# Writes one JSON object, {"generated": <UTC ISO-8601>, "tasks": [...]}, holding
# every open (not Done) backlog task as bin/fm-tasks-axi.sh reports it, in
# backlog order. Firstmate is the file's only writer; the reader is docstrap's
# task tool. The write is atomic: a temporary file beside the target is renamed
# over it, so a reader never sees a partial file.
#
# Default --out is <data>/docstrap/docs/triage/tasks.json, where <data> is
# FM_DATA_OVERRIDE, else $FM_HOME/data, else the code root's data/.
#
# Inputs, all under <data>/task-census/:
#   records/<id>.yaml          optional census record for task <id>.
#   recommendations/<id>.yaml  optional recommendation history for task <id>:
#                              a YAML list of {action, note, date, by}, where
#                              action is close-done | close-duplicate |
#                              close-obsolete | reshape | dispatch | hold | ask |
#                              keep, date is YYYY-MM-DD, and by is firstmate |
#                              captain. Append a new entry to record a new
#                              recommendation. A captain entry taken in from
#                              docstrap's task tool also carries decided_at,
#                              which this export does not output (see
#                              bin/fm-procevent-docstrap.sh, TASK DECISIONS).
#
# Per task:
#   id, title, project (backlog repo, or "none"), filed (backlog created date),
#   hold_reason ("" when not held), and blocked_by (list of ids) come from the
#   backlog. state is in_flight for an In flight row, else held when the row is
#   held, else blocked when it has an open blocker, else queued.
#   unit, last_activity, work, stuck, alignment, plan, done_elsewhere,
#   done_evidence, lifecycle_stage, lifecycle_evidence, and tangle come from the
#   census record. A task with no record gets "" for each; nothing is guessed.
#   page is "tasks/<id>" when <triage>/tasks/<id>.md exists beside the output,
#   else "".
#   recommendations is the history list in file order (oldest first), and
#   latest_recommendation is its entry with the newest date (the later entry
#   wins a tie), or null when there is no history.
#
# Exit status: 0 on success; 2 on a usage error, a missing tool (jq, yq), or a
# backlog read or census file that cannot be parsed, with nothing written.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
TASKS_AXI="$SCRIPT_DIR/fm-tasks-axi.sh"

usage() {
  awk '
    NR == 1 { next }
    /^#/ { sub(/^# ?/, ""); print; next }
    { exit }
  ' "$0"
}

fail() {
  printf 'fm-task-export: %s\n' "$*" >&2
  exit 2
}

OUT="$DATA/docstrap/docs/triage/tasks.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      [ $# -ge 2 ] && [ -n "$2" ] || fail "--out needs a path"
      OUT=$2
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) fail "unknown argument: $1 (see --help)" ;;
  esac
done

command -v jq >/dev/null 2>&1 || fail "jq not found on PATH"
command -v yq >/dev/null 2>&1 || fail "yq not found on PATH"

CENSUS="$DATA/task-census"
OUT_DIR=$(dirname "$OUT")
mkdir -p "$OUT_DIR" || fail "cannot create $OUT_DIR"

WORK=$(mktemp -d "${TMPDIR:-/tmp}/fm-task-export.XXXXXX") || fail "cannot create a temporary directory"
trap 'rm -rf "$WORK"' EXIT

listing=$("$TASKS_AXI" list --limit 100000) || fail "backlog list failed"
# The list's rows are `  <id>,<state>,...`; ids carry no commas or quotes.
ids=$(printf '%s\n' "$listing" | awk '
  /^tasks\[/ { rows = 1; next }
  rows && /^  [^ ]/ { split(substr($0, 3), f, ","); if (f[2] != "done") print f[1]; next }
  rows { rows = 0 }
')

: > "$WORK/show.yaml"
for id in $ids; do
  {
    printf -- '---\n'
    "$TASKS_AXI" show "$id" --full || fail "backlog show $id failed"
  } >> "$WORK/show.yaml"
done
yq -o json -I 0 '.task' "$WORK/show.yaml" | jq -s '.' > "$WORK/backlog.json" \
  || fail "could not parse the backlog rows"

# Set key <id> of the JSON object in <file> to the value in $WORK/one.json.
merge_into() {  # <file> <id>
  jq --arg id "$2" --slurpfile r "$WORK/one.json" '.[$id] = $r[0]' "$1" > "$WORK/next.json" || return 1
  mv "$WORK/next.json" "$1"
}

# Census records and recommendation histories, keyed by task id.
printf '{}' > "$WORK/records.json"
printf '{}' > "$WORK/recs.json"
for id in $ids; do
  record="$CENSUS/records/$id.yaml"
  if [ -f "$record" ]; then
    yq -o json -I 0 '.' "$record" > "$WORK/one.json" || fail "cannot parse $record"
    merge_into "$WORK/records.json" "$id" || fail "cannot merge $record"
  fi
  history="$CENSUS/recommendations/$id.yaml"
  if [ -f "$history" ]; then
    yq -o json -I 0 '.' "$history" > "$WORK/one.json" || fail "cannot parse $history"
    jq -e 'type == "array"' "$WORK/one.json" >/dev/null || fail "$history is not a list"
    merge_into "$WORK/recs.json" "$id" || fail "cannot merge $history"
  fi
done

pages=$(for id in $ids; do [ -f "$OUT_DIR/tasks/$id.md" ] && printf '%s\n' "$id"; done)

generated=$(date -u +%Y-%m-%dT%H:%M:%SZ)
tmp_out=$(mktemp "$OUT_DIR/.tasks.json.XXXXXX") || fail "cannot create a temporary file in $OUT_DIR"
if ! jq -n \
  --arg generated "$generated" \
  --arg pages "$pages" \
  --slurpfile backlog "$WORK/backlog.json" \
  --slurpfile records "$WORK/records.json" \
  --slurpfile recs "$WORK/recs.json" '
  def str: if . == null then "" else tostring end;
  def day: str | .[0:10];
  def none_dash: if . == null or . == "-" or . == "none" then "" else . end;
  def ids: if . == null then [] elif type == "array" then map(tostring)
           else (none_dash | split(",") | map(gsub("^ +| +$"; "")) | map(select(. != ""))) end;
  def entry: {action: (.action | str), note: (.note | str), date: (.date | day), by: (.by | str)};
  ($pages | split("\n") | map(select(. != ""))) as $page_ids
  | {generated: $generated,
     tasks: [ $backlog[0][]
       | . as $t
       | ($records[0][$t.id] // null) as $r
       | (($recs[0][$t.id] // []) | map(entry)) as $history
       | {id: $t.id,
          title: ($t.title | str),
          project: ($t.repo | none_dash | if . == "" then "none" else . end),
          unit: ($r.unit | str),
          state: (if $t.state == "in_flight" then "in_flight"
                  elif $t.held == "yes" then "held"
                  elif $t.blocked == "yes" then "blocked"
                  else "queued" end),
          hold_reason: ($t.hold_reason | none_dash | str),
          blocked_by: ($t.blocked_by | ids),
          filed: ($t.created | none_dash | day),
          last_activity: ($r.last_activity | day),
          work: ($r.work | str),
          stuck: ($r.stuck | str),
          alignment: ($r.alignment | str),
          plan: ($r.plan | str),
          done_elsewhere: ($r.done_elsewhere | str),
          done_evidence: ($r.done_evidence | str),
          lifecycle_stage: ($r.lifecycle_stage | str),
          lifecycle_evidence: ($r.lifecycle_evidence | str),
          tangle: ($r.tangle | str),
          page: (if ($page_ids | index($t.id)) != null then "tasks/\($t.id)" else "" end),
          latest_recommendation: (if ($history | length) == 0 then null
            else ($history | to_entries | max_by([.value.date, .key]) | .value) end),
          recommendations: $history} ]}
' > "$tmp_out"; then
  rm -f "$tmp_out"
  fail "could not assemble tasks.json"
fi
if ! chmod 0644 "$tmp_out" || ! mv -f "$tmp_out" "$OUT"; then
  rm -f "$tmp_out"
  fail "cannot replace $OUT"
fi
printf 'wrote %s: %s tasks\n' "$OUT" "$(jq '.tasks | length' "$OUT")"
