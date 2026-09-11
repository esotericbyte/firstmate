#!/usr/bin/env bash
# Self-update a running firstmate and its secondmates to the latest origin.
#
# Mechanical half of the /updatefirstmate skill. On a FORK home it first advances
# origin's default branch from upstream (see "fork upstream sync" below), so that
# origin genuinely carries the latest firstmate before anything pulls from it.
# It then fast-forwards the running firstmate repo's default branch from origin,
# and then fast-forwards every
# registered secondmate home. Local homes are treehouse worktrees or standalone
# clones; remote routes update their configured code root on that host and then
# fast-forward the persistent home to that root. FAST-FORWARD ONLY, exactly like
# fm-fleet-sync.sh: never force, never create a merge commit, never stash;
# advance a target only when it is a clean fast-forward, otherwise skip and
# report. A tracked-files fast-forward never touches the gitignored operational
# dirs (data/, state/, config/, projects/, .no-mistakes/), so a secondmate's
# in-flight work is never disrupted. Worktrees of this repo share one object
# store, so a single fetch refreshes them all; standalone-clone homes are
# fetched on their own. Secondmate homes are leased at a detached HEAD on the
# default branch, so a fast-forward there advances HEAD only and never touches
# any other worktree's checkout or the shared `main` branch.
#
# The fast-forward mechanics live in bin/fm-ff-lib.sh (base_mode "origin" here);
# the same library drives local and remote parent-targeted secondmate sync, so
# there is one ff implementation, not several.
#
# --- fork upstream sync ----------------------------------------------------
# A home whose firstmate repo is a fork has TWO remotes: origin (the fork) and
# upstream (the repo it was forked from). A fork does not advance on its own, so
# pulling from origin alone delivers nothing new no matter how far upstream has
# moved. The fork condition is DETECTED, never assumed: a home with no upstream
# remote is the ordinary non-fork case and takes this path not at all - no extra
# command, no extra output, no new failure mode.
#
# The sync runs `gh repo sync <origin-slug> --source <upstream-slug> --branch
# <default>`, which advances the fork's branch on the forge itself, before the
# fetch below. That mechanism was chosen over hand-rolled ref surgery because it
# is the supported operation for exactly this, it is FAST-FORWARD ONLY unless
# --force is passed (which nothing here ever passes), it needs no local push and
# never touches this checkout, and its only write target is the fork. The
# upstream remote is a read-only source on every path here; its push URL is
# deliberately unusable and nothing below ever pushes to it.
#
# Every failure - no gh, no GitHub authentication, an unreachable or unnameable
# remote, or a fork that has DIVERGED from upstream - is reported on its own
# status line and in the `upstream-sync:` summary line, and never resolved by a
# merge or a force. All of them warn and continue rather than aborting: the run
# still has honest work to do (whatever origin itself carries, plus the whole
# secondmate fleet), and nothing is left half-advanced, while the reported
# failure plus the summary line keep the caller from reading the pass as a clean
# update. A divergence is named, not fixed.
#
# It does NOT re-read AGENTS.md or nudge secondmates itself - those are LLM /
# tmux actions the skill performs. The script's job is the safe git mechanics
# plus a parseable summary telling the caller what to do next:
#   - one status line per target (updated/already current/skipped)
#   - upstream-sync: synced|current|failed  (fork homes ONLY; absent entirely on
#     a non-fork home, so its output is unchanged)
#   - reread-firstmate: yes|no    (did the running firstmate's instructions change)
#   - restart-secondmates: fm-<id>...|none (every live secondmate this pass left
#     on origin's tip - advanced OR already there - whose recorded runtime can
#     prove a restart)
#   - nudge-secondmates: fm-<id>...|none   (the residual: live secondmates on
#     that same tip whose runtime CANNOT prove a restart, so the older re-read
#     steer is all that is honest for them)
#
# The two sets are disjoint, and restart is UNCONDITIONAL on a successful update
# of that home. It is deliberately not gated on the git diff: replacing the agent
# is the only thing that re-resolves the launch-time wiring - turn-end hooks,
# harness flags, per-harness feature switches - which a running agent froze when
# it started and which no changed_instr list describes. An unchanged tracked
# surface therefore is NOT evidence that the running agent is already on the
# current behavior, so an ALREADY-CURRENT home restarts too.
#
# Only two things keep a live mate out of the restart set, and neither is papered
# over as a reload:
#   - its home was SKIPPED (dirty, diverged, offline, unsafe). It is not on the
#     new bytes, nothing here forces, stashes, or discards it, and it gets no
#     action at all.
#   - its runtime cannot prove the old agent stopped and a replacement came up
#     (bin/fm-secondmate-restart-lib.sh owns that test), so it falls to the
#     honest re-read steer and is reported as a nudge, never as a reload.
# A positively dead or missing endpoint has no agent to replace and is left to
# the ordinary startup recovery.
#
# Usage: fm-update.sh [--help]
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FM_ROOT="${FM_ROOT_OVERRIDE:-$(cd "$SCRIPT_DIR/.." && pwd)}"
FM_HOME="${FM_HOME:-${FM_ROOT_OVERRIDE:-$FM_ROOT}}"
STATE="${FM_STATE_OVERRIDE:-$FM_HOME/state}"
SECONDMATES_MD="$FM_HOME/data/secondmates.md"
# shellcheck source=bin/fm-ff-lib.sh
. "$SCRIPT_DIR/fm-ff-lib.sh"
# shellcheck source=bin/fm-secondmate-restart-lib.sh
. "$SCRIPT_DIR/fm-secondmate-restart-lib.sh"

