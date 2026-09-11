#!/usr/bin/env bash
# docstrap adapter for the generic process-to-event runner: ask the captain's
# held decisions as questions in one of his own project documents, and read his
# answers back into the one keyed-answer intake.
#
# Usage:
#   fm-procevent-docstrap.sh export <document-path> <payload.json>
#   fm-procevent-docstrap.sh arm <document-path>
#   fm-procevent-docstrap.sh source <document-path>
#   fm-procevent-docstrap.sh source-id <document-path>
#   fm-procevent-docstrap.sh classify <result-file>
#   fm-procevent-docstrap.sh terminal <result-file>
#   fm-procevent-docstrap.sh answers <result-file>
#   fm-procevent-docstrap.sh autohandle <source-id> <sequence> <result-file>
#   fm-procevent-docstrap.sh read <result-file>
#   fm-procevent-docstrap.sh retire <document-path>
#
# TRAFFIC IS ONE-WAY, AND THAT IS THE WHOLE POINT. Firstmate WRITES a question
# document into one of the captain's project repositories and READS his answers
# out of that project's docstrap answer store. Nothing here asks docstrap to
# look at a firstmate home, and nothing here changes docstrap: the question
# document is found by docstrap's existing `Q<n>` rule, and the answers are read
# out of the file docstrap already writes.
#
# export     Render a question document at <document-path> from a composed
#            payload, and record the private label-to-task mapping the rest of
#            this adapter reads. The destination path is required and has no
#            default. The payload is composed by firstmate, exactly as the
#            bearings board's payload is: what to ask is judgement, and a script
#            that derived questions from hold reasons would emit prose failing
#            the captain's question rules on its first line. What a script CAN
#            check, it checks - see THE QUESTION RULES below.
# arm        Register the blocking answer listener for an exported document.
#            It REFUSES unless the source is already bound to the keyed-answer
#            intake, so a question can never be asked through a channel whose
#            answer would have nowhere to go.
# source     The registered listener `arm` publishes, not a command to run in a
#            conversational turn. It blocks until the answer store changes, then
#            prints one result and exits.
# classify   Print what a captured result is: answers, continuity-broken, or
#            malformed.
# terminal   Exit 0 when the captured result proves every exported question now
#            has an answer in the store, so the runner may retire the source.
# answers    This adapter's half of the generic keyed-answer contract in
#            bin/fm-procevent.sh. It prints `<task-id>\t<answer>\t<label>` and
#            stops there; what a keyed answer MEANS is owned once, by
#            bin/fm-captain-hold.sh's intake, which the runner feeds.
# autohandle The runner's own entry: advance this source's durable read position
#            and delivery ledger for a captured result, then acknowledge it.
#            Advancing a read position carries no judgement, so it belongs in
#            code rather than in an agent's memory.
# read       Present one already-captured result for a handler, without arming,
#            polling, or changing anything.
# retire     Retire the registration and drop this source's private records.
#
# THE KEY IS NEVER READ OUT OF THE DOCUMENT OR THE STORE.
# docstrap keys an answer on `<document-id>:<label>` - its own identifiers, for
# its own store. A captain-held task id appears in neither, and must not: a
# store is an ordinary file the captain can hand-edit, and a channel that read
# decision keys out of one would let edited prose name any task it liked. So
# `export` records the label-to-task mapping privately under `state/`, and
# `answers` resolves `Q<n>` through that private record alone. A label the
# export never wrote feeds nothing, and no prose anywhere can name a task.
#
# THE READ IS NON-DESTRUCTIVE, AND NOTHING IS CONSUMED TO PERFORM IT.
# `answers.md` is a file, so there is no source-side handoff window to argue
# about: `source` only ever reads it. Nothing is cleared, moved, or rewritten to
# discover an answer, and re-running `source` over an unchanged store produces
# the same reading. The durable read position advances in `autohandle`, AFTER
# the runner has captured the result, so a listener that dies between reading
# and capture loses nothing: the next listener reads the same answers again, and
# the keyed intake reports the replay as already closed.
#
# Do not describe this path as at-least-once, no-loss, or exactly-once. What is
# proved here is narrower and worth stating exactly: the store is read without
# being modified, a delivered answer is recorded only after its result was
# durably captured, and a replay of the same answer is idempotent at the intake.
# A key the intake skips - a task nobody holds, or one already closed - is
# reported there and not retried, because re-delivering would not change it.
#
# A RE-EXPORT THAT CHANGES THE MAPPING RE-BASELINES THE READ POSITION.
# `Q<n>` is a position, not an identity: narrowing a question set renumbers it,
# so an answer written before a re-export is an answer to whatever used to sit
# at that label. Every export whose label-to-task mapping differs from the one
# it replaces therefore treats what the store already holds as delivered and
# reads forward from there, and an export that changes nothing leaves the read
# position alone. See baseline_read_state.
#
# REPLACEMENT AND TRUNCATION ARE DETECTED, NOT REBASED ON.
# docstrap rewrites the whole answer file on every write, so a byte offset is
# not the continuity fact here; what a rewrite must preserve is identity and
# accumulation. A read therefore breaks continuity, delivers nothing, and says
# so when the store stops parsing as an answer file, when its declared project
# changes, when the document's docstrap identity changes under a stable display
# path, or when a key this source has already observed is absent. Each of those
# means the file was replaced or cut back rather than superseded, and silently
# rebasing on it would deliver a `Q3` answer belonging to a different question.
#
# THE QUESTION RULES ARE ENFORCED WHERE A SCRIPT CAN SEE THEM.
# The captain's question rules are his, and most of them need judgement: which
# questions are worth his time, and what order makes later ones moot. Three do
# not, and `export` refuses rather than trusting memory for them - a question
# whose text is not one interrogative sentence, one that joins two askable
# things with "and", and one that offers "A or B" instead of asking about A. It
# also refuses any supplied string that opens with a question label, because
# such a string would mint a question nothing exported and nothing can answer.
#
# CONTEXT REFERENCES ARE OPT-IN, OFF BY DEFAULT, AND PROVENANCE-TESTED.
# With `config/docstrap-references` absent, every reference in the payload is
# dropped and named on stderr. With it present, a reference survives only when
# it passes both halves of a test that cannot manufacture one:
#   - the path resolves to a markdown file inside the same project the question
#     document is written into, so a reference is never born broken; and
#   - the held task's own durable record names that exact path, so the reference
#     is the decision's recorded provenance rather than a resemblance.
# There is no scoring, no keyword overlap, and no similarity judgement anywhere
# in this path. A reference firstmate cannot point at a citation for does not
# appear, because a reference that turns out to be irrelevant costs the captain
# a click and teaches him to stop opening them.
#
# A REFERENCE IS A FILE REFERENCE, NEVER A LINK.
# Firstmate names WHICH document is relevant and stops. It does not own the
# site's URL structure, so it emits no anchor and no href: an `fm-ref:` line
# names the label it belongs to and a project-relative path, and turning that
# into a link - and opening it beside the question - belongs to docstrap's build
# and its existing reference pane. Nothing consumes these lines today; that is
# expected. The reference points by PATH rather than by docstrap's rename-proof
# document id because firstmate cannot know that id: it is minted lazily when a
# document is first answered, and looking one up would mean reaching into
# docstrap's own metadata store. The cost is real - a path rots on rename - and
# is bounded here by verifying every path at export time, so a reference is
# never born broken and a later rename leaves a reference that visibly fails to
# resolve rather than one that silently points somewhere wrong. The `path=`
# spelling leaves room for an `id=` beside it whenever the build side is ready
# to supply one, without breaking the line's grammar. That choice is open to
# revision: it is what firstmate can emit today, not a claim that a path is the
# better anchor.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
DATA="${FM_DATA_OVERRIDE:-$FM_HOME/data}"
CONFIG="${FM_CONFIG_OVERRIDE:-$FM_HOME/config}"

