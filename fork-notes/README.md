# Fork notes

Notes about maintaining this fork of firstmate.
They are TRACKED on purpose: fork changes and fork notes must survive a fresh clone and must never be machine-local.

`data/` is gitignored, so anything kept there exists on one workstation only and is gone the moment the repository is cloned elsewhere.
These files belong to the fork itself, so they live here.

Nothing under this directory is loaded at session start.
A note is only useful if something that IS loaded points at it, so `data/learnings.md` carries one line naming this directory.

New paths cost nothing at merge time.
Measured 2026-09-28: zero upstream commits have ever touched any of this fork's own new files, because a path upstream does not know about cannot conflict.