"$SCRIPT_DIR/fm-guard.sh" || true

usage() { echo "usage: fm-update.sh [--help]" >&2; }

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi
[ $# -eq 0 ] || { usage; exit 1; }

# --- fork upstream sync ----------------------------------------------------
# Header owns why this exists and why every failure warns rather than aborts.

# Echo the owner/repo slug a GitHub remote URL names, or fail. Accepts the https,
# ssh, and scp-style spellings and rejects anything that is not a plain
# owner/repo on github.com, so an unnameable remote becomes a reported failure
# rather than a guessed argument.
github_slug() {  # <remote-url>
  local url=$1 path
  case "$url" in
    *github.com/*) path=${url#*github.com/} ;;
    *github.com:*) path=${url#*github.com:} ;;
    *) return 1 ;;
  esac
  path=${path%/}
  path=${path%.git}
  case "$path" in
    */*/*|*' '*|/*|*/) return 1 ;;
    */*) ;;
    *) return 1 ;;
  esac
  [ -n "${path%%/*}" ] && [ -n "${path#*/}" ] || return 1
  printf '%s\n' "$path"
}

# Echo the owner/repo slug one remote names. Reads the CONFIGURED url first,
# because that is the repository's identity, and falls back to the resolved one
# so a home that reaches GitHub through an insteadOf rewrite is still nameable.
remote_slug() {  # <remote-name>
  local remote=$1 url
  url=$(git -C "$FM_ROOT" config --get "remote.$remote.url" 2>/dev/null) || url=""
  if [ -n "$url" ] && github_slug "$url"; then
    return 0
  fi
  url=$(git -C "$FM_ROOT" remote get-url "$remote" 2>/dev/null) || return 1
  [ -n "$url" ] || return 1
  github_slug "$url"
}

# Echo the configured url one remote names, for reporting.
remote_url() {  # <remote-name>
  git -C "$FM_ROOT" config --get "remote.$1.url" 2>/dev/null \
    || git -C "$FM_ROOT" remote get-url "$1" 2>/dev/null
}

# Empty on a non-fork home, which is what keeps its output unchanged.
upstream_sync=""

upstream_sync_failed() {  # <reason>
  upstream_sync="failed"
  echo "upstream sync: failed: $1"
}

