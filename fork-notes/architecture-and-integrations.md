# Firstmate's architecture, docstrap, and a revived specavator

Written 2026-10-29 at the captain's request.
The source is the captain's own words, quoted here spelling-corrected: only spelling and obvious typos are changed, and the wording is the captain's.

> I think I asked for an architectural overview of firstmate to understand it better and its relationship to docstrap.
> I'd like a full picture if we move forward and resurrect specavator, and use it with docstrap, promdance, firstmate, and lavish together.
> Docstrap has some overlap with lavish.
> I'd like to know if pants builds could help with firstmate having 1 to 1 with projects and repositories.
> I think the way specavator models projects and repositories also needs to be refined as part of its resurrection and revamp.
> The all new specavator should be able to function without firstmate but should be able to be driven by it.
> Specavator can be inter-related with the firstmate fork for integrating docstrap, I'm not sure if I want to combine integration for specavator into that same firstmate fork but changes that enable docstrap integration could perhaps also enable integration with specavator without many changes?
> It's supposed to keep coupling light and be usable with other third party extensions.
> If an extension mechanism has been introduced upstream that both can use then the need for the fork needs to be re-assessed.
> I'm not sure why the mechanic lavish uses or other extension mechanisms firstmate provides were not sufficient.
> This prompt is for a documentation note in the firstmate fork project and also a note that refers to it from the specavator project.

This note is a reading aid, not a second owner.
Where it and an owning file named beside a statement disagree, the owning file is right.
Several sources are private records in the captain's firstmate home, under the gitignored `data/` directory, so they do not travel with a clone; their substance is stated here and their paths are given only so they can be found on that workstation.
The main one is the specavator fitting scout report, rev 2 of 2026-10-27, `data/specavator-fitting-promdance/report.md`.

## Contents

