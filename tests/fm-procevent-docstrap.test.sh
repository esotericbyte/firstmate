#!/usr/bin/env bash
# Behavioral tests for bin/fm-procevent-docstrap.sh.
#
# The question document is checked against docstrap's three discovery rules two
# ways: by an independent reader written here from
# packages/docstrap/docs/finding-questions.md, which runs everywhere, and - when
# docstrap is installed - by docstrap itself, which is the only thing that can
# prove the independent reader still agrees with the real detector.
set -u
umask 022

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-procevent-docstrap.XXXXXX")
BIN="$LAB/bin"
HOME_DIR="$LAB/home"
PROJECT="$LAB/proj"
STORE_DIR="$LAB/promdance-storage"
DOC="$PROJECT/docs/questions.md"
ADAPTER="$BIN/fm-procevent-docstrap.sh"

cleanup() { rm -rf "$LAB"; }
trap cleanup EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
ok() { printf 'ok - %s\n' "$1"; }

mkdir -p "$BIN" "$HOME_DIR/state" "$HOME_DIR/config" "$PROJECT/docs/plans" "$STORE_DIR"
cp "$ROOT/bin/fm-procevent-docstrap.sh" "$BIN/"
chmod 755 "$ADAPTER"
ln -s "$STORE_DIR" "$PROJECT/$(basename promdance)"
STORE="$PROJECT/promdance/answers.md"
printf '# The bridge plan\n' > "$PROJECT/docs/plans/bridge.md"
printf '# Something else\n' > "$PROJECT/docs/plans/other.md"

# The two siblings this adapter calls. Only their answers matter here: what a
# keyed answer MEANS belongs to bin/fm-captain-hold.sh's own tests, and the
# runner's capture and publication belong to bin/fm-procevent.sh's.
cat > "$BIN/fm-captain-hold.sh" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  open) case "${2:-}" in fm-held-*) exit 0 ;; *) exit 1 ;; esac ;;
  binding) [ -n "${FAKE_BOUND:-}" ] || exit 1; printf '(any)\n'; exit 0 ;;
