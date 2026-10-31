# Keeping the firstmate fork current, cheaply

Written 2026-09-26 at the captain's instruction, immediately after doing it the expensive way.
His words: "It feels like this should have been mechanical not 17 question for you and 5 quesations for me
deep."

He is right. This note exists so it is mechanical next time.

## 1 The model: main mirrors upstream, the fork's changes ride one rebased branch

`main` on `esotericbyte/firstmate` is an exact copy of upstream `main` and carries no fork commits.
The fork's own changes live on branch `esotericbyte`, rebased onto upstream `main`.
The operational home follows that branch through upstream's self-update source: `config/self-update-source` contains `origin esotericbyte`, and `/updatefirstmate` fast-forwards the home from it (`docs/configuration.md` "Self-update source").
The fork's earlier `bin/fm-update.sh` upstream-sync feature is gone; the self-update source supersedes it.

The fork exists for one reason: the yq replacement of Ruby in the YAML-reading tests, carried as a cherry-pick of upstream PR https://github.com/kunchenguid/firstmate/pull/6857 until upstream merges it.
When upstream merges that PR, drop the cherry-picked commit at the next rebase.

## 2 Keeping the branch current

Refresh `main` from upstream, then rebase `esotericbyte` onto it:

    git fetch upstream && git fetch origin
    git push origin upstream/main:main
    git rebase upstream/main esotericbyte

Push a dated backup of the old head before replacing it, then replace the branch with a lease:

    git push origin <old-head>:refs/heads/backup/esotericbyte-<date>-pre-rebase
    git push --force-with-lease=esotericbyte:<old-head> origin esotericbyte

Verify afterwards that upstream is an ancestor and that the divergence is only what section 4 lists:

    git merge-base --is-ancestor upstream/main esotericbyte
    git diff --stat upstream/main esotericbyte

Do it in a plain Claude Code session in a plain clone, not in the firstmate operational home, because every turn inside `~/firstmate` fires the supervision Stop hook and pays a wake-drain-acknowledge cycle that adds no information to a mechanical rebase.
Not as a firstmate task either, which is the captain's own suggestion: a crewmate's supervision, status protocol, and teardown verification are worth paying for judgment work and add nothing to a mechanical rebase.
Do not raise a pull request: nobody reviews upstream's already-landed work, and a PR imports a full CI run, an inherited upstream-owner gate, and a merge-authority question.

## 3 Two specific traps, each of which cost real time

**3.1 Check the GitHub token scope BEFORE starting.** Upstream's commits touch `.github/workflows/`, and
pushing those requires the `workflow` scope. Without it the push is refused after all the work is done,
which is where one captain interruption went. Check first:

    gh auth status    # look for 'workflow' in the scope list

If it is missing the fix is `gh auth refresh -h github.com -s workflow`, which the captain must run, and
it preserves existing scopes.

**3.2 Run the lint the way CI runs it, not the way it runs locally.** `bin/fm-lint.sh` in changed-file
mode **disables SC1091, SC2034, SC2153 and SC2329 entirely** because they need library context. A local
green is therefore not a weaker CI green - those checks did not run at all. On 2026-09-26 a dead-variable
SC2034 slipped through exactly this gap, failed CI, and cost a second push plus a ten-minute CI re-run.
Use CI's own invocation, both partitions:

    bin/fm-lint.sh --partition 1of2
    bin/fm-lint.sh --partition 2of2

Each takes about ten minutes. Run them before pushing, not after.

## 4 What the fork actually contains, so divergence stays checkable

Eighteen files as of the 2026-10-31 rebase onto upstream bb3e6906.
The docstrap process-event bridge (`bin/fm-procevent-docstrap.sh` and its hook in `bin/fm-procevent.sh`, plus its test) and the docstrap task export (`bin/fm-task-export.sh` plus its test), with matching notes in `docs/configuration.md` and two skills (the docstrap layout entries live in the operational-home-layout skill since upstream moved that block out of `AGENTS.md` section 2).
The question-restatement rule in `AGENTS.md`.
The three `fork-notes/` files and their classification in `docs/documentation-audiences.json`.
The yq change from upstream PR #6857: `tests/lib.sh`, `tests/fm-ci-workflow.test.sh`, `tests/fm-nm-test-contract.test.sh`, and `tests/fm-test-run.test.sh`.
Conflicts concentrate in `AGENTS.md` and `docs/configuration.md`, because both sides append to the same anchors.

Resolution rule: **keep both sides.** Upstream's entries keep their position and ours follow.

One fork divergence is temporary and is the exception to keeping both sides: `.github/workflows/ci.yml`
pins Pi and its `@earendil-works` packages to 1.1.0 and installs pinned TypeScript in both portable lanes.
When upstream's own test pinning covers the Pi extension typecheck, take upstream's side and drop the fork
pin. The fork-only comments in `ci.yml` state the reason.

Never edit upstream's code to satisfy a review. Every such edit is permanent divergence that re-conflicts
forever. This is also why the rebase must not go through no-mistakes - reviewing someone else's landed work invites
exactly that.

## 5 The honest cost accounting

Seven of the nine numbered questions put to the captain in this stretch were fork-update mechanics, not
judgment calls he needed to make: the token scope, the inherited gate, the merge method, the merge
authority, the gate workaround, and the two stale files blocking the fast-forward. Section 2 removes
the first four outright. Section 3 removes the rest.

The residual judgment call is genuinely his and should stay: whether to land at all. Nothing else here
needed him.

## 6 gh and gh-axi resolve to UPSTREAM in this home - never trust a bare PR number

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