MAP_DIR="$STATE/docstrap-questions"
CURSOR_DIR="$STATE/docstrap-answers"
REFERENCE_FLAG="$CONFIG/docstrap-references"
STORE_BASENAME=answers.md
PROMDANCE_DIRNAME=promdance

# The listener's own window. It closes with no output rather than blocking
# forever, so a retired source stops cleanly and the runner's reconcile cycle
# owns restarting a live one.
WAIT_SECONDS=${FM_DOCSTRAP_WAIT_SECONDS:-240}
POLL_SECONDS=${FM_DOCSTRAP_POLL_SECONDS:-5}
WINDOW_CLOSED_EMPTY=75

# An answer is one tab-separated field at the keyed intake, which accepts a
# decision of at most 8192 bytes. A longer answer is delivered cut at this bound
# with an explicit marker naming the store, so the captain's full words stay
# findable rather than silently vanishing or being rejected whole.
MAX_ANSWER_BYTES=4096
MAX_QUESTIONS=100

TAB=$'\t'

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
usage() { sed -n '2,/^set -u$/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 2; }

case "${1-}" in ''|-h|--help|help) usage ;; esac

sha256_stdin() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    die "no SHA-256 tool is available"
  fi
}

sha256_file() { sha256_stdin < "$1"; }
sha256_text() { printf '%s' "$1" | sha256_stdin; }

realpath_of() {
  perl -MCwd=realpath -e '$p = realpath($ARGV[0]); defined($p) or exit 1; print "$p\n"' "$1" 2>/dev/null
}

validate_source_id() {
  case "$1" in docstrap-?*) ;; *) return 1 ;; esac
  case "${1#docstrap-}" in *[!0-9a-f]*) return 1 ;; esac
  return 0
}

# Canonical identity is the document's physical path, the same rule the Lavish
# adapter uses for an artifact: two names for one document are one source and
# must never become two owners of the same questions.
cmd_source_id() {
  local doc=${1-} real
  [ -n "$doc" ] || usage
  [ "$#" -eq 1 ] || usage
  case "$doc" in *$'\n'*) die "document paths cannot contain newlines" ;; esac
  real=$(realpath_of "$doc") || die "cannot resolve the document path: $doc"
  [ -f "$real" ] || die "document does not exist: $doc"
  printf 'docstrap-%s\n' "$(printf '%s' "$real" | sha256_stdin | cut -c1-16)"
}

map_path() { printf '%s/%s.map\n' "$MAP_DIR" "$1"; }
cursor_path() { printf '%s/%s.cursor\n' "$CURSOR_DIR" "$1"; }
ledger_path() { printf '%s/%s.delivered\n' "$CURSOR_DIR" "$1"; }

private_dir() {  # <dir>
  (umask 077; mkdir -p "$1") || return 1
  [ -d "$1" ] && [ ! -L "$1" ] || return 1
  chmod 700 "$1" 2>/dev/null || true
}

# Read one `field=value` header. The scan stops at the first blank line, so a
# captured result's payload - which carries the captain's own prose - can never
# forge a header this adapter reads.
read_record_field() {  # <file> <field>
  LC_ALL=C awk -v prefix="$2=" '
    $0 == "" { exit }
    index($0, prefix) == 1 { value = substr($0, length(prefix) + 1); found++ }
    END { if (found != 1) exit 1; print value }
  ' "$1"
}

MAP_FILE=''
MAP_DOCUMENT=''
MAP_STORE=''
MAP_COUNT=0

load_map() {  # <source-id>; fatal when the export record is missing
  local sid=$1
  MAP_FILE=$(map_path "$sid")
  [ -f "$MAP_FILE" ] && [ ! -L "$MAP_FILE" ] \
    || die "no exported question record for $sid; run export first"
  [ "$(read_record_field "$MAP_FILE" schema)" = fm-docstrap-map.v1 ] \
    || die "question record has an incompatible schema: $MAP_FILE"
  MAP_DOCUMENT=$(read_record_field "$MAP_FILE" document) \
    || die "question record names no document: $MAP_FILE"
  MAP_STORE=$(read_record_field "$MAP_FILE" store) \
    || die "question record names no answer store: $MAP_FILE"
  MAP_COUNT=$(read_record_field "$MAP_FILE" count) \
    || die "question record carries no question count: $MAP_FILE"
  case "$MAP_COUNT" in ''|*[!0-9]*) die "question record carries an invalid count: $MAP_FILE" ;; esac
}

map_labels() { awk -F'\t' '/^q=/ { sub(/^q=/, "", $1); print $1 }' "$MAP_FILE"; }

map_task_for() {  # <label>
  awk -F'\t' -v want="q=$1" '$1 == want { print $2; exit }' "$MAP_FILE"
}

# --- the project and its answer store ---------------------------------------

# Walk up for the nearest ancestor carrying a `promdance` entry. That entry is
# the project's own link into its promdance storage, so the nearest one names
# the project that owns this document - the same "deepest project wins" rule
# docstrap's own scope resolution applies.
resolve_project_root() {  # <absolute document path>
  local dir
  dir=$(dirname -- "$1")
  while :; do
    if [ -e "$dir/$PROMDANCE_DIRNAME" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    case "$dir" in /|.) return 1 ;; esac
    dir=$(dirname -- "$dir")
  done
}

# --- store reading ----------------------------------------------------------