# Advance origin's default branch from upstream when this home is a fork.
sync_fork_from_upstream() {
  local upstream_slug origin_slug default out
  git -C "$FM_ROOT" remote get-url upstream >/dev/null 2>&1 || return 0

  default=$(default_branch "$FM_ROOT") || {
    upstream_sync_failed "cannot determine the default branch"
    return 0
  }
  git -C "$FM_ROOT" remote get-url origin >/dev/null 2>&1 || {
    upstream_sync_failed "no origin remote to sync"
    return 0
  }
  origin_slug=$(remote_slug origin) || {
    upstream_sync_failed "origin is not a GitHub repository this can name: $(remote_url origin)"
    return 0
  }
  upstream_slug=$(remote_slug upstream) || {
    upstream_sync_failed "upstream is not a GitHub repository this can name: $(remote_url upstream)"
    return 0
  }
  command -v gh >/dev/null 2>&1 || {
    upstream_sync_failed "gh is not installed, so $origin_slug cannot be synced from $upstream_slug"
    return 0
  }
  gh auth status >/dev/null 2>&1 || {
    upstream_sync_failed "not authenticated to GitHub, so $origin_slug cannot be synced from $upstream_slug"
    return 0
  }

  if ! out=$(gh repo sync "$origin_slug" --source "$upstream_slug" --branch "$default" 2>&1); then
    if printf '%s\n' "$out" | grep -qiE 'fast.?forward|diverg'; then
      upstream_sync_failed "$origin_slug $default has diverged from $upstream_slug $default and was left untouched: $(first_line "$out")"
    else
      upstream_sync_failed "$origin_slug could not be synced from $upstream_slug: $(first_line "$out")"
    fi
    return 0
  fi
  if printf '%s\n' "$out" | grep -qi 'up to date'; then
    upstream_sync="current"
    echo "upstream sync: origin $default already current with $upstream_slug"
  else
    upstream_sync="synced"
    echo "upstream sync: origin $default synced from $upstream_slug"
  fi
}

sync_fork_from_upstream

# --- main firstmate repo ---------------------------------------------------

reread_firstmate="no"
ff_target "$FM_ROOT" "firstmate" origin no no
if [ "$FF_STATUS" = "updated" ] && [ -n "$FF_INSTR" ]; then
  reread_firstmate="yes"
fi

# --- secondmates -----------------------------------------------------------
# Every live secondmate this pass leaves on origin's tip is restarted, whether it
# advanced or was already there. The header above owns why the git diff does not
# gate that, and which two conditions - a skipped home, an unprovable runtime -
# are the only ways a live mate stays out of the restart set.

# FF_NUDGE_WINDOWS and FF_SEEN_HOMES are the sweep's own accumulators and are
# reset here per its contract; the instruction-gated nudge set is the session-start
# sweep's threshold, not this command's, so only the two sets below are read.
FF_NUDGE_WINDOWS=""
FF_SEEN_HOMES=""
FF_RESTART_WINDOWS=""
FF_STEER_WINDOWS=""

secondmate_agent_may_be_alive() {  # <id>
  local id=$1 meta="$STATE/$1.meta" remote_host state=unreadable
  remote_host=$(fm_meta_get "$meta" remote_host)
  if [ -n "$remote_host" ]; then
    state=$("$SCRIPT_DIR/fm-on.sh" "$id" \
      fm-remote-secondmate-control.sh state "$id" < /dev/null 2>/dev/null) || state=unreadable
  elif fm_backend_validate_task_endpoint "$meta" "$id" >/dev/null 2>&1; then
    state=$(fm_backend_agent_state "$FM_BACKEND_VALIDATED_BACKEND" \
      "$FM_BACKEND_VALIDATED_TARGET" 2>/dev/null) || state=unreadable
  fi
  case "$state" in
    dead|missing) return 1 ;;
    *) return 0 ;;
  esac
}

