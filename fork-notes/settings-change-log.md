# A settings-change log with reasons — note, not a request to build

Captain's idea, 2026-09-28. Recorded as a note on the firstmate fork. **Nothing is to be built from this
until he says so.**

## The gap, confirmed

No such log exists. Checked 2026-09-28: nothing under `state/` records configuration changes, and the
fleet activity ledger (`docs/fleet-ledger.md`) covers task activity only — dispatch, worker reports,
PR-ready, merge, cleanup — not settings.

And firstmate's `config/` files carry a bare value with no metadata at all. `config/startup-memory-budget`
contains the five bytes `7500` and nothing else. **Why** it is 7500, who set it, and when, are recorded
nowhere. Before the 2026-09-27 prune that reasoning lived in `captain.md` prose; the prune removed it,
correctly, because it was prose in an always-loaded file.

## His shape for it

A dedicated file holding a log of settings changes, each with a very brief reason where one is available,
loaded **only when the captain asks about settings history or reasoning** — never as part of the startup
read. His stated motivation: keep `captain.md` and `learnings.md` from filling with chit-chat and trash
again, while not losing the one class of context that turned out to be genuinely useful, which is why a
setting is what it is.

The shape matches what already works elsewhere in this home: a durable file outside the startup set, with
a pointer from something that IS loaded so it can be found. An on-demand file nothing points at is a lost
file — see `data/note-fork-upstream-sync.md`, which was orphaned within twenty minutes of being written.

## Where fork notes belong — the two options and what separates them

`data/note-*.md` is the established convention: 25 markdown files live there, with `data/INDEX.md` as the
door. `data/` is gitignored, so those notes are private to this machine and **do not travel with the
fork**. A fresh clone of `esotericbyte/firstmate` has none of them.

A tracked new file in the fork travels with the repository and costs nothing at merge time. Measured
2026-09-28: **zero** upstream commits have ever touched either of the fork's two fork-only files. A new
path upstream does not know about cannot conflict, ever.

So the question for any fork note is simply whether it should survive a fresh clone. Notes about
maintaining the fork itself probably should; notes about this workstation's own state should not.