# Read one project answer store and report only what concerns one document.
# Prints `project`, `rows`, `unreadable`, and one tab-separated `answer` record
# per matching row, with the answer text collapsed to a single line. It reads
# only the two fields it needs out of each flow-style index row rather than
# pretending to be a YAML parser, and it reproduces docstrap's own body-section
# rule exactly: a `## <key>` heading opens a section only when the key is two
# colon-separated runs with no whitespace, so an ordinary heading written inside
# an answer stays part of that answer.
#
# Exit 1 when the store cannot be opened and 2 when it does not parse as an
# answer file at all; the caller turns either into a continuity break rather
# than reading past it.
store_scan() {  # <store> <document display path> <max answer bytes>
  perl -e '
    use strict; use warnings;
    no warnings "utf8";
    my ($path, $want_document, $max) = @ARGV;
    my $SQ = chr(39);
    # Read as characters, not bytes: docstrap writes the body section heading
    # with an em dash, and a byte-wise read cannot recognize it. Malformed bytes
    # become the replacement character rather than a warning, because an
    # unreadable byte in one answer must not break the reading of the store.
    open my $fh, "<:encoding(UTF-8)", $path or exit 1;
    my @lines = <$fh>;
    close $fh;
    chomp @lines;

    exit 2 unless @lines && $lines[0] eq "---";
    my $close = -1;
    for my $i (1 .. $#lines) {
      if ($lines[$i] eq "---" || $lines[$i] eq "...") { $close = $i; last }
    }
    exit 2 if $close < 0;

    sub unquote {
      my ($raw, $sq) = @_;
      $raw =~ s/\A\s+//; $raw =~ s/\s+\z//;
      if ($raw =~ /\A"((?:[^"\\]|\\.)*)"\z/) {
        my $v = $1;
        $v =~ s/\\(.)/$1 eq "n" ? "\n" : $1 eq "t" ? "\t" : $1/ge;
        return $v;
      }
      if ($raw =~ /\A$sq((?:[^$sq]|$sq$sq)*)$sq\z/) {
        my $v = $1; $v =~ s/$sq$sq/$sq/g; return $v;
      }
      return $raw;
    }

    # One flow mapping, read for the named field only.
    sub flow_field {
      my ($body, $field, $sq) = @_;
      my $rest = $body;
      while (length $rest) {
        $rest =~ s/\A[\s,]+//;
        last unless $rest =~ s/\A([A-Za-z0-9_]+)\s*:\s*//;
        my $name = $1;
        my $value;
        if ($rest =~ s/\A("(?:[^"\\]|\\.)*")//) { $value = unquote($1, $sq) }
        elsif ($rest =~ s/\A($sq(?:[^$sq]|$sq$sq)*$sq)//) { $value = unquote($1, $sq) }
        else { $rest =~ s/\A([^,}]*)//; $value = unquote($1, $sq) }
        return $value if $name eq $field;
      }
      return undef;
    }

    my $project = "";
    my ($in_strapdance, $in_answers, $unreadable) = (0, 0, 0);
    my @rows;
    for my $n (1 .. $close - 1) {
      my $line = $lines[$n];
      if ($line =~ /\A\S/) {
        $in_strapdance = ($line =~ /\Astrapdance:\s*\z/) ? 1 : 0;
        $in_answers = ($line =~ /\Aanswers:\s*\z/) ? 1 : 0;
        next;
      }
      if ($in_strapdance && $line =~ /\A\s+project:\s*(.*)\z/) {
        $project = unquote($1, $SQ);
        next;
      }
      if ($in_answers && $line =~ /\A\s*-\s*\{(.*)\}\s*\z/) {
        my $body = $1;
        my $key = flow_field($body, "key", $SQ);
        my $document = flow_field($body, "document", $SQ);
        if (!defined $key || $key !~ /\A[^\s:]+:[^\s:]+\z/) { $unreadable++; next }
        push @rows, { key => $key, document => defined $document ? $document : "" };
        next;
      }
    }

    my (%section, $current);
    for my $n ($close + 1 .. $#lines) {
      my $line = $lines[$n];
      if ($line =~ /\A##[ \t]+([^\s:]+:[^\s:]+)[ \t]*(?:\x{2014}.*)?\z/) {
        $current = $1;
        $section{$current} = [] unless exists $section{$current};
        next;
      }
      push @{ $section{$current} }, $line if defined $current;
    }

    binmode STDOUT, ":encoding(UTF-8)";
    print "project\t$project\n";
    print "rows\t", scalar(@rows), "\n";
    print "unreadable\t$unreadable\n";
    for my $row (@rows) {
      next unless $row->{document} eq $want_document;
      my ($doc_id, $label) = split /:/, $row->{key}, 2;
      my $text = exists $section{ $row->{key} } ? join("\n", @{ $section{ $row->{key} } }) : "";
      $text =~ s/[\x00-\x1f\x7f]/ /g;
      $text =~ s/\s+/ /g;
      $text =~ s/\A\s+//; $text =~ s/\s+\z//;
      next unless length $text;
      # Bound the delivered answer in BYTES, because the keyed intake bounds the
      # decision it records in bytes. The cut lands on a character boundary, so
      # a multi-byte answer is never delivered half a character short.
      my $encoded = $text;
      utf8::encode($encoded);
      if (length($encoded) > $max) {
        $text = substr($text, 0, $max);
        while (1) {
          my $probe = $text;
          utf8::encode($probe);
          last if length($probe) <= $max;
          substr($text, -1, 1, "");
        }
        $text .= " [answer continues in the project answer store]";
      }
      print "answer\t$row->{key}\t$doc_id\t$label\t$text\n";
    }
  ' "$1" "$2" "$3"
}

# --- cursor and delivery ledger ---------------------------------------------

CURSOR_PRESENT=0
CURSOR_PROJECT=''
CURSOR_DOC_ID=''
CURSOR_DIGEST=''
CURSOR_KEYS_FILE=''

read_cursor() {  # <source-id> <keys-destination>
  local path=$1 dest=$2
  path=$(cursor_path "$path")
  CURSOR_PRESENT=0
  CURSOR_PROJECT=''
  CURSOR_DOC_ID=''
  CURSOR_DIGEST=''
  CURSOR_KEYS_FILE=$dest
  : > "$dest"
  [ -e "$path" ] || return 0
  [ -f "$path" ] && [ ! -L "$path" ] || die "answer cursor is unsafe: $path"
  [ "$(read_record_field "$path" schema)" = fm-docstrap-cursor.v1 ] \
    || die "answer cursor has an incompatible schema: $path"
  CURSOR_PRESENT=1
  CURSOR_PROJECT=$(read_record_field "$path" project || true)
  CURSOR_DOC_ID=$(read_record_field "$path" doc_id || true)
  CURSOR_DIGEST=$(read_record_field "$path" store_sha256 || true)
  sed -n 's/^key=//p' "$path" > "$dest"
}

write_cursor() {  # <source-id> <project> <doc-id> <digest> <keys-file>
  local sid=$1 project=$2 doc_id=$3 digest=$4 keys=$5 path tmp
  private_dir "$CURSOR_DIR" || return 1
  path=$(cursor_path "$sid")
  [ ! -L "$path" ] || return 1
  tmp=$(umask 077; mktemp "$CURSOR_DIR/.cursor.XXXXXX") || return 1
  {
    printf 'schema=fm-docstrap-cursor.v1\n'
    printf 'project=%s\n' "$project"
    printf 'doc_id=%s\n' "$doc_id"
    printf 'store_sha256=%s\n' "$digest"
    LC_ALL=C sort -u "$keys" | grep -v '^$' | sed 's/^/key=/' || true
  } > "$tmp" || { rm -f -- "$tmp"; return 1; }
  chmod 600 "$tmp" || { rm -f -- "$tmp"; return 1; }
  mv -f -- "$tmp" "$path"
}

