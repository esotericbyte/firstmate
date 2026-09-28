# Keeping the firstmate fork current, cheaply

Written 2026-09-26 at the captain's instruction, immediately after doing it the expensive way.
His words: "It feels like this should have been mechanical not 17 question for you and 5 quesations for me
deep."

He is right. This note exists so it is mechanical next time.

## 1 The mechanical path, which is almost always the whole answer

    bin/fm-update.sh

That is it. On a fork home this advances `origin/main` from upstream before fast-forwarding the local
checkout, and reports `upstream-sync: synced|current|failed`.

**The premise that made 2026-09-26 expensive was wrong.** It was believed - stated in the fork-sync
feature's own commit and repeated in its pull request - that `gh repo sync` is fast-forward only and
refuses a fork carrying its own commits, so a diverged fork needs a hand-driven merge. It does not.
`gh repo sync` calls GitHub's merge-upstream API, which **creates a merge commit** when the fork has
diverged **and the merge is clean**. Refined 2026-09-27 after seeing both outcomes the same day: it
merged 12 commits in the morning, then refused in the afternoon with "can't sync because there are
diverging changes" once 22 further upstream commits touched `AGENTS.md` and `docs/configuration.md` -
two of the eight files this fork diverges in. So the rule is: it merges what it can and refuses a
conflict. A refusal is the legitimate trigger for section 3, not a bug. Proven the same day: minutes after landing the manual merge, an ordinary `bin/fm-update.sh`
silently merged 11 further upstream commits into our main and reported `synced`.

So the fork does not need a crewmate, a branch, a pull request, or a decision to stay current. It needs
one command, and the tokens it costs are the tokens of reading six lines of output.

**What to verify afterwards, because the merge is unreviewed.** A clean auto-merge is still a change to
our own default branch that nobody read:

    git -C ~/firstmate log --oneline <old-head>..origin/main
    git -C ~/firstmate diff --stat <upstream-head> origin/main   # fork divergence: expect 8 files

If divergence has grown beyond the fork's own features, something merged that should not have.

## 2 When the mechanical path refuses

GitHub refuses a conflicted merge-upstream, and the sync reports `failed`. That refusal is the only
legitimate trigger for a hand-driven merge. Everything in section 3 applies only then.

## 3 Doing a hand-driven merge without the apparatus

**Do it in a plain Claude Code session in a plain clone - NOT in the firstmate operational home, and NOT
as a firstmate task.** This is the captain's own suggestion and it is the single biggest saving available.

    git clone git@github.com:esotericbyte/firstmate.git /tmp/fork-merge && cd /tmp/fork-merge
    git remote add upstream https://github.com/kunchenguid/firstmate
    git fetch upstream && git merge upstream/main

Why the operational home is the wrong place. Every turn taken inside `~/firstmate` fires the supervision
Stop hook, so a mechanical merge pays a full wake-drain-acknowledge cycle per turn: read the queue, handle
the event, run the generation-bound acknowledgement. On 2026-09-26 that machinery fired on stale wakes and
turn-end signals repeatedly while the only thing happening was a ten-minute lint. None of it added
information, and each one cost a turn. A clone in `/tmp` has no hooks, no watcher, no lock, and no
directory guard.

Why running it as a firstmate task is also wrong. Dispatching a crewmate buys supervision, status
protocol, briefs, and teardown verification. All of that is valuable for work that needs judgment and
worthless for `git merge`. The supervisor then spends turns supervising a worker doing something the
supervisor could have done in two commands.

Then push the merge straight to main. **Do not raise a pull request.** A fork maintainer does not review
upstream's already-merged work; there is nothing to approve and no one to approve it. Raising one on
2026-09-26 imported three avoidable costs: a full CI run, a decision about an inherited gate that fails
by design for anyone who is not upstream's owner, and the merge-authority question - which together
accounted for four of the captain's five interruptions.

## 4 Three specific traps, each of which cost real time

**4.1 Never squash a merge.** The merge tool defaults to squash, and squashing flattens the merge commit
so upstream stops being an ancestor. Every future merge then re-processes the entire history and conflicts
on everything. Pass `--merge` explicitly, and verify afterwards that the merge commit still has two
parents and that `git merge-base --is-ancestor <upstream-head> main` succeeds.