selector_claimed() {  # <selector>
  case " $FF_RESTART_WINDOWS $FF_STEER_WINDOWS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# Route one secondmate whose home this pass left on the target commit. Restart is
# the outcome unless its runtime cannot prove one, in which case it keeps the
# re-read steer and is reported as a nudge rather than as a reload. A stopped
# endpoint has no agent to replace and is left to startup recovery.
claim_settled_secondmate() {  # <id>
  local id=$1
  selector_claimed "fm-$id" && return 0
  secondmate_agent_may_be_alive "$id" || return 0
  if fm_secondmate_restart_capable "$STATE/$id.meta"; then
    FF_RESTART_WINDOWS="$FF_RESTART_WINDOWS fm-$id"
  else
    FF_STEER_WINDOWS="$FF_STEER_WINDOWS fm-$id"
  fi
}

# bin/fm-ff-lib.sh calls this for each local home it left AT the base with a live
# endpoint - status "updated" or "current" alike. A skipped home never gets here.
fm_ff_after_secondmate_settled() {  # <id> <home> <window> <status> <instr>
  claim_settled_secondmate "$1"
}

# Live direct reports first: state/<id>.meta with kind=secondmate carries the
# authoritative home= path.
sweep_live_secondmate_metas "$STATE" origin yes

# Registry backstop: a secondmate registered in data/secondmates.md but without
# a live meta (e.g. between restarts) is still its persistent on-disk home.
if [ -f "$SECONDMATES_MD" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "- "*) ;;
      *) continue ;;
    esac
    if ! secondmate_registry_parse_line "$line"; then
      echo "secondmate registry: skipped malformed entry: $line" >&2
      continue
    fi
    id=$SECONDMATE_REGISTRY_ID
    home=$SECONDMATE_REGISTRY_HOME
    if [ "$SECONDMATE_REGISTRY_REMOTE" -eq 1 ]; then
      if remote_out=$("$SCRIPT_DIR/fm-on.sh" "$id" fm-remote-secondmate-control.sh update "$id" < /dev/null 2>&1); then
        remote_result=$(printf '%s\n' "$remote_out" | tail -1)
        case "$remote_result" in
          synced:*)
            remote_detail=${remote_result#synced: }
            # The host reports its advance as "<commit> instr=<paths>"; a host
            # whose Firstmate copy predates that suffix reports the commit alone.
            # The suffix is now reporting detail only: the routing below no longer
            # reads it, so an older host's silence can no longer downgrade a
            # restartable mate to a steer.
            case "$remote_detail" in
              *' instr='*)
                remote_instr=${remote_detail##* instr=}
                remote_commit=${remote_detail%% instr=*}
                ;;
              *) remote_instr=""; remote_commit=$remote_detail ;;
            esac
            if [ -n "$remote_instr" ]; then
              echo "remote secondmate $id: updated on $SECONDMATE_REGISTRY_HOST ($remote_commit, instructions changed: $remote_instr)"
            else
              echo "remote secondmate $id: updated on $SECONDMATE_REGISTRY_HOST ($remote_commit)"
            fi
            if [ -f "$STATE/$id.meta" ] && grep -qx 'kind=secondmate' "$STATE/$id.meta"; then
              claim_settled_secondmate "$id"
            fi
            ;;
          current:*)
            echo "remote secondmate $id: already current on $SECONDMATE_REGISTRY_HOST (${remote_result#current: })"
            # Already on the target commit is a SUCCESSFUL update of that home,
            # so it earns the same restart as one that had to advance.
            if [ -f "$STATE/$id.meta" ] && grep -qx 'kind=secondmate' "$STATE/$id.meta"; then
              claim_settled_secondmate "$id"
            fi
            ;;
          *) echo "remote secondmate $id: skipped on $SECONDMATE_REGISTRY_HOST: malformed update result" >&2 ;;
        esac
      else
        echo "remote secondmate $id: skipped on $SECONDMATE_REGISTRY_HOST: ${remote_out%%$'\n'*}" >&2
      fi
    else
      process_secondmate "$id" "$home" "" origin yes
    fi
  done < "$SECONDMATES_MD"
fi

# --- caller action summary -------------------------------------------------

# claim_settled_secondmate puts each live settled mate in exactly one set, so the
# two lines below are disjoint by construction: no mate is ever restarted and
# then also steered about the instructions it just relaunched on.

[ -z "$upstream_sync" ] || echo "upstream-sync: $upstream_sync"
echo "reread-firstmate: $reread_firstmate"
echo "restart-secondmates:${FF_RESTART_WINDOWS:- none}"
echo "nudge-secondmates:${FF_STEER_WINDOWS:- none}"