read_ledger() {  # <source-id> <destination>
  local path
  path=$(ledger_path "$1")
  : > "$2"
  [ -e "$path" ] || return 0
  [ -f "$path" ] && [ ! -L "$path" ] || die "delivery ledger is unsafe: $path"
  cat -- "$path" > "$2"
}

# --- the listener -----------------------------------------------------------

emit_result() {  # <sid> <status> <project> <doc-id> <digest> <answered> <new> <reason> <payload-file>
  local sid=$1 status=$2 project=$3 doc_id=$4 digest=$5 answered=$6 new=$7 reason=$8 payload=$9
  local bytes payload_digest remaining
  bytes=$(LC_ALL=C wc -c < "$payload" | tr -d ' ')
  payload_digest=$(sha256_file "$payload")
  remaining=$((MAP_COUNT - answered))
  [ "$remaining" -ge 0 ] || remaining=0
  printf 'schema=fm-docstrap-answers.v1\n'
  printf 'status=%s\n' "$status"
  printf 'source_id=%s\n' "$sid"
  printf 'document=%s\n' "$MAP_DOCUMENT"
  printf 'store=%s\n' "$MAP_STORE"
  printf 'project=%s\n' "$project"
  printf 'doc_id=%s\n' "$doc_id"
  printf 'store_sha256=%s\n' "$digest"
  printf 'exported=%s\n' "$MAP_COUNT"
  printf 'answered=%s\n' "$answered"
  printf 'delivered=%s\n' "$new"
  printf 'remaining=%s\n' "$remaining"
  printf 'reason=%s\n' "$reason"
  printf 'payload_bytes=%s\n' "$bytes"
  printf 'payload_sha256=%s\n' "$payload_digest"
  printf '\n'
  [ "$bytes" -eq 0 ] || cat -- "$payload"
}

# Compare one reading of the store against the recorded position and print the
# result the runner captures. Returns 0 when a result was printed and 1 when the
# store holds nothing new for this document.
evaluate_store() {  # <source-id> <scan-file> <digest> <work-dir>
  local sid=$1 scan=$2 digest=$3 work=$4
  local project doc_id='' break_reason='' answered=0 new=0
  local kind key doc label text answer_digest
  project=$(awk -F'\t' '$1 == "project" { print $2; exit }' "$scan")

  awk -F'\t' '$1 == "answer"' "$scan" > "$work/answers"
  awk -F'\t' '$1 == "answer" { print $2 }' "$scan" > "$work/keys"
  map_labels > "$work/labels"

  while IFS="$TAB" read -r kind key doc label text; do
    [ "$kind" = answer ] || continue
    answered=$((answered + 1))
    if [ -z "$doc_id" ]; then
      doc_id=$doc
    elif [ "$doc_id" != "$doc" ]; then
      break_reason="the store holds two document identities for $MAP_DOCUMENT"
    fi
  done < "$work/answers"

  if [ -z "$break_reason" ] && [ "$CURSOR_PRESENT" -eq 1 ]; then
    if [ -n "$CURSOR_PROJECT" ] && [ "$CURSOR_PROJECT" != "$project" ]; then
      break_reason="the answer store now declares project '$project', not '$CURSOR_PROJECT'"
    elif [ -n "$CURSOR_DOC_ID" ] && [ -n "$doc_id" ] && [ "$CURSOR_DOC_ID" != "$doc_id" ]; then
      break_reason="the document's docstrap identity changed from $CURSOR_DOC_ID to $doc_id"
    else
      while IFS= read -r key; do
        [ -n "$key" ] || continue
        grep -Fqx -- "$key" "$work/keys" && continue
        break_reason="an answer this source already read is gone from the store ($key)"
        break
      done < "$CURSOR_KEYS_FILE"
    fi
  fi

  if [ -n "$break_reason" ]; then
    : > "$work/payload"
    emit_result "$sid" continuity-broken "$project" "$doc_id" "$digest" \
      "$answered" 0 "$break_reason" "$work/payload"
    return 0
  fi

  read_ledger "$sid" "$work/ledger"
  : > "$work/payload"
  while IFS="$TAB" read -r kind key doc label text; do
    [ "$kind" = answer ] || continue
    grep -Fqx -- "$label" "$work/labels" || continue
    answer_digest=$(sha256_text "$text")
    grep -Fqx -- "$label$TAB$answer_digest" "$work/ledger" && continue
    printf 'answer\t%s\t%s\t%s\t%s\n' "$label" "$key" "$answer_digest" "$text" >> "$work/payload"
    new=$((new + 1))
  done < "$work/answers"

  [ "$new" -gt 0 ] || return 1
  emit_result "$sid" answers "$project" "$doc_id" "$digest" "$answered" "$new" '' "$work/payload"
  return 0
}

cmd_source() {
  local doc=${1-} sid deadline digest work rc
  [ -n "$doc" ] || usage
  [ "$#" -eq 1 ] || usage
  case "$WAIT_SECONDS" in ''|*[!0-9]*) die "FM_DOCSTRAP_WAIT_SECONDS must be whole seconds" ;; esac
  case "$POLL_SECONDS" in ''|*[!0-9]*) die "FM_DOCSTRAP_POLL_SECONDS must be whole seconds" ;; esac
  [ "$POLL_SECONDS" -ge 1 ] || die "FM_DOCSTRAP_POLL_SECONDS must be at least one second"
  sid=$(cmd_source_id "$doc") || exit 1
  load_map "$sid"

  work=$(mktemp -d "${TMPDIR:-/tmp}/fm-docstrap-source.XXXXXX") || die "cannot stage the store reading"
  # shellcheck disable=SC2064  # $work must expand now, while the staged path is set.
  trap "rm -rf -- '$work'" EXIT
  read_cursor "$sid" "$work/cursor-keys"

  deadline=$(( $(date +%s) + WAIT_SECONDS ))
  while :; do
    if [ -f "$MAP_STORE" ] && [ ! -L "$MAP_STORE" ]; then
      digest=$(sha256_file "$MAP_STORE")
      if [ "$digest" != "$CURSOR_DIGEST" ]; then
        rc=0
        store_scan "$MAP_STORE" "$MAP_DOCUMENT" "$MAX_ANSWER_BYTES" > "$work/scan" || rc=$?
        if [ "$rc" -ne 0 ]; then
          : > "$work/empty"
          emit_result "$sid" continuity-broken "$CURSOR_PROJECT" "$CURSOR_DOC_ID" "$digest" 0 0 \
            "the answer store no longer parses as a docstrap answer file" "$work/empty"
          return 0
        fi
        if evaluate_store "$sid" "$work/scan" "$digest" "$work"; then
          return 0
        fi
        # The store changed for some other document. Remember the new digest so
        # the same unrelated write is not re-read every pass, and leave the
        # observed-key set alone: only a delivery advances that.
        CURSOR_DIGEST=$digest
      fi
    elif [ "$CURSOR_PRESENT" -eq 1 ] && [ -n "$CURSOR_DIGEST" ]; then
      : > "$work/empty"
      emit_result "$sid" continuity-broken "$CURSOR_PROJECT" "$CURSOR_DOC_ID" '' 0 0 \
        "the answer store this source had already read is gone: $MAP_STORE" "$work/empty"
      return 0
    fi
    [ "$(date +%s)" -lt "$deadline" ] || break
    sleep "$POLL_SECONDS"
  done
  return "$WINDOW_CLOSED_EMPTY"
}

