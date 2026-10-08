# Requirements

The tools this fork's runtime and test suite assume, with the minimum version the code actually needs and the reason it is needed.
Where the code states no floor, this note says so rather than inventing one.
Presence of the runtime tools, and the floors for no-mistakes and the axi-family tools, are checked at session start by `bin/fm-bootstrap.sh`, which owns those floors.

## 1 Node

The fork pins Node 24 in `.node-version` at the repository root.
The hard floor is a Node that runs `.ts` files natively, meaning type stripping is enabled by default and compiled in: Node 22.18 or 23.6 and later, built with TypeScript support (`node -p process.features.typescript` prints `strip` or `transform`, not `false`).
Node 22.12 cannot run `.ts` files, and some distribution builds of later 22.x releases are compiled without that support, which is why the pin names 24 rather than the floor.

TypeScript is needed at runtime, not only in tests.
`bin/fm-branch-dispatch.mjs` imports `.pi/extensions/lib/fm-branch-dispatch.ts`, so the supervision host's branch-eligibility decision fails on a Node without type stripping and every wake falls back to the main session (upstream issue kunchenguid/firstmate#6685).
The Pi extensions under `.pi/extensions/` and the calm mod under `.claude/mods/firstmate-calm/` are TypeScript too, and their tests load them with `node` directly.
Plain `node` is also used by the pre-tool command policies (`bin/fm-cd-command-policy.mjs`, `bin/fm-arm-command-policy.mjs`) and by the Claude and Antigravity trust writers.

### 1.1 How the pin is applied

The pin covers only processes Firstmate starts, so the shell's default Node and every other project are unaffected.
`bin/fm-node-pin-lib.sh` owns the mechanism: it reads `.node-version`, asks fnm for the matching installed version, and puts that version's bin directory on PATH ahead of the Node the process would otherwise use.
The supervision host inserts it immediately before the first PATH entry holding a `node` only when that entry is an fnm-managed Node; any other `node` earlier on PATH keeps its precedence, and with no fnm-managed `node` the host's PATH is left as it was. The Claude session environment and worker panes put it first.
When fnm is not installed, `.node-version` is missing or not a plain version, or the pinned version is not installed, PATH is left exactly as it was.
Three places apply it: a Claude session's later shell commands (through `CLAUDE_ENV_FILE` at session open), the supervision host and the engine it runs, and every worker Firstmate launches in a checkout of this repository.
A worker on any other project keeps its own Node.
Other primary harnesses have no session environment file, so their own shell commands keep the inherited Node; the supervision host and workers are still pinned.

Global npm tools installed through fnm live under one Node version each.
Every global tool Firstmate calls (`tasks-axi`, `gh-axi`, `quota-axi`, `lavish-axi`, `chrome-devtools-axi`, and the npm-installed harness CLIs) must therefore be installed under the pinned version as well as the shell's default.

GitHub CI does not read `.node-version`; it uses the runner image's Node.

## 2 jq

jq 1.6 or later.
The scripts use `--rawfile` and `--args`, both new in 1.6.
`bin/fm-fleet-snapshot.sh` defines its own `trim` rather than relying on the 1.7.1 builtin, so nothing found needs more than 1.6.

## 3 yq

Not used.
No script or test calls `yq`.

## 4 tmux

Required for the tmux runtime backend and for the e2e tests CI runs under real tmux.
The code declares no minimum version.
`bin/fm-bootstrap.sh` requires tmux only when the resolved runtime backend needs it.

## 5 Python 3

Python 3.11 or later.
`tomllib`, new in 3.11, is used by the Kimi turn-end hook (`bin/fm-kimi-turnend-hook.sh`), which refuses without it, and by its test.
Python also runs the documentation audience check, the mail and voice helpers, test fixtures, and the millisecond clock in `bin/fm-test-run.sh`; nothing else found needs more than 3.11.

## 6 git

git 2.38 or later.
`bin/fm-teardown.sh` uses `git merge-tree --write-tree`, new in 2.38, to prove a task's content already landed on the default branch.
On an older git that proof fails, so cleanup refuses rather than discarding work.
Worktrees, `rev-parse --path-format`, and `merge-base --is-ancestor` are used throughout and are older than 2.38.

## 7 ShellCheck and actionlint

ShellCheck exactly 0.11.0 and actionlint exactly the version `bin/fm-lint-workflows.sh --required-version` prints.
`bin/fm-lint.sh` refuses to run under any other ShellCheck version, so local lint and CI lint agree.
`bin/fm-install-shellcheck.sh` and `bin/fm-install-actionlint.sh` install the pinned, checksum-verified releases.