1. [Firstmate as built](#1-firstmate-as-built)
2. [Docstrap, and what the fork changes](#2-docstrap-and-what-the-fork-changes)
3. [The full picture with specavator, promdance and Lavish](#3-the-full-picture-with-specavator-promdance-and-lavish)
4. [Pants, projects and repositories](#4-pants-projects-and-repositories)
5. [Coupling, extension points, and the fork](#5-coupling-extension-points-and-the-fork)
6. [Open problems](#6-open-problems)

## 1 Firstmate as built

[`docs/architecture.md`](../docs/architecture.md) is the in-depth owner, and [`AGENTS.md`](../AGENTS.md) is the supervisor's always-loaded contract.
This section only places the parts relative to each other.

### 1.1 One supervisor, its workers, and second mates

The primary firstmate is the captain's only point of contact for software work.
It never writes to a project itself: every project change is delegated to a worker it spawns and supervises (`AGENTS.md` section 1).
A worker is a ship, which changes one project, or a scout, which writes only a report under `data/<id>/report.md` ([`docs/architecture.md`](../docs/architecture.md) "Two task shapes").
A second mate is a persistent worker with its own isolated home and a charter, routed work by a natural-language scope recorded in `data/secondmates.md` (`docs/architecture.md` "Optional secondmates", the `secondmate-provisioning` skill).
Workers and second mates never address the captain; everything flows through the primary.

### 1.2 Homes

Scripts come from the tracked code root, while `FM_HOME` selects an instance's private directories.
`data/` holds durable private records, `state/` holds runtime records and append-only status events, `config/` holds local operating choices, and `projects/` holds clones that firstmate only reads.
[`docs/configuration.md`](../docs/configuration.md) "Operational home layout and state" and the `operational-home-layout` skill own the layout.
Each second mate has a home of its own, with its own backlog and session lock.

### 1.3 Projects

The registry is `data/projects.md`, one line per project, parsed by [`bin/fm-project-mode.sh`](../bin/fm-project-mode.sh), whose header owns the token syntax: delivery mode, `+yolo`, `branch=` and `forge=`.
Each project is one clone, flat under `projects/`, so the unit firstmate calls a project is a git repository.
Delivery posture, merge posture, branch prefix, machine capacity (`config/project-capacity`), the worktree pool and the backlog's `repo` field all attach to that repository.
The `project-management` skill owns adding, creating and removing projects.
Section 4 turns on this.

### 1.4 The backlog and captain holds

The backlog is the configured `tasks-axi` backend, always reached through [`bin/fm-tasks-axi.sh`](../bin/fm-tasks-axi.sh), with Queued, In flight and Done sections and holds and blocks as flags on a row.
A decision is not a separate record: it is an ordinary task held for the captain through [`bin/fm-captain-hold.sh`](../bin/fm-captain-hold.sh) ([`docs/captain-hold-lifecycle.md`](../docs/captain-hold-lifecycle.md)).
`fm-captain-hold.sh answers` is the one keyed-answer intake: every channel that carries a captain's answer turns it into `<task-id>`-keyed lines and pipes them there, and the intake alone decides what an answer closes.
Section 5 turns on this.
[`lifecycles-and-docstrap.md`](lifecycles-and-docstrap.md) Part 1 draws the backlog, ship, scout and captain-hold lifecycles.

### 1.5 Briefs, worktrees and delivery modes

[`bin/fm-brief.sh`](../bin/fm-brief.sh) scaffolds every worker's instructions, and the scaffold is a safety contract (`AGENTS.md` section 11).
A home may append standing static text to every brief through `config/brief-include.md` (`docs/configuration.md` "Home brief include").
[`bin/fm-spawn.sh`](../bin/fm-spawn.sh) launches each ship or scout into an isolated disposable worktree of one repository, from a treehouse pool or an Orca-managed worktree (`docs/architecture.md` "Worktrees, not branches in your checkout").
The delivery mode is resolved per task: `no-mistakes` validates through a pipeline to a PR, `direct-PR` pushes and opens a PR, and `local-only` stops at a ready branch landed by a guarded fast-forward (`docs/architecture.md` "Delivery modes are explicit per task").
Merge authority is separate from the mode, and landing runs only through [`bin/fm-pr-merge.sh`](../bin/fm-pr-merge.sh) or [`bin/fm-merge-local.sh`](../bin/fm-merge-local.sh).
[`bin/fm-teardown.sh`](../bin/fm-teardown.sh) cleans up and refuses work that has not landed.

### 1.6 The watcher, the wake queue and the supervision host

[`bin/fm-watch.sh`](../bin/fm-watch.sh) is a zero-token bash watcher that classifies events and wakes the primary only for actionable ones, by appending durable wake records.
The primary drains that queue with [`bin/fm-wake-drain.sh`](../bin/fm-wake-drain.sh) before acting and acknowledges only after handling, so an interrupted turn re-handles rather than loses work (`docs/architecture.md` "Event-driven supervision", [`docs/watcher-continuity.md`](../docs/watcher-continuity.md)).
Beside a primary that is not Pi, the supervision host runs routine wake handling on a headless engine session so routine wakes stay out of the captain's conversation ([`docs/supervision-host.md`](../docs/supervision-host.md)); on Pi the same contract runs as an in-process supervision branch.

### 1.7 Status and steering inboxes

A worker reports by appending one line to `state/<id>.status`, and each line is a wake event rather than current state: [`bin/fm-classify-lib.sh`](../bin/fm-classify-lib.sh) owns what a line means and [`bin/fm-crew-state.sh`](../bin/fm-crew-state.sh) reconciles current state.
Firstmate steers a worker through [`bin/fm-send.sh`](../bin/fm-send.sh), which writes a durable message into the task's steering inbox and rings a constant doorbell in the worker's terminal; the worker acknowledges by moving the message into `handled/`, and [`bin/fm-task-inbox-lib.sh`](../bin/fm-task-inbox-lib.sh) re-rings and escalates an unacknowledged one.
Lifecycle control, as opposed to text, goes through [`bin/fm-control.sh`](../bin/fm-control.sh) ([`docs/agent-control.md`](../docs/agent-control.md)).

### 1.8 Process-event sources

[`bin/fm-procevent.sh`](../bin/fm-procevent.sh) is a generic runner that owns an outside source, such as a review board waiting for the captain, captures each result durably under `state/procevent-inbox/`, and publishes it as a `check` wake.
What a result means is asked of the source's adapter through a fixed set of seams: `classify`, `terminal`, `silent`, `answers` (which feeds the keyed-answer intake for a bound source), `autohandle`, `self-announcing` and `relisten`.
A built-in adapter is a script named `bin/fm-procevent-<adapter>.sh`, resolved only from the tracked code root; upstream ships `lavish`, `quota`, `when` and `remote-reply`.
The `process-event-sources` skill owns arming and handling, and `docs/configuration.md` "Process-to-event sources" owns the runner's contract.

### 1.9 Extension bindings

[`docs/extension-bindings.md`](../docs/extension-bindings.md) is upstream's mechanism for binding third-party code, added on 2026-08-29, and `docs/configuration.md` calls it "one narrow extension type, not a general plugin or hook system".
It binds a trusted outside package as a process-event adapter, `process-event-adapter/1`, with four operations: poll, classify, terminal and silent.
It deliberately withholds the `answers`, `autohandle` and `self-announcing` seams, and states that no extension response can authorize a captain decision.
It also says what it is not: no lifecycle sinks, runtime backends, worker-launch grants, before or after hooks, instruction injection, project discovery or task mutation.

### 1.10 Skills and hooks

Agent-only skills under `.agents/skills/` load only at the trigger their description names, so `AGENTS.md` stays small; the `agent-skill-trigger-index` skill audits the triggers.
Harness hooks are firstmate's own guards, not extension points: the turn-end guard ([`docs/turnend-guard.md`](../docs/turnend-guard.md)), the session-start adapters ([`docs/sessionstart-nudge.md`](../docs/sessionstart-nudge.md)), and the directory, subagent and arm guards those pages name.

## 2 Docstrap, and what the fork changes

### 2.1 Where docstrap sits

Docstrap is a separate tool, kept in the platformshoes repository at `packages/docstrap`.
It discovers documentation projects by their `.docstrap` files, builds each with Sphinx, and aggregates them into one local site.
It owns document identity, a closed six-value lifecycle status, a document's `Q<n>` questions, and the answer store `answers.md` that lives in each project's promdance entry.
It never reads a firstmate home: `docstrap firstmate-ignore-check` writes `ignore: true` into one so no scan enters it.
Two invariants govern the pairing: docstrap does nothing inside a firstmate home, and firstmate does not touch the captain's working copies to make the pairing work; firstmate is always the actor.
Firstmate's own docstrap project, with its proposals, triage pages and open-questions page, lives privately at `data/docstrap` in the home.

### 2.2 What each fork change does

[`upstream-sync.md`](upstream-sync.md) section 5 inventories the fork and owns how to keep it current.
At the time of writing the fork differs from upstream in eighteen files, which `git diff --stat upstream/main...HEAD` lists; the notice bridge and the task export below were added after that section's last count.

2.2.1 **The question bridge.**
[`bin/fm-procevent-docstrap.sh`](../bin/fm-procevent-docstrap.sh) and its test add a built-in process-event adapter.
`export` writes held decisions as `Q<n>` questions into a document in one of the captain's projects and keeps the label-to-task map privately under `state/`; `arm` registers the answer reader and refuses until the source is bound to the keyed-answer intake; `notice` runs the reader once when docstrap reports the answers done; `answers` and `autohandle` feed the intake and advance the read position after capture.
Its header owns the mechanics, and traffic is one-way by design.

2.2.2 **The on-demand seam.**
A small edit to upstream's [`bin/fm-procevent.sh`](../bin/fm-procevent.sh) lets a built-in adapter declare `on-demand`, so reconcile never starts its source and only an explicit start reads it.
It and the fork sync in [`bin/fm-update.sh`](../bin/fm-update.sh) (section 2.2.4) are the fork's two changes to upstream's code logic, and the seam exists so the docstrap store is read on the captain's notice instead of on a timer ([`go-listener-architecture.md`](go-listener-architecture.md) section 2).

2.2.3 **The task export.**
[`bin/fm-task-export.sh`](../bin/fm-task-export.sh) and its test write the open backlog, with census fields and recommendation history, to `tasks.json` in firstmate's docstrap project for docstrap's task tool.
On the notice for that page, the bridge appends each new task decision of the captain's to the task's recommendation history and wakes firstmate once, changing no task itself.

2.2.4 **Fork upkeep.**
A fork sync in [`bin/fm-update.sh`](../bin/fm-update.sh) and its tests advance the fork from upstream before a self-update fast-forwards, and the files under `fork-notes/` record how the fork is kept.

2.2.5 **Documentation of the above.**
Entries in `docs/configuration.md`, the `process-event-sources` and `operational-home-layout` skills, and `docs/documentation-audiences.json` describe the first four.

2.2.6 **The question-restatement rule** in `AGENTS.md` is a rule of the captain's about how questions are put in chat, and has nothing to do with docstrap's mechanics.

### 2.3 The round trip

Firstmate exports questions into a project document and binds and arms the reader.
Docstrap finds the questions by its own `Q<n>` rule, and the captain answers them in its panels, which save continuously.
Pressing docstrap's "answers done" runs the `answers_done_command` set in docstrap's user config, which is `fm-procevent-docstrap.sh notice`.
The notice starts the reader once through the runner, so the reading is captured, its answers reach their held tasks through the keyed-answer intake, and a wake is published.
[`lifecycles-and-docstrap.md`](lifecycles-and-docstrap.md) section 1.5 draws the round trip as it stood before the notice replaced the timed read, and its Part 2 maps the relations that are only possible.

## 3 The full picture with specavator, promdance and Lavish

The fitting report proposes this shape; none of it is built, and its open calls are the captain's (section 6.5).

### 3.1 What each owns

3.1.1 **Specavator** owns the specification discipline and nothing else: a project's contract kept apart from the code that fulfils it, a stable identity for each requirement, and a one-way step from contract to work.
Revived, it is a small command line over git and docstrap that creates and checks specification contexts, owns the specification document type (templates, requirement numbering, the rule that a specification states what it does not do, and a declared constraint state of firm, choice or open for every detail), and writes hand-off records.
It runs no server, keeps no database, builds no site, hosts no agents and tracks no tasks.

3.1.2 **Docstrap** stays the reader, publisher and aggregator, and the single owner of identity, lifecycle status, questions and answers.
It learns one new fact, which code projects a context specifies, and answers that relation in both directions.

3.1.3 **Promdance** is each project's store of material that is not canon: prompts, drafts, notes and docstrap's answer records, kept in one store outside every project's git and linked into working copies by a gitignored symlink, so it is the same place from every branch and worktree.
The report proposes governing it directory by directory: the captain's domain, which is the default and keeps "promdance is OFF LIMITS" wherever nothing is marked; places the captain directs for a named use; and places a tool keeps on initiative, such as docstrap's answer files.

3.1.4 **Firstmate** stays the dispatcher and tracker of work: specification work and code work go out as separate tasks, one writable repository per worker, and a worker sees the other side only as a pinned read-only export in the task's own directory.

3.1.5 **Lavish** is outside the report.
It is a review surface for a live discussion: one rendered artifact the captain annotates, with choices sent back round by round, integrated into upstream firstmate as the built-in adapter [`bin/fm-procevent-lavish.sh`](../bin/fm-procevent-lavish.sh), whose header calls a Lavish review "just an ephemeral discussion format that happens to carry answers".

### 3.2 How they meet

A change starts as drafts in the specification context's promdance entry.
When the captain sets a draft out for use, firstmate pins a copy into a spec ship's task directory, and the spec ship restates it as specification in the context; the draft itself never crosses.
Docstrap publishes the context, the captain answers its numbered questions and moves its lifecycle status, and a spec ship writes a hand-off naming the requirements, one target code project, the acceptance criteria for the firm details and the alternatives for the others.
Firstmate files the implementation task from the landed hand-off, asks docstrap which context specifies the target, and dispatches a code ship carrying the hand-off and a read-only export of the context at that commit.
The code ship writes only the code project, meets every firm detail, decides choice and open details itself and records what it tried, and stops only when firm details cannot all hold.
Firstmate returns what it tried as numbered questions through the existing docstrap bridge, and a tried alternative stays an observation until the captain settles it.
Lavish meets this loop where firstmate already uses it, for a live visual review such as a scout's design board or the bearings board, whose answers feed the same keyed-answer intake.

### 3.3 Where docstrap and Lavish overlap

They overlap on three fronts, and the overlap is real duplication.
Both are browser review surfaces put in front of the captain.
Both carry the captain's answers to held decisions into the same keyed-answer intake through a built-in adapter.
Both show fleet boards: the bearings board is a Lavish artifact, and docstrap's task tool shows the backlog from `tasks.json`.

They differ in what lasts and in how a round ends.
A Lavish review is one artifact for one session, answered by annotations and per-question choice buttons, read round by round, and closed when the session ends.
A docstrap page is a durable document in a project's repository, published on the aggregate site, saved as the captain types, and finished by one "answers done" notice, with its answers kept in a store with history.
Docstrap will not adopt Lavish's per-question button ([`go-listener-architecture.md`](go-listener-architecture.md) section 3.4).

Stated plainly: for answering held decisions and for showing the backlog, the two now do the same job twice.
Lavish's own ground is the ephemeral visual review of a rendered artifact; docstrap's own ground is durable, published, versioned documents.

## 4 Pants, projects and repositories

### 4.1 Firstmate's one-to-one today

Firstmate's project is a repository (section 1.3), and nothing below the repository has an identity of its own.
The fleet already strains that: platformshoes carries docstrap, which the registry itself calls fleet-wide tooling rather than a platformshoes feature, beside laces, ccpane and other members, and rl_deployment once shared dkp's repository.
Two tasks touching different members of one repository look like one project with one posture, one pool and one capacity.
This gap is recorded and held for the captain as the backlog item `multi-project-repos-h57`, which is deliberately not designed yet.

### 4.2 What Pants would and would not change

Pants is a build system for many targets in one repository, with dependency inference, caching and selection of the targets a change touches.
It would give a machine-readable list of the members inside a repository and of which members a change affects.
It would not change what firstmate's project is: a worktree, a branch, a landing and a merge are still per repository, and posture, capacity and the pool attach to those.
So Pants makes many projects in one repository easier for build tooling; it does not make firstmate track members, and it does not split repositories.

### 4.3 The evidence already gathered

The mate-state proposal (`data/mate-state-proposal/report.md` section 2.5) evaluated Pants for platformshoes and recommended against it.
Its JavaScript backend is beta, its TypeScript support experimental, and Svelte is not covered; its uv support is an experimental lockfile format for its own resolves, not a reader of a uv workspace.
It adds `pants.toml` and BUILD targets as a second source of truth beside `pyproject.toml` and `package.json`.
It earns that weight with many targets and continuous-integration scale, and the fleet is local-only with a handful of members per repository.
The fleet standard is the uv workspace, whose member list already names every member, and docstrap's `.docstrap` `projects:` entries already name member paths.

### 4.4 The answer

Pants would not help firstmate keep one project to one repository.
One-to-one is reached either by splitting repositories, which fits firstmate with no change and has a worked example in the rl_deployment split, or by giving firstmate a project identity below the repository, which is `multi-project-repos-h57`.
Either way the member list a design would need already exists in uv workspaces and `.docstrap` files, so Pants is a prerequisite for neither.

### 4.5 What specavator's project and repository model needs

Today's specavator keeps projects in five places that disagree: a workspace found by walking up, with a silent fallback to a global hub; a SQLite `projects` table; a hub `registry.json` minting ids and tokens; a registry of running servers; and per-client tracking directories.
It also writes into code projects (`install-client`, `pull`, `bootstrap`) and commits and pushes across repositories (`sync`).
The revamp replaces all of that with one relation, one record and one owner (report section 5).

4.5.1 **A context.**
A specification context is independent of the code in authority, history and location: either an entry in one shared specification store repository, or a repository of its own.

4.5.2 **The relation.**
A context names each code project it specifies in a `specifies` list in its own `.docstrap`, a field owned by docstrap's schema and written through a docstrap command.
Each entry has a required `repo`, the captain's working copy, an optional `member`, a path inside that repository for a workspace member such as `packages/docstrap`, and an optional `remote`.
Docstrap computes the reverse direction and folds any worktree path onto its canonical checkout, so the code project is never touched.
The `member` field handles the many-projects-per-repository case at the level of the relation, so specavator does not need firstmate to model members.

4.5.3 **Where it meets firstmate's one-to-one.**
A context may specify several repositories and members, but a hand-off names exactly one context and one target, because one code ship writes one repository.

4.5.4 **Without firstmate, and driven by it.**
Specavator is a command line over git and docstrap and needs nothing from firstmate.
Firstmate drives it by reading its machine-readable outputs, such as the hand-off listing at a commit and docstrap's `specifies` query, and by registering each context as a project of its own.
Specavator never calls firstmate or reads its home, so the dependency runs one way.

## 5 Coupling, extension points, and the fork

### 5.1 Why the bridge is a built-in: the record

The bridge task's instructions of 2026-09-11 (`data/fm-docstrap-question-bridge-h71/brief.md`) record that the captain asked whether the bridge could be a plugin.
The answer given there was no, quoting upstream's process-event skill: "External process-event bindings intentionally expose no answer operation and cannot feed the captain-answer intake", so "only a built-in adapter can carry answers", and the bridge was modelled on Lavish's adapter.
Extension bindings had landed upstream thirteen days earlier, so the mechanism was there and was set aside for that reason.
The later notice design needed a source that only an explicit start reads, which extension bindings also withhold, so the fork added the on-demand seam to upstream's runner (section 2.2.2).

### 5.2 Why Lavish's mechanism did not spare a fork

Lavish has no extension mechanism of its own to borrow.
Lavish is integrated by upstream itself, as a built-in adapter in upstream's own `bin/`.
The fork did exactly what Lavish does, and because a built-in adapter is resolved only from the tracked code root (`adapter_script` in `bin/fm-procevent.sh`), doing what Lavish does means adding a file to upstream's tree, which is a fork.

### 5.3 Whether the other extension points would have sufficed

Extension bindings could not carry answers, by upstream's design (section 1.9).
Skills are instructions only and add no code seam.
`config/brief-include.md` appends the same static text to every brief and carries no per-task content or event intake.
Harness hooks enforce firstmate's own guards, and upstream offers no hook surface to third parties.

Two public commands would very likely have sufficed, and the records do not show that they were weighed.
`fm-captain-hold.sh answers` is the one keyed-answer intake "fed by every channel": it reads keyed lines on stdin, treats `--source` as provenance only, has no per-channel branch, and is idempotent on a replayed answer.
`fm-inbox.sh note` is a durable intake that appends one `check` wake, idempotent with `--request-id`.
A command run by docstrap's `answers_done_command`, kept in docstrap or as a home-local script, could have exported the questions, kept the label map, read `answers.md`, piped keyed lines into the intake and left a note, with no tracked change to firstmate.
The task export needs no seam at all: it reads the backlog through `bin/fm-tasks-axi.sh` and writes a file.
What the built-in adds over that path is the runner's ownership of the source (listing, retirement, reconcile and stranded-source detection), durable capture before delivery, and the same shape as Lavish's adapter.

### 5.4 Whether the docstrap changes would carry specavator

5.4.1 **Questions, yes, unchanged.**
A specification context is a docstrap project with its own promdance entry, so its documents' `Q<n>` questions and its `answers.md` work with `export`, `arm` and `notice` exactly as any project's do.
Questions a code ship raises would be posed in firstmate's own docstrap project through the same bridge (report section 6.3.7).

5.4.2 **The boundary, no.**
Specavator's firstmate side, listed in report section 6.4, sits in registry parsing, the brief scaffold, spawn, the definition of done and landing: `bin/fm-project-mode.sh`, `bin/fm-brief.sh`, `bin/fm-spawn.sh`, `bin/fm-dod-lib.sh` and `bin/fm-merge-local.sh`.
None of that is event intake, and the docstrap changes touch none of it.
Those are among upstream's busiest files: of the 165 upstream commits between the fork's last merge (upstream `b062eb94`) and upstream's main as fetched on 2026-10-29, 31 touched `bin/fm-spawn.sh` and 10 touched `bin/fm-brief.sh`.
Editing them would turn the fork from new files, which upstream cannot conflict with, into permanent conflicts in the files upstream changes most.

5.4.3 **What existing surfaces already carry.**
Much of driving specavator needs no firstmate code: firstmate can run docstrap's `specifies` query and specavator's hand-off listing at intake, place a pinned `git archive` export under the task's `data/<id>/`, which every brief already names as the worker's own, and carry the hand-off in the brief's specification.
What cannot be had without core edits is enforcement: spawn refusing an unlanded pin, landing refusing a diff outside the context or into promdance, and a generated scaffold paragraph.

5.4.4 **Light coupling for third parties.**
The coupling that stays light runs one way through command lines and JSON: firstmate calls docstrap's and specavator's commands and reads their output, docstrap calls back only through a configured command (`answers_done_command`), and neither reads firstmate's home.
Any third-party tool can sit on the same seams: a configured callback that calls firstmate's public intake commands.

### 5.5 Retiring the fork, and the test for it

For docstrap, retirement needs no new upstream mechanism if the bridge moves onto the public commands of section 5.3.
Inside upstream's extension model it would need `process-event-adapter` to gain a keyed-answer operation, a post-capture handling operation and an explicit-start mode, which are the three things version 1 withholds; the answer operation runs against upstream's stated boundary that extension output never authorizes a captain decision, so it should not be counted on.
The rest of the fork moves without upstream's help: the fork sync exists only because there is a fork, the question-restatement rule is a captain preference whose home-local owner under `AGENTS.md` section 6 is `data/captain.md` unless upstream takes it, and fork notes can live in any tracked repository.

The test is a classification of every fork change by how it reaches firstmate.
A change that uses only public commands can move out of the fork.
A new file upstream resolves only from its own code root, such as a built-in adapter, keeps the fork until upstream exposes an equivalent extension capability.
An edit to upstream's own files keeps the fork and costs conflicts at every merge.
The fork is needed exactly while either of the last two classes is non-empty.
Rerun the classification at every upstream sync, against `git diff --stat upstream/main...HEAD` and the capability list in upstream's `docs/extension-bindings.md`.
At the time of writing the bridge is in the second class; the on-demand seam, the fork sync, the `AGENTS.md` rule and the documentation entries are in the third; and the task export is in the first and could move out as it stands.

## 6 Open problems

6.1 **Who owns decisions and boards.**
Lavish and docstrap both carry the captain's answers into one intake and both show the backlog, so two surfaces now do one job, and nothing yet says which a given decision or board belongs on.

6.2 **Whether the bridge belongs inside firstmate's tree.**
The public intake commands would carry the docstrap bridge from outside, at the cost of the runner's ownership and durable capture, and what of that is worth keeping a fork for is undecided.

6.3 **Where specavator's boundary is enforced.**
The fitting wants its rules as mechanisms in the scaffold, spawn and landing, while light coupling and a cheap fork want upstream's busiest files untouched, and no upstream surface lets an outside tool add a brief section, a spawn check or a landing check.

6.4 **Whether firstmate needs a project below the repository.**
Splitting repositories keeps one-to-one with no change to firstmate, docstrap stays inside platformshoes while being fleet-wide tooling, and the alternative is the undesigned and held `multi-project-repos-h57`.

6.5 **Specavator's shape.**
The fitting report's first four calls decide the shape of everything after them, and they are held for the captain as `specavator-fitting-calls`.
They ask whether the revamp should make specavator a small tool over git and docstrap and keep the V2 service architecture as proposals outside it; whether one form of context is an entry in one shared specification store repository and the other a repository of its own; whether a context should record the code projects it specifies in its own `.docstrap`, under a field docstrap's schema owns; and whether each context should be registered as a firstmate project of its own, without standing merge authority.
Twenty more calls follow in the report's section 8.

6.6 **Trust in a callback.**
A command configured in docstrap's user config already closes captain-held tasks through the bridge, while upstream refuses to let extension output authorize a captain decision, so whether a third-party tool may feed the keyed-answer intake, and on what proof that its input is the captain's, is open.