# --- captured-result commands -----------------------------------------------

result_payload() {  # <result-file>
  LC_ALL=C awk 'body { print; next } $0 == "" { body = 1 }' "$1"
}

classify_result() {  # <result-file>
  local file=$1 schema status
  [ -f "$file" ] && [ ! -L "$file" ] || { printf 'malformed\n'; return 0; }
  schema=$(read_record_field "$file" schema 2>/dev/null || true)
  status=$(read_record_field "$file" status 2>/dev/null || true)
  [ "$schema" = fm-docstrap-answers.v1 ] || { printf 'malformed\n'; return 0; }
  case "$status" in
    answers|continuity-broken) printf '%s\n' "$status" ;;
    *) printf 'malformed\n' ;;
  esac
}

cmd_classify() {
  [ "$#" -eq 1 ] && [ -n "${1-}" ] || usage
  classify_result "$1"
}

# A source ends when every exported question has an answer in the store. That is
# a fact the result states rather than a guess, and it is the only end this
# channel has: until then the captain may still answer, and after it there is
# nothing left to ask. Exporting again arms a fresh source.
cmd_terminal() {
  local file=${1-} remaining
  [ "$#" -eq 1 ] && [ -n "$file" ] || usage
  [ "$(classify_result "$file")" = answers ] || return 1
  remaining=$(read_record_field "$file" remaining 2>/dev/null || true)
  case "$remaining" in ''|*[!0-9]*) return 1 ;; esac
  [ "$remaining" -eq 0 ]
}

# The keyed-answer half. Every key printed here comes from this home's own
# private export record; the store supplies only a label and the captain's
# prose. A label the export never wrote, and any payload line that is not a
# well-formed answer record, print nothing.
cmd_answers() {
  local file=${1-} sid document kind label key digest text task
  [ "$#" -eq 1 ] && [ -n "$file" ] || usage
  [ -f "$file" ] && [ ! -L "$file" ] || die "result file does not exist: $file"
  [ "$(classify_result "$file")" = answers ] || return 0
  sid=$(read_record_field "$file" source_id) || return 0
  validate_source_id "$sid" || return 0
  MAP_FILE=$(map_path "$sid")
  [ -f "$MAP_FILE" ] && [ ! -L "$MAP_FILE" ] || return 0
  document=$(read_record_field "$MAP_FILE" document 2>/dev/null || true)
  [ -n "$document" ] || document='the exported question document'
  while IFS="$TAB" read -r kind label key digest text; do
    [ "$kind" = answer ] || continue
    case "$label" in ''|*[!A-Za-z0-9]*) continue ;; esac
    [ -n "$text" ] || continue
    task=$(map_task_for "$label")
    [ -n "$task" ] || continue
    case "$task" in *[!A-Za-z0-9._-]*) continue ;; esac
    printf '%s\t%s\t%s\n' "$task" "$text" "$label in $document"
  done < <(result_payload "$file")
}

cmd_read() {
  local file=${1-} status count=0 kind label key digest text
  [ "$#" -eq 1 ] && [ -n "$file" ] || usage
  [ -f "$file" ] && [ ! -L "$file" ] || die "result file does not exist: $file"
  status=$(classify_result "$file")
  printf 'status: %s\n' "$status"
  if [ "$status" = malformed ]; then
    printf 'The captured result is not a readable docstrap answer reading.\n'
    return 0
  fi
  printf 'document: %s\n' "$(read_record_field "$file" document || true)"
  printf 'store: %s\n' "$(read_record_field "$file" store || true)"
  printf 'project: %s\n' "$(read_record_field "$file" project || true)"
  printf 'exported_questions: %s\n' "$(read_record_field "$file" exported || true)"
  printf 'answered_questions: %s\n' "$(read_record_field "$file" answered || true)"
  printf 'unanswered_questions: %s\n' "$(read_record_field "$file" remaining || true)"
  printf 'new_answers: %s\n' "$(read_record_field "$file" delivered || true)"
  if [ "$status" = continuity-broken ]; then
    printf 'reason: %s\n' "$(read_record_field "$file" reason || true)"
    printf 'No answer was delivered from this reading.\n'
    return 0
  fi
  printf '\n'
  while IFS="$TAB" read -r kind label key digest text; do
    [ "$kind" = answer ] || continue
    count=$((count + 1))
    printf 'ANSWER %s\n' "$label"
    printf 'store_key: %s\n' "$key"
    printf '| %s\n' "$text"
  done < <(result_payload "$file")
  [ "$count" -gt 0 ] || printf 'ANSWERS: (none)\n'
  printf 'END DOCSTRAP RESULT (%s)\n' "$count"
}

# Advance this source's durable read position for a captured result, then
# acknowledge the capture. Applying a read position carries no judgement, which
# is why it runs here instead of waiting on an agent to remember it.
cmd_autohandle() {
  local sid=${1-} seq=${2-} file=${3-} status project doc_id digest work
  local kind label key answer_digest text
  [ "$#" -eq 3 ] && [ -n "$sid" ] && [ -n "$seq" ] && [ -n "$file" ] || usage
  validate_source_id "$sid" || die "not a docstrap source id: $sid"
  case "$seq" in ''|*[!0-9]*) die "sequence must be a nonnegative integer" ;; esac
  [ -f "$file" ] && [ ! -L "$file" ] || die "result file does not exist: $file"
  status=$(classify_result "$file")
  [ "$status" != malformed ] || return 1
  [ "$(read_record_field "$file" source_id)" = "$sid" ] || return 1
  load_map "$sid"

  if [ "$status" = answers ]; then
    work=$(mktemp -d "${TMPDIR:-/tmp}/fm-docstrap-apply.XXXXXX") || return 1
    read_cursor "$sid" "$work/keys"
    read_ledger "$sid" "$work/ledger"
    project=$(read_record_field "$file" project || true)
    doc_id=$(read_record_field "$file" doc_id || true)
    digest=$(read_record_field "$file" store_sha256 || true)
    while IFS="$TAB" read -r kind label key answer_digest text; do
      [ "$kind" = answer ] || continue
      printf '%s\n' "$key" >> "$work/keys"
      printf '%s\t%s\n' "$label" "$answer_digest" >> "$work/ledger"
    done < <(result_payload "$file")
    private_dir "$CURSOR_DIR" || { rm -rf -- "$work"; return 1; }
    write_cursor "$sid" "$project" "$doc_id" "$digest" "$work/keys" \
      || { rm -rf -- "$work"; return 1; }
    LC_ALL=C sort -u "$work/ledger" | grep -v "^$" > "$work/ledger.final" || true
    ( umask 077; cp -- "$work/ledger.final" "$(ledger_path "$sid")" ) \
      || { rm -rf -- "$work"; return 1; }
    chmod 600 "$(ledger_path "$sid")" 2>/dev/null || true
    rm -rf -- "$work"
  fi

  "$SCRIPT_DIR/fm-procevent.sh" handled "$sid" "$seq" >/dev/null || return 1
}