esac
exit 1
SH
cat > "$BIN/fm-procevent.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_PROCEVENT_LOG:-/dev/null}"
exit 0
SH
# The backlog reader the reference provenance test goes through. Only
# fm-held-two's record names the bridge plan.
cat > "$BIN/fm-tasks-axi-lib.sh" <<'SH'
# test stand-in; the adapter needs no symbol from here
SH
cat > "$BIN/fm-backlog-transition-lib.sh" <<'SH'
fm_backlog_data_absolute() { printf '%s\n' "$1"; }
fm_backlog_row_show() {
  case "${2:-}" in
    fm-held-two) printf '  id: fm-held-two\n  body: "blocked on docs/plans/bridge.md"\n' ;;
    *) printf '  id: %s\n  body: "no document is named here"\n' "${2:-}" ;;
  esac
}
SH
chmod 755 "$BIN"/*.sh

export FM_HOME="$HOME_DIR"
export FM_DOCSTRAP_WAIT_SECONDS=0

payload() { cat > "$LAB/payload.json"; }

payload <<'JSON'
{
  "schema": "fm-docstrap-questions.v1",
  "title": "Open decisions",
  "intro": "Two decisions are waiting on the captain.",
  "questions": [
    {"task": "fm-held-one",
     "question": "Should the exporter refuse a question that is not interrogative?",
     "context": "A wrong refusal costs one reword, which is cheaper than a confusing question.",
     "options": ["Refuse it", "Warn only"]},
    {"task": "fm-held-two",
     "question": "Is a project-relative path the right reference form?",
     "references": ["docs/plans/bridge.md", "docs/plans/other.md"]}
  ]
}
JSON

# --- export -----------------------------------------------------------------

out=$("$ADAPTER" export "$DOC" "$LAB/payload.json" 2>"$LAB/export.err") \
  || fail "export refused a valid payload: $(cat "$LAB/export.err")"
printf '%s\n' "$out" | grep -q '^questions: 2$' || fail "export did not report two questions"
SID=$(printf '%s\n' "$out" | sed -n 's/^source-id: //p')
[ -n "$SID" ] || fail "export printed no source id"
[ -f "$DOC" ] || fail "export wrote no document"
ok "export writes a question document and reports its source id"

# Rule 1: every question is a block whose first line opens with a `Q<n>` label,
# and the block runs to the next blank line.
# Rule 2: no label inside a heading, a fence, a blockquote, or front matter.
# Rule 3: the labels form one ascending run and it is the last one.
# An independent reader of the document, written from docstrap's own three
# rules rather than from this adapter's source.
labelled_runs() {  # <document>
  perl -e '
    use strict; use warnings;
    my ($path) = @ARGV;
    open my $fh, "<", $path or exit 1;
    my ($fence, @found) = ("");
    while (my $line = <$fh>) {
      chomp $line;
      if ($line =~ /^ {0,3}(`{3,}|~{3,})/) { $fence = $fence ? "" : $1; next }
      next if $fence;
      next if $line =~ /^ {0,3}#{1,6}\s/;
      next if $line =~ /^ {0,3}>/;
      if ($line =~ /^[ \t]{0,3}(?:(?:[-*+]|\d+[.)])[ \t]+)?(?:\[[ xX]\][ \t]+)?(?:\*\*|__)?Q(\d+)[*_]*[.:)][ \t]+\S/) {
        push @found, $1;
      }
    }
    print join(",", @found), "\n";
  ' "$1"
}
[ "$(labelled_runs "$DOC")" = "1,2" ] \
  || fail "the document does not carry exactly one ascending Q1..Q2 run: $(labelled_runs "$DOC")"
ok "the question document satisfies docstrap's three discovery rules"

# Each question block must end at a blank line with only the question in it, so
# the context paragraph and the options are separate blocks the panel's question
# text never absorbs.
perl -e '
  use strict; use warnings;
  my ($path) = @ARGV;
  open my $fh, "<", $path or exit 1;
  my @lines = map { chomp; $_ } <$fh>;
  for my $i (0 .. $#lines) {
    next unless $lines[$i] =~ /^Q\d+\. /;
    exit 1 unless $i == $#lines || $lines[$i + 1] eq "";
  }
  exit 0;
' "$DOC" || fail "a question block runs past its own line"
ok "each question block is one line and ends at a blank line"

if command -v docstrap >/dev/null 2>&1; then
  found=$(docstrap questions "$DOC" --json 2>/dev/null | grep -c '"label"' || true)
  [ "$found" = 2 ] || fail "docstrap itself found $found questions, not 2"
  docstrap questions "$DOC" --json 2>/dev/null | grep -q 'Should the exporter refuse' \
    || fail "docstrap did not read the first question's text"
  docstrap questions "$DOC" --json 2>/dev/null | grep -q 'A wrong refusal costs' \
    && fail "the context paragraph leaked into the question text"
  ok "docstrap itself finds exactly the exported questions"
else
  printf '# skip - docstrap is not installed; the independent reader above still ran\n'
fi

# --- context references -----------------------------------------------------

grep -q '^fm-ref:' "$DOC" && fail "a reference appeared with the opt-in flag absent"
grep -q 'dropped-reference: Q2 docs/plans/bridge.md' "$LAB/export.err" \
  || fail "the dropped reference was not named on stderr"
ok "references are dropped, and named, while the opt-in flag is absent"

touch "$HOME_DIR/config/docstrap-references"
"$ADAPTER" export "$DOC" "$LAB/payload.json" >/dev/null 2>"$LAB/export2.err" \
  || fail "export refused after enabling references"
grep -qx 'fm-ref: Q2 path=docs/plans/bridge.md' "$DOC" \
  || fail "the cited reference was not emitted"
grep -q 'path=docs/plans/other.md' "$DOC" \
  && fail "an uncited reference was emitted"
grep -q 'dropped-reference: Q2 docs/plans/other.md (the held task does not name it)' "$LAB/export2.err" \
  || fail "the uncited reference was not reported as dropped"
grep -q 'href=\|](' "$DOC" && fail "the reference was emitted as a link rather than a file reference"
ok "an opted-in reference survives only when the held task's record names it"

[ "$(labelled_runs "$DOC")" = "1,2" ] \
  || fail "the reference line disturbed the question run"
ok "a reference line is not itself discovered as a question"

sed 's#docs/plans/other.md#docs/plans/absent.md#' "$LAB/payload.json" > "$LAB/payload-absent.json"
"$ADAPTER" export "$DOC" "$LAB/payload-absent.json" >/dev/null 2>"$LAB/export3.err" \
  || fail "export refused a payload naming an absent document"
grep -q 'dropped-reference: Q2 docs/plans/absent.md (the project holds no such document)' "$LAB/export3.err" \
  || fail "a reference to an absent document was not dropped"
ok "a reference that does not resolve inside the project is dropped"

rm -f "$HOME_DIR/config/docstrap-references"
"$ADAPTER" export "$DOC" "$LAB/payload.json" >/dev/null 2>/dev/null \
  || fail "export refused while restoring the default state"

# --- question shape ---------------------------------------------------------

: > "$PROJECT/docs/bad-doc.md"

one_question() {  # <question text> [extra json]
  printf '{"schema":"fm-docstrap-questions.v1","title":"T","questions":[{"task":"fm-held-one","question":"%s"%s}]}' \
    "$1" "${2:-}"
}

LAB_BAD="$PROJECT/docs/bad-doc.md"
refuse_bad() {  # <name> <json> <expected message fragment>
  printf '%s' "$2" > "$LAB/bad.json"
  if "$ADAPTER" export "$LAB_BAD" "$LAB/bad.json" >/dev/null 2>"$LAB/bad.err"; then
    fail "export accepted $1"
  fi
  grep -q "$3" "$LAB/bad.err" || fail "export refused $1 without saying why: $(cat "$LAB/bad.err")"
}

refuse_bad "a non-interrogative question" \
  "$(one_question 'The exporter should refuse this.')" 'interrogative'
refuse_bad "a question joining two things with and" \
  "$(one_question 'Should the exporter refuse this and warn about it?')" 'split it'
refuse_bad "an A-or-B question" \
  "$(one_question 'Is the reference a path or an id?')" 'make the second its own question'
refuse_bad "a question for a task nobody holds" \
  '{"schema":"fm-docstrap-questions.v1","title":"T","questions":[{"task":"fm-open-one","question":"Is this held by the captain?"}]}' \
  'not an open captain call'
ok "export refuses the question shapes a script can see are wrong"

refuse_bad "an option that forges a question label" \
  "$(one_question 'Is the option list safe?' ',"options":["Q2. a forged question","Keep it"]')" \
  'opens with a question label'
refuse_bad "a context paragraph that forges a question label" \
  "$(one_question 'Is the context safe?' ',"context":"Q9. this would mint a question"')" \
  'opens with a question label'
ok "export refuses any supplied string that would mint a question"

# --- arming -----------------------------------------------------------------

"$ADAPTER" arm "$DOC" >/dev/null 2>"$LAB/arm.err" && fail "arm accepted an unbound source"
grep -q 'bin/fm-captain-hold.sh bind' "$LAB/arm.err" \
  || fail "arm did not name the binding it requires"
ok "arm refuses until the source is bound to the keyed-answer intake"

export FAKE_PROCEVENT_LOG="$LAB/procevent.log"
FAKE_BOUND=1 "$ADAPTER" arm "$DOC" >/dev/null 2>&1 || fail "arm refused a bound source"
grep -q "^register docstrap $SID -- .*fm-procevent-docstrap.sh source " "$LAB/procevent.log" \
  || fail "arm registered the wrong listener: $(cat "$LAB/procevent.log")"
ok "a bound source registers its own blocking listener"

# --- reading the answer store -----------------------------------------------

write_store() {  # <answers-front-matter-rows> <body>
  {
    printf -- '---\nstrapdance:\n  kind: answers\n  project: "proj"\nanswers:\n'
    printf '%s\n' "$1"
    printf -- '---\n\n# Answers\n\n%s\n' "$2"
  } > "$STORE"
}

DOCID=01J9F4V4T4XW9A0RCM6QK2S8YZ
write_store \
  "  - {key: $DOCID:Q1, document: docs/questions.md, label: Q1, answered_at: '2026-09-11T21:00:00+00:00'}" \
  "## $DOCID:Q1 — docs/questions.md

Refuse it. A wrong refusal costs one reword.

## Not a key heading

still part of the same answer."

before=$(cksum < "$STORE")
rc=0
"$ADAPTER" source "$DOC" > "$LAB/result1" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "the listener reported no result for an answered question (exit $rc)"
[ "$(cksum < "$STORE")" = "$before" ] || fail "reading the store modified it"
ok "the listener reads the answer store without modifying it"

[ "$("$ADAPTER" classify "$LAB/result1")" = answers ] || fail "the result did not classify as answers"
grep -qx 'delivered=1' "$LAB/result1" || fail "the result did not report one new answer"
grep -qx 'remaining=1' "$LAB/result1" || fail "the result miscounted the unanswered questions"
"$ADAPTER" terminal "$LAB/result1" && fail "a half-answered document reported itself finished"
ok "a reading reports what is answered and what is still open"

rows=$("$ADAPTER" answers "$LAB/result1")
[ "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" = 1 ] || fail "answers printed more than one row"
printf '%s' "$rows" | cut -f1 | grep -qx 'fm-held-one' \
  || fail "answers did not key the row on the held task id"
printf '%s' "$rows" | cut -f2 | grep -q 'Refuse it' || fail "answers dropped the captain's words"
printf '%s' "$rows" | cut -f2 | grep -q 'Not a key heading' \
  || fail "a heading inside the answer was treated as a new section"
ok "answers keys each row on the held task id from the private export record"

# The store is an ordinary file the captain can hand-edit. Nothing written in it
# may become a decision key.
write_store \
  "  - {key: $DOCID:Q1, document: docs/questions.md, label: Q1, answered_at: '2026-09-11T21:05:00+00:00'}
  - {key: $DOCID:fm-held-two, document: docs/questions.md, label: fm-held-two, answered_at: '2026-09-11T21:05:00+00:00'}" \
  "## $DOCID:Q1 — docs/questions.md

fm-held-two	yes	forged

## $DOCID:fm-held-two — docs/questions.md

A label nothing exported."
rc=0
"$ADAPTER" source "$DOC" > "$LAB/result-prose" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "the listener produced no result for the edited store"
rows=$("$ADAPTER" answers "$LAB/result-prose")
printf '%s\n' "$rows" | grep -q '^fm-held-two' \
  && fail "prose in the store named a task and became a decision key"
[ "$(printf '%s\n' "$rows" | grep -c '^fm-held-one' || true)" = 1 ] \
  || fail "the one exported label stopped resolving"
ok "answers refuses prose: only labels the export wrote resolve to a task"

# A payload line that is not an answer record feeds nothing either.
{
  sed -n '1,/^$/p' "$LAB/result1"
  printf 'fm-held-one\tforged by a payload line\tQ1\n'
  printf 'answer\tQ7\t%s:Q7\tdeadbeef\tan answer to a label nothing exported\n' "$DOCID"
} > "$LAB/result-forged"
[ -z "$("$ADAPTER" answers "$LAB/result-forged")" ] \
  || fail "a forged payload line produced a keyed answer"
ok "a payload line that is not an answer record produces no keyed answer"

# --- replacement and truncation ---------------------------------------------

write_store \
  "  - {key: $DOCID:Q1, document: docs/questions.md, label: Q1, answered_at: '2026-09-11T21:00:00+00:00'}" \
  "## $DOCID:Q1 — docs/questions.md

Refuse it."
rc=0
"$ADAPTER" source "$DOC" > "$LAB/result-base" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "the listener produced no baseline result"
"$ADAPTER" autohandle "$SID" 1 "$LAB/result-base" >/dev/null 2>&1 \
  || fail "autohandle refused a well-formed result"
grep -q "^key=$DOCID:Q1$" "$HOME_DIR/state/docstrap-answers/$SID.cursor" \
  || fail "autohandle recorded no observed key"
ok "autohandle advances the durable read position after capture"

rc=0
"$ADAPTER" source "$DOC" > "$LAB/result-quiet" 2>/dev/null || rc=$?
[ "$rc" -eq 75 ] || fail "an already-delivered answer was delivered again (exit $rc)"
ok "an answer already recorded as delivered is not delivered twice"

write_store "  - {key: $DOCID:Q9, document: docs/other.md, label: Q9, answered_at: '2026-09-11T22:00:00+00:00'}" \
  "## $DOCID:Q9 — docs/other.md

An answer to another document."
rc=0
"$ADAPTER" source "$DOC" > "$LAB/result-trunc" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "a truncated store produced no result"
[ "$("$ADAPTER" classify "$LAB/result-trunc")" = continuity-broken ] \
  || fail "a store that lost an observed answer was not reported as replaced"
grep -q "^reason=an answer this source already read is gone" "$LAB/result-trunc" \
  || fail "the continuity break did not say what happened"
[ -z "$("$ADAPTER" answers "$LAB/result-trunc")" ] \
  || fail "a continuity break still delivered an answer"
ok "a truncated or replaced store is detected and delivers nothing"

printf 'not a document with front matter at all\n' > "$STORE"
rc=0
"$ADAPTER" source "$DOC" > "$LAB/result-unparsed" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "an unparseable store produced no result"
[ "$("$ADAPTER" classify "$LAB/result-unparsed")" = continuity-broken ] \
  || fail "an unparseable store was not reported as a continuity break"
ok "a store that stops parsing as an answer file is a continuity break"

rm -f "$STORE"
rc=0
"$ADAPTER" source "$DOC" > "$LAB/result-gone" 2>/dev/null || rc=$?
[ "$("$ADAPTER" classify "$LAB/result-gone")" = continuity-broken ] \
  || fail "a vanished store was not reported as a continuity break"
ok "a store that vanishes after being read is a continuity break"

# --- re-export renumbering ---------------------------------------------------

# Narrowing a question set renumbers it, so an answer written before a re-export
# belongs to whatever used to sit at that label. Handing it to the task that
# sits there now would close a captain call with someone else's words.
REDOC="$PROJECT/docs/renumber.md"
cat > "$LAB/first.json" <<'JSON'
{"schema":"fm-docstrap-questions.v1","title":"Round one","questions":[
  {"task":"fm-held-one","question":"Is the first question answered first?"},
  {"task":"fm-held-two","question":"Is the second question still open?"}]}
JSON
cat > "$LAB/second.json" <<'JSON'
{"schema":"fm-docstrap-questions.v1","title":"Round two","questions":[
  {"task":"fm-held-two","question":"Is the second question still open?"}]}
JSON
"$ADAPTER" export "$REDOC" "$LAB/first.json" >/dev/null 2>&1 || fail "the first export failed"
REDOCID=01HRENUMBERRENUMBERRENUM
{
  printf -- '---\nstrapdance:\n  kind: answers\n  project: "proj"\nanswers:\n'
  printf "  - {key: %s:Q1, document: docs/renumber.md, label: Q1, answered_at: '2026-09-11T21:00:00+00:00'}\n" "$REDOCID"
  printf -- '---\n\n# Answers\n\n## %s:Q1 \xe2\x80\x94 docs/renumber.md\n\nThis answers the FIRST question.\n' "$REDOCID"
} > "$STORE"

# The captain's answer to Q1 is in the store but has not been read yet when the
# question set is narrowed and fm-held-two moves up to Q1.
"$ADAPTER" export "$REDOC" "$LAB/second.json" > "$LAB/reexport.out" 2>&1 \
  || fail "the narrowing re-export failed"
grep -q '^read-position: baselined' "$LAB/reexport.out" \
  || fail "a re-export that renumbered the questions did not re-baseline"
rc=0
"$ADAPTER" source "$REDOC" > "$LAB/result-renumber" 2>/dev/null || rc=$?
[ "$rc" -eq 75 ] \
  || fail "an answer written before the renumbering was delivered against the new task"
ok "a re-export that renumbers the questions does not misdeliver an earlier answer"

# A new answer written after the re-export still reaches the task now at Q1.
{
  printf -- '---\nstrapdance:\n  kind: answers\n  project: "proj"\nanswers:\n'
  printf "  - {key: %s:Q1, document: docs/renumber.md, label: Q1, answered_at: '2026-09-11T22:00:00+00:00'}\n" "$REDOCID"
  printf -- '---\n\n# Answers\n\n## %s:Q1 \xe2\x80\x94 docs/renumber.md\n\nThis answers the question that is there NOW.\n' "$REDOCID"
} > "$STORE"
rc=0
"$ADAPTER" source "$REDOC" > "$LAB/result-renumber2" 2>/dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "an answer written after the re-export was not delivered"
"$ADAPTER" answers "$LAB/result-renumber2" | grep -q '^fm-held-two	This answers the question that is there NOW' \
  || fail "the answer after a re-export did not reach the task now at that label"
ok "an answer written after a re-export reaches the task now at that label"

# An export that changes nothing must not disturb a pending answer.
"$ADAPTER" export "$REDOC" "$LAB/second.json" > "$LAB/reexport2.out" 2>&1 \
  || fail "an identical re-export failed"
grep -q '^read-position: baselined' "$LAB/reexport2.out" \
  && fail "an identical re-export re-baselined the read position"
ok "an export that changes nothing leaves the read position alone"

"$ADAPTER" retire "$REDOC" >/dev/null 2>&1 || true

# --- presentation and retirement --------------------------------------------

"$ADAPTER" read "$LAB/result1" > "$LAB/read.out" || fail "read refused a captured result"
grep -q '^status: answers$' "$LAB/read.out" || fail "read did not report the status"
grep -q '^ANSWER Q1$' "$LAB/read.out" || fail "read did not present the answer"
grep -q 'Refuse it' "$LAB/read.out" || fail "read dropped the captain's words"
ok "read presents a captured result without changing anything"

"$ADAPTER" retire "$DOC" >/dev/null || fail "retire failed"
[ ! -e "$HOME_DIR/state/docstrap-answers/$SID.cursor" ] || fail "retire left the read position behind"
[ ! -e "$HOME_DIR/state/docstrap-questions/$SID.map" ] || fail "retire left the question record behind"
grep -q "^retire $SID$" "$LAB/procevent.log" || fail "retire did not retire the registration"
ok "retire drops the registration and this source's private records"

# --- through the real runner -------------------------------------------------

# Everything above stands the two siblings in. This last case runs the genuine
# bin/fm-procevent.sh over the genuine adapter, because plugging into the
# adapter family is exactly the thing a stand-in cannot prove.
LIVE="$LAB/live"
mkdir -p "$LIVE/state/docstrap-questions" "$LIVE/proj/docs" "$LIVE/store"
ln -s "$LIVE/store" "$LIVE/proj/promdance"
LIVE_DOC="$LIVE/proj/docs/questions.md"
printf '# Open decisions\n\n## Questions\n\nQ1. Does the runner capture this reading?\n' > "$LIVE_DOC"
LIVE_SID=$(FM_STATE_OVERRIDE="$LIVE/state" "$ROOT/bin/fm-procevent-docstrap.sh" source-id "$LIVE_DOC")
{
  printf 'schema=fm-docstrap-map.v1\n'
  printf 'source_id=%s\n' "$LIVE_SID"
  printf 'document=docs/questions.md\n'
  printf 'document_path=%s\n' "$LIVE_DOC"
  printf 'project_root=%s\n' "$LIVE/proj"
  printf 'store=%s\n' "$LIVE/proj/promdance/answers.md"
  printf 'exported_at=2026-09-11T00:00:00Z\n'
  printf 'count=1\n'
  printf 'q=Q1\tfm-held-live\n'
} > "$LIVE/state/docstrap-questions/$LIVE_SID.map"
LIVE_DOCID=01HZZZZZZZZZZZZZZZZZZZZZZZ
{
  printf -- '---\nstrapdance:\n  kind: answers\n  project: "proj"\nanswers:\n'
  printf "  - {key: %s:Q1, document: docs/questions.md, label: Q1, answered_at: '2026-09-11T21:00:00+00:00'}\n" "$LIVE_DOCID"
  printf -- '---\n\n# Answers\n\n## %s:Q1 \xe2\x80\x94 docs/questions.md\n\nYes, and here are the words.\n' "$LIVE_DOCID"
} > "$LIVE/store/answers.md"

live_store_before=$(cksum < "$LIVE/store/answers.md")
(
  export FM_STATE_OVERRIDE="$LIVE/state"
  unset FM_HOME
  "$ROOT/bin/fm-procevent.sh" register docstrap "$LIVE_SID" \
    -- "$ROOT/bin/fm-procevent-docstrap.sh" source "$LIVE_DOC" >/dev/null \
    || exit 1
  "$ROOT/bin/fm-procevent.sh" start "$LIVE_SID" > "$LAB/live.out" 2>&1
) || fail "the live runner refused the docstrap source: $(cat "$LAB/live.out" 2>/dev/null)"

grep -q '^captured: ' "$LAB/live.out" || fail "the runner captured no result: $(cat "$LAB/live.out")"
grep -q "^autohandled: $LIVE_SID$" "$LAB/live.out" || fail "the runner did not apply the reading"
[ "$(cksum < "$LIVE/store/answers.md")" = "$live_store_before" ] \
  || fail "a live runner pass modified the answer store"
grep -q "^key=$LIVE_DOCID:Q1$" "$LIVE/state/docstrap-answers/$LIVE_SID.cursor" \
  || fail "the live pass recorded no read position"
grep -q "check: procevent docstrap $LIVE_SID" "$LIVE/state/.wake-queue" \
  || fail "the live pass published no wake"
live_result="$LIVE/state/procevent-inbox/$LIVE_SID.1.result"
[ -f "$live_result" ] || fail "the runner stored no durable capture"
FM_STATE_OVERRIDE="$LIVE/state" "$ROOT/bin/fm-procevent-docstrap.sh" answers "$live_result" \
  | grep -qx "fm-held-live	Yes, and here are the words.	Q1 in docs/questions.md" \
  || fail "the captured result did not yield the keyed answer"
ok "the live runner captures, applies, and announces a docstrap reading"

printf '# all fm-procevent-docstrap tests passed\n'