**4.2 Check the GitHub token scope BEFORE starting.** Upstream's merges touch `.github/workflows/`, and
pushing those requires the `workflow` scope. Without it the push is refused after all the work is done,
which is where one captain interruption went. Check first:

    gh auth status    # look for 'workflow' in the scope list

If it is missing the fix is `gh auth refresh -h github.com -s workflow`, which the captain must run, and
it preserves existing scopes.

**4.3 Run the lint the way CI runs it, not the way it runs locally.** `bin/fm-lint.sh` in changed-file
mode **disables SC1091, SC2034, SC2153 and SC2329 entirely** because they need library context. A local
green is therefore not a weaker CI green - those checks did not run at all. On 2026-09-26 a dead-variable
SC2034 slipped through exactly this gap, failed CI, and cost a second push plus a ten-minute CI re-run.
Use CI's own invocation, both partitions:

    bin/fm-lint.sh --partition 1of2
    bin/fm-lint.sh --partition 2of2

Each takes about ten minutes. Run them before pushing, not after.

## 5 What the fork actually contains, so divergence stays checkable

Eight files, about 1,985 insertions, in three commits. The docstrap process-event bridge
(`bin/fm-procevent-docstrap.sh` plus its test), the fork-sync feature in `bin/fm-update.sh` plus its
tests, and the question-restatement rule in `AGENTS.md`, with matching notes in `docs/configuration.md`
and two skills. Conflicts concentrate in `AGENTS.md`, `docs/configuration.md`, the updatefirstmate skill,
and `tests/fm-update.test.sh`, because both sides append to the same anchors.

Resolution rule for all four: **keep both sides.** Upstream's entries keep their position and ours follow.
The one case needing real judgment was a test-number collision where both sides added a `T12` sharing one
scratch directory; ours moved to a `TF1`-`TF4` family so upstream's number line stays clean and its hunks
keep applying.

Never edit upstream's code to satisfy a review. Every such edit is permanent divergence that re-conflicts
forever. This is also why the integration merge must not go through no-mistakes - reviewing 188 commits of
someone else's landed work invites exactly that.

## 6 The honest cost accounting

Seven of the nine numbered questions put to the captain in this stretch were fork-update mechanics, not
judgment calls he needed to make: the token scope, the inherited gate, the merge method, the merge
authority, the gate workaround, and the two stale files blocking the fast-forward. Sections 1 and 3 remove
the first four outright. Section 4 removes the rest.

The residual judgment call is genuinely his and should stay: whether to land at all. Nothing else here
needed him.

## 7 gh and gh-axi resolve to UPSTREAM in this home - never trust a bare PR number

`~/firstmate` has two remotes: `origin` -> `esotericbyte/firstmate` (ours) and `upstream` ->
`kunchenguid/firstmate`. gh's default repo resolution picks `upstream`. So when the fork-merge worker
reported `done: PR https://github.com/esotericbyte/firstmate/pull/1` and I ran `gh-axi pr view 1`, I
got back a DIFFERENT pull request entirely: kunchenguid's "chore: initialize no-mistakes gate",
state **merged**, authored 2026-06-12. The session-start hook shows the same thing - its `repo:` line
reads `esotericbyte/firstmate` but its issue and PR lists are upstream's.

Read naively that says the worker's PR was already merged, which would have been a serious bookkeeping
error in either direction: it could have been read as "nothing to do, it landed" on a PR the captain
had never approved.

`gh pr list --repo esotericbyte/firstmate` returned the real one - number 1, OPEN, base `main`,
head `fm/fm-fork-upstream-merge-h145`. Same number, different repository, opposite state.

Rule: in this home, pass `--repo esotericbyte/firstmate` on every PR or issue query, and never trust a
bare PR number. Verify a reported PR by its base and head refs, not by its number. `bin/fm-pr-check.sh`
takes the full URL and records `pr_head=`, which is the identity that actually pins it - use that
recorded head to confirm you are looking at the same commit you reviewed.