# --- arming and retirement --------------------------------------------------

cmd_arm() {
  local doc=${1-} sid real
  [ "$#" -eq 1 ] && [ -n "$doc" ] || usage
  sid=$(cmd_source_id "$doc") || exit 1
  real=$(realpath_of "$doc") || die "cannot resolve the document path: $doc"
  load_map "$sid"
  # The captain's ordering rule, enforced rather than documented: a bound source
  # is the only thing that carries an answer to the keyed intake, so arming an
  # unbound one would ask a question whose answer has nowhere to go.
  "$SCRIPT_DIR/fm-captain-hold.sh" binding "$sid" >/dev/null 2>&1 \
    || die "bind this source to the keyed-answer intake first: bin/fm-captain-hold.sh bind $sid"
  "$SCRIPT_DIR/fm-procevent.sh" register docstrap "$sid" \
    -- "$SCRIPT_DIR/fm-procevent-docstrap.sh" source "$real" || exit 1
  printf 'armed: %s\n' "$sid"
  printf 'document: %s\n' "$real"
  printf 'store: %s\n' "$MAP_STORE"
}

cmd_retire() {
  local doc=${1-} sid
  [ "$#" -eq 1 ] && [ -n "$doc" ] || usage
  sid=$(cmd_source_id "$doc") || exit 1
  "$SCRIPT_DIR/fm-procevent.sh" retire "$sid" || exit 1
  rm -f -- "$(cursor_path "$sid")" "$(ledger_path "$sid")" "$(map_path "$sid")"
  printf 'retired: %s\n' "$sid"
}

# --- export -----------------------------------------------------------------

# Validate and normalize one composed payload. Every text field arrives as a
# single collapsed line, so the document's line structure is this script's alone
# and no supplied string can invent one.
plan_payload() {  # <payload.json> <max questions>
  perl -MJSON::PP -e '
    use strict; use warnings;
    my ($path, $max) = @ARGV;
    open my $fh, "<", $path or do { print STDERR "error: cannot read the payload: $path\n"; exit 1 };
    local $/; my $raw = <$fh>; close $fh;
    my $data = eval { decode_json($raw) };
    if (!$data || ref($data) ne "HASH") { print STDERR "error: the payload is not a JSON object\n"; exit 1 }

    my @problems;
    sub bad { push @problems, $_[0]; return undef }

    # A label shape at the start of a line is how docstrap finds a question, so
    # no supplied string may carry one: an option or a context paragraph opening
    # with `Q2.` would mint a question nothing exported and nothing can answer.
    sub forges_label {
      my ($text) = @_;
      return $text =~ /\A[ \t]{0,3}(?:(?:[-*+]|\d+[.)])[ \t]+)?(?:\[[ xX]\][ \t]+)?(?:\*\*|__)?Q\d+[*_]*[.:)]/;
    }

    sub clean {
      my ($value, $what, $limit) = @_;
      return bad("$what must be a string") if !defined $value || ref $value;
      return bad("$what contains a control character")
        if $value =~ /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/;
      $value =~ s/\s+/ /g; $value =~ s/\A\s+//; $value =~ s/\s+\z//;
      return bad("$what is empty") unless length $value;
      return bad("$what is longer than $limit characters") if length($value) > $limit;
      return bad("$what opens with a question label, which would mint a question nothing exported")
        if forges_label($value);
      return $value;
    }

    my $schema = $data->{schema};
    if (!defined $schema || ref $schema || $schema ne "fm-docstrap-questions.v1") {
      print STDERR "error: payload schema must be fm-docstrap-questions.v1\n";
      exit 1;
    }
    my $title = clean($data->{title}, "title", 200);
    my $intro;
    if (defined $data->{intro} && $data->{intro} ne "") {
      $intro = clean($data->{intro}, "intro", 2000);
    }
    my $questions = $data->{questions};
    if (ref($questions) ne "ARRAY" || !@$questions) {
      print STDERR "error: the payload needs a non-empty questions array\n";
      exit 1;
    }
    if (@$questions > $max) {
      print STDERR "error: the payload carries more than $max questions\n";
      exit 1;
    }

    my (@plan, %seen_task);
    my $n = 0;
    for my $item (@$questions) {
      $n++;
      my $label = "Q$n";
      if (ref($item) ne "HASH") { push @problems, "$label is not an object"; next }
      my $task = $item->{task};
      if (!defined $task || ref $task || $task !~ /\A[A-Za-z0-9._-]{1,128}\z/) {
        push @problems, "$label names no captain-held task id"; next;
      }
      if ($seen_task{$task}++) { push @problems, "$label repeats task $task"; next }

      my $question = clean($item->{question}, "$label question", 300);
      if (defined $question) {
        push @problems, "$label is not an interrogative sentence; it must end with a question mark"
          unless $question =~ /\?\z/;
        my $marks = () = $question =~ /\?/g;
        push @problems, "$label carries $marks question marks; a question is one interrogative sentence"
          if $marks > 1;
        push @problems, "$label joins two askable things with \"and\"; split it into separate questions"
          if $question =~ /\band\b/i;
        push @problems, "$label offers a choice with \"or\"; ask whether it is the first, and make the second its own question"
          if $question =~ /\bor\b/i;
        push @problems, "$label is too short to be a question" if length($question) < 10;
      }

      my $context;
      if (defined $item->{context} && $item->{context} ne "") {
        $context = clean($item->{context}, "$label context", 1200);
      }

      my @options;
      if (defined $item->{options}) {
        if (ref($item->{options}) ne "ARRAY") { push @problems, "$label options must be an array" }
        elsif (@{$item->{options}} < 2 || @{$item->{options}} > 10) {
          push @problems, "$label must offer between two and ten options, or none";
        } else {
          my $oi = 0;
          for my $option (@{$item->{options}}) {
            $oi++;
            my $text = clean($option, "$label option $oi", 120);
            next unless defined $text;
            push @problems, "$label option $oi is itself a question" if $text =~ /\?/;
            push @options, $text;
          }
        }
      }

      my @refs;
      if (defined $item->{references}) {
        if (ref($item->{references}) ne "ARRAY") { push @problems, "$label references must be an array" }
        elsif (@{$item->{references}} > 5) { push @problems, "$label carries more than five references" }
        else {
          for my $ref (@{$item->{references}}) {
            if (!defined $ref || ref $ref) { push @problems, "$label has a non-string reference"; next }
            if ($ref !~ m{\A[A-Za-z0-9._][A-Za-z0-9._/-]*\.md\z}
                || $ref =~ m{(?:\A|/)\.\.(?:/|\z)} || $ref =~ m{//}) {
              push @problems, "$label reference is not a plain project-relative markdown path: $ref";
              next;
            }
            push @refs, $ref;
          }
        }
      }

      push @plan, { label => $label, task => $task, question => $question,
                    context => $context, options => \@options, refs => \@refs };
    }

    if (@problems) {
      print STDERR "error: $_\n" for @problems;
      exit 1;
    }

    binmode STDOUT, ":encoding(UTF-8)";
    print "doc\ttitle\t$title\n";
    print "doc\tintro\t$intro\n" if defined $intro;
    for my $q (@plan) {
      print "q\t$q->{label}\ttask\t$q->{task}\n";
      print "q\t$q->{label}\tquestion\t$q->{question}\n";
      print "q\t$q->{label}\tcontext\t$q->{context}\n" if defined $q->{context};
      print "q\t$q->{label}\toption\t$_\n" for @{$q->{options}};
      print "q\t$q->{label}\tref\t$_\n" for @{$q->{refs}};
    }
  ' "$1" "$2"
}

references_enabled() { [ -e "$REFERENCE_FLAG" ]; }

# Treat everything the store holds for this document right now as already
# delivered, and start reading from here.
#
# An export that CHANGES the mapping must do this, and getting it wrong is how a
# captain's words end up recorded against the wrong task. Narrowing a question
# set renumbers it - answer Q1 and Q2, re-export the rest, and the old Q3 is the
# new Q1 - so an answer written before that renumbering is an answer to a
# question that no longer exists at that label. Without re-baselining, the next
# reading would hand it to whatever task now sits at Q1 and close that captain
# call with someone else's words. The same reasoning covers a first export into
# a project whose store already carries answers under this document's path.
#
# An export that leaves the mapping untouched changes nothing here, so
# re-exporting the same questions stays idempotent and loses no pending answer.
baseline_read_state() {  # <source-id> <store>
  local sid=$1 store=$2 work project doc_id digest label text answer_digest kind key doc
  rm -f -- "$(cursor_path "$sid")" "$(ledger_path "$sid")"
  [ -f "$store" ] && [ ! -L "$store" ] || return 0
  work=$(mktemp -d "${TMPDIR:-/tmp}/fm-docstrap-baseline.XXXXXX") || return 1
  digest=$(sha256_file "$store")
  if ! store_scan "$store" "$MAP_DOCUMENT" "$MAX_ANSWER_BYTES" > "$work/scan"; then
    # A store that does not parse holds nothing this source can claim to have
    # read, so the next reading reports the break rather than starting from a
    # position invented here.
    rm -rf -- "$work"
    return 0
  fi
  project=$(awk -F'\t' '$1 == "project" { print $2; exit }' "$work/scan")
  doc_id=$(awk -F'\t' '$1 == "answer" { print $3; exit }' "$work/scan")
  : > "$work/keys"
  : > "$work/ledger"
  while IFS="$TAB" read -r kind key doc label text; do
    [ "$kind" = answer ] || continue
    answer_digest=$(sha256_text "$text")
    printf '%s\n' "$key" >> "$work/keys"
    printf '%s\t%s\n' "$label" "$answer_digest" >> "$work/ledger"
  done < "$work/scan"
  private_dir "$CURSOR_DIR" || { rm -rf -- "$work"; return 1; }
  write_cursor "$sid" "$project" "$doc_id" "$digest" "$work/keys" \
    || { rm -rf -- "$work"; return 1; }
  ( umask 077; cp -- "$work/ledger" "$(ledger_path "$sid")" ) || { rm -rf -- "$work"; return 1; }
  chmod 600 "$(ledger_path "$sid")" 2>/dev/null || true
  rm -rf -- "$work"
}

BACKLOG_LIB_LOADED=0
load_backlog_lib() {
  [ "$BACKLOG_LIB_LOADED" -eq 0 ] || return 0
  # shellcheck source=bin/fm-tasks-axi-lib.sh
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/fm-tasks-axi-lib.sh"
  # shellcheck source=bin/fm-backlog-transition-lib.sh
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/fm-backlog-transition-lib.sh"
  BACKLOG_LIB_LOADED=1
}

# The whole durable record of one held task, with its body decoded, so a
# citation written into the body is visible as ordinary text.
task_record_text() {  # <task-id>
  local id=$1 data show body
  load_backlog_lib
  data=$(fm_backlog_data_absolute "$DATA") || return 1
  show=$(fm_backlog_row_show "$data" "$id") || return 1
  body=$(printf '%s\n' "$show" | sed -n 's/^  body: //p' | head -1)
  case "$body" in
    \"*\")
      printf '%s' "$body" | perl -MJSON::PP -e '
        local $/; my $value = decode_json(<STDIN>);
        binmode STDOUT, ":raw";
        utf8::encode($value) if utf8::is_utf8($value);
        print $value;
      '
      printf '\n'
      ;;
  esac
  printf '%s\n' "$show"
}

# The provenance half of the pertinence test: the held task's own durable record
# must name this exact path. A reference firstmate cannot point at a citation
# for is dropped, because resemblance is not pertinence.
task_record_cites() {  # <task-id> <path>
  local text
  text=$(task_record_text "$1" 2>/dev/null) || return 1
  case "$text" in *"$2"*) return 0 ;; esac
  return 1
}

cmd_export() {
  local doc=${1-} payload=${2-} plan project_root store dir real sid now out tmp
  local label task question context ref line count dropped=0 wrote_block previous_map='' new_map=''
  [ "$#" -eq 2 ] && [ -n "$doc" ] && [ -n "$payload" ] || usage
  case "$doc" in *$'\n'*) die "document paths cannot contain newlines" ;; esac
  [ -f "$payload" ] && [ ! -L "$payload" ] || die "payload does not exist: $payload"
  dir=$(dirname -- "$doc")
  [ -d "$dir" ] || die "the destination directory does not exist: $dir"
  dir=$(CDPATH='' cd -- "$dir" && pwd -P) || die "cannot resolve the destination directory"
  real="$dir/$(basename -- "$doc")"

  project_root=$(resolve_project_root "$real") \
    || die "no docstrap project owns $real; it needs an ancestor carrying a $PROMDANCE_DIRNAME entry"
  store="$project_root/$PROMDANCE_DIRNAME/$STORE_BASENAME"
  case "$real" in
    "$project_root"/*) ;;
    *) die "the document does not sit inside its project: $real" ;;
  esac
  MAP_DOCUMENT=${real#"$project_root"/}
  case "$MAP_DOCUMENT" in
    "$PROMDANCE_DIRNAME"/*)
      die "a question document cannot live under $PROMDANCE_DIRNAME/, which docstrap excludes from a project"
      ;;
  esac

  plan=$(mktemp "${TMPDIR:-/tmp}/fm-docstrap-plan.XXXXXX") || die "cannot stage the question plan"
  out=$(mktemp "${TMPDIR:-/tmp}/fm-docstrap-doc.XXXXXX") || die "cannot stage the question document"
  # shellcheck disable=SC2064  # Both paths must expand now, while they are set.
  trap "rm -f -- '$plan' '$out'" EXIT
  plan_payload "$payload" "$MAX_QUESTIONS" > "$plan" || exit 1

  # Every task must be an open captain call before its question is written: a
  # question nobody holds cannot be closed by an answer, so asking it would
  # spend the captain's attention on work that is not waiting for him.
  while IFS="$TAB" read -r label task; do
    "$SCRIPT_DIR/fm-captain-hold.sh" open "$task" >/dev/null 2>&1 \
      || die "$label names $task, which is not an open captain call in this home"
  done < <(awk -F'\t' '$1 == "q" && $3 == "task" { print $2 "\t" $4 }' "$plan")

  now=$(date -u '+%Y-%m-%d')
  {
    printf '# %s\n\n' "$(awk -F'\t' '$1 == "doc" && $2 == "title" { print $3; exit }' "$plan")"
    context=$(awk -F'\t' '$1 == "doc" && $2 == "intro" { print $3; exit }' "$plan")
    [ -z "$context" ] || printf '%s\n\n' "$context"
    printf 'Written by firstmate on %s. Each question below is one decision waiting on the captain.\n' "$now"
    printf 'Answering one here is what releases the work it holds up.\n\n'
    printf '## Questions\n\n'
  } > "$out"

  while IFS="$TAB" read -r label task; do
    question=$(awk -F'\t' -v l="$label" '$1 == "q" && $2 == l && $3 == "question" { print $4; exit }' "$plan")
    context=$(awk -F'\t' -v l="$label" '$1 == "q" && $2 == l && $3 == "context" { print $4; exit }' "$plan")
    printf '%s. %s\n\n' "$label" "$question" >> "$out"
    [ -z "$context" ] || printf '%s\n\n' "$context" >> "$out"

    wrote_block=0
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '%s\n' "$line" >> "$out"
      wrote_block=1
    done < <(
      awk -F'\t' -v l="$label" '$1 == "q" && $2 == l && $3 == "option" { print $4 }' "$plan" \
        | awk '{ printf "%d. %s\n", NR, $0 }'
    )
    [ "$wrote_block" -eq 0 ] || printf '\n' >> "$out"

    wrote_block=0
    while IFS= read -r ref; do
      [ -n "$ref" ] || continue
      if ! references_enabled; then
        printf 'dropped-reference: %s %s (config/docstrap-references is absent)\n' "$label" "$ref" >&2
        dropped=$((dropped + 1))
        continue
      fi
      if [ ! -f "$project_root/$ref" ]; then
        printf 'dropped-reference: %s %s (the project holds no such document)\n' "$label" "$ref" >&2
        dropped=$((dropped + 1))
        continue
      fi
      if ! task_record_cites "$task" "$ref"; then
        printf 'dropped-reference: %s %s (the held task does not name it)\n' "$label" "$ref" >&2
        dropped=$((dropped + 1))
        continue
      fi
      printf 'fm-ref: %s path=%s\n' "$label" "$ref" >> "$out"
      wrote_block=1
    done < <(awk -F'\t' -v l="$label" '$1 == "q" && $2 == l && $3 == "ref" { print $4 }' "$plan")
    [ "$wrote_block" -eq 0 ] || printf '\n' >> "$out"
  done < <(awk -F'\t' '$1 == "q" && $3 == "task" { print $2 "\t" $4 }' "$plan")

  cp -- "$out" "$real" || die "cannot write the question document: $real"
  chmod 644 "$real" 2>/dev/null || true

  count=$(awk -F'\t' '$1 == "q" && $3 == "task"' "$plan" | wc -l | tr -d ' ')
  sid=$(cmd_source_id "$real") || exit 1
  private_dir "$MAP_DIR" || die "cannot create the private question record directory"
  [ ! -f "$(map_path "$sid")" ] || previous_map=$(sed -n 's/^q=//p' "$(map_path "$sid")")
  new_map=$(awk -F'\t' '$1 == "q" && $3 == "task" { printf "%s\t%s\n", $2, $4 }' "$plan")
  tmp=$(umask 077; mktemp "$MAP_DIR/.map.XXXXXX") || die "cannot stage the question record"
  {
    printf 'schema=fm-docstrap-map.v1\n'
    printf 'source_id=%s\n' "$sid"
    printf 'document=%s\n' "$MAP_DOCUMENT"
    printf 'document_path=%s\n' "$real"
    printf 'project_root=%s\n' "$project_root"
    printf 'store=%s\n' "$store"
    printf 'exported_at=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf 'count=%s\n' "$count"
    awk -F'\t' '$1 == "q" && $3 == "task" { printf "q=%s\t%s\n", $2, $4 }' "$plan"
  } > "$tmp" || die "cannot write the question record"
  chmod 600 "$tmp" || die "cannot secure the question record"
  mv -f -- "$tmp" "$(map_path "$sid")" || die "cannot commit the question record"

  if [ "$previous_map" != "$new_map" ]; then
    baseline_read_state "$sid" "$store" \
      || die "cannot baseline the answer read position for $sid"
    printf 'read-position: baselined against the store as it stands\n'
  fi

  printf 'exported: %s\n' "$real"
  printf 'document: %s\n' "$MAP_DOCUMENT"
  printf 'store: %s\n' "$store"
  printf 'source-id: %s\n' "$sid"
  printf 'questions: %s\n' "$count"
  [ "$dropped" -eq 0 ] || printf 'dropped-references: %s\n' "$dropped"
  printf 'next: bin/fm-captain-hold.sh bind %s, then bin/fm-procevent-docstrap.sh arm %s\n' "$sid" "$real"
}

case "${1-}" in
  export)     shift; cmd_export "$@" ;;
  arm)        shift; cmd_arm "$@" ;;
  source)     shift; cmd_source "$@" ;;
  source-id)  shift; cmd_source_id "$@" ;;
  classify)   shift; cmd_classify "$@" ;;
  terminal)   shift; cmd_terminal "$@" ;;
  answers)    shift; cmd_answers "$@" ;;
  autohandle) shift; cmd_autohandle "$@" ;;
  read)       shift; cmd_read "$@" ;;
  retire)     shift; cmd_retire "$@" ;;
  *) die "unknown command: $1" ;;
esac
