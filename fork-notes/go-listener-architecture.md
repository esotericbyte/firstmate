# The Go HTTP event listener - a decided architecture

First decided by the captain in conversation on 2026-09-30, and filed here at his instruction: "go http listner into firstmate fork notes."
Revised to the captain's rulings of 2026-10-12, which replaced the separate firstmate copy and the combine-by-area stage with one small push endpoint into firstmate's existing intake.
Revised again to the captain's rulings of 2026-10-13, which confirmed the design in section 1: messages go from the listener to the owning worker, and the logs are firstmate's follow-up list of messages nobody handled.

This is a record of rulings, not a proposal and not a plan.
The captain settled the shape himself, and the point of writing it down is that it stops being re-litigated.
Sections 1, 3 and 4 are decided.
Section 7 states the defaults chosen for the details the captain left to a sensible option, and names one contradiction inside the design rather than resolving it.
Section 5 records what was considered and discarded, because a reader who sees only the final state will propose the discarded options again.

Nothing under `fork-notes/` is loaded at session start, which is why this file is here rather than in `AGENTS.md`, a skill, or `data/captain.md`.
The captain was explicit that nothing should clog what every session loads.

## 1 The decided shape

Pages push HTTP events from a Web Worker to one Go listener on this machine.
The listener checks each message, writes it once to the message log, and delivers it to the worker of the task it belongs to.
Each worker records the messages it handled in its own message-work log and passes that file's path to firstmate when it finishes.
Firstmate resolves that file mechanically into the work log.
A message with no work-log entry is unhandled, and unhandled messages are what firstmate follows up.

    Lavish board page -> Web Worker -> HTTP POST -> |
                                                    | Go listener (this machine only,
    docstrap surface  -> Web Worker -> HTTP POST -> | token per page load)
                                                    |   reads firstmate records read-only
                                                    |   rejects invalid messages at intake
                                                    |
                         +--------------------------+--------------------------+
                         |                                                     |
                         v                                                     v
                   message log                                    owning task's worker
                   (listener only,                                (delivered through the
                    one record per message,                        doorbell it already answers)
                    written once)                                              |
                         |                                                     v
                         | inotify                                   message-work log
                         v                                           (that worker only)
                   firstmate primary  <---- worker passes the file path when it finishes
                         |
                         v
                   work log
                   (firstmate only: resolved worker entries
                    plus entries for messages firstmate handled itself)

There is no separate firstmate copy, no `fm2` home, no combine-by-area stage, and no prioritizer.
The Claude command prompt is not in the loop.

### 1.1 The three files and their writers

Every file has exactly one writer, and every record in it is written once and never edited.
The captain was explicit: "having the files writen by mulitple processes is not a smart design."

| File | Only writer | Holds | Readers |
| --- | --- | --- | --- |
| Message log | Go listener | One message record per accepted message | Firstmate, and the listener itself for repeat ids and rotation |
| Message-work log | The worker of one task | One entry per message that worker handled | Firstmate's resolution script |
| Work log | Firstmate | One entry per handled message, keyed by message id | Firstmate, and the listener for rotation |

Nothing about delivery, acknowledgement or an unhandled reason is ever written back onto a message record.
Whether a message was handled is answered only by the presence of its work-log entry.

### 1.2 The page side

Each page sends from a Web Worker so it never blocks the page's UI thread.
The Lavish artifact is HTML we author, and docstrap's widget surfaces are pages rendered by docstrap, which the captain owns, so neither tool's server needs a push feature added and no upstream dependency blocks the build.
The page retries a failed send a limited number of times.
When the listener is still unreachable after those retries, the page tells the user that the listener needs a restart.
When the listener rejects a message at intake, the page shows the listener's error.
Nothing is queued in the page or anywhere else for later delivery.

### 1.3 The message record

The listener writes one record per accepted message, once, at intake.
Every field is required.

| Field | Meaning |
| --- | --- |
| `id` | The message's id, assigned when the page builds it and reused on every retry of that message. |
| `original_time` | When the message first entered a message log; kept unchanged when rotation carries the record forward. |
| `received_time` | When the listener accepted this message. |
| `source` | `docstrap` or `lavish`. |
| `source_ref` | Where it came from: for docstrap the store, the document path and the question label; for Lavish the board and the session. |
| `seq` | The message's sequence number within its `source_ref`. |
| `task_id` | The task the message belongs to, taken from the page's own context and checked against firstmate's records. |
| `project` | The project of that task, taken from the task's record. |
| `kind` | `answer`, `annotation`, `note` or `session_end`. |
| `body` | The captain's words as typed; empty for `session_end`, which carries no typed words. |
| `payload` | Per kind: the question label for an `answer`, the selector for an `annotation`, and empty for `note` and `session_end`. |

### 1.4 Intake and delivery

The listener rejects at intake any message with a missing or invalid field, and any message whose `task_id` is not in firstmate's records; the page shows the error and nothing is written.
A message always has an owning task, because a message without one never gets past intake.
A repeated `id` is dropped and answered as success, so a retry after a lost success answer is written once.
Within one `source_ref`, the listener delivers messages in `seq` order.
The listener answers the page with success only after the record is durable in the message log.
It then delivers the message to its task's worker, and records nothing about that delivery.

The listener reads firstmate's records read-only, which is how it checks `task_id` and fills `project`.
It never writes a firstmate record or the backlog.
Delivering to a worker is now the listener's job by the captain's 2026-10-13 rulings, and section 6.2 records that boundary.

### 1.5 The worker's message-work log

Each worker writes its own message-work log, one entry per message it handled.

| Field | Required | Meaning |
| --- | --- | --- |
| `message_id` | Yes | The `id` of the message handled. |
| `handled_time` | Yes | When the worker handled it. |
| `action` | Yes | What the worker did with it, in a short phrase. |
| `note` | No | Anything firstmate should know about it. |

When the worker finishes, it passes that file's path to firstmate.
That handoff is the only thing the worker sends about its messages.

### 1.6 The work log and mechanical resolution

The work log is written only by firstmate, one entry per handled message.

| Field | Required | Meaning |
| --- | --- | --- |
| `message_id` | Yes | The `id` of the message in the message log. |
| `task_id` | Yes | The task the message belongs to, copied from the message record. |
| `handled_by` | Yes | `worker` when the entry came from a worker's message-work log, `firstmate` when firstmate handled the message itself. |
| `handled_time` | Yes | When the message was handled, copied from the worker's entry or set by firstmate. |
| `action` | Yes | For a worker entry, the worker's own `action`; for a firstmate entry, one of `relayed`, `relaunched_and_relayed`, `recorded_as_answer`, `attached_to_task`, `reopened_task`, `closed_duplicate` or `escalated_to_captain`. |
| `note` | No | The worker's note, or firstmate's. |
| `source_file` | For worker entries | The message-work log path the worker passed. |
| `resolved_time` | Yes | When firstmate appended this entry. |

When a worker's path arrives, firstmate runs a script over it, with no judgement.
For every entry whose `message_id` matches a message in the message log, the script appends one work-log entry.
An entry naming no message in the log is skipped, and a message that already has a work-log entry gets no second one.
Firstmate writes its own entries only for messages it handled itself, with one of the actions listed above.

### 1.7 Unhandled, rotation and retention

A message is unhandled exactly when the message log holds it and the work log has no entry for its `id`.
Unhandled messages are firstmate's concern in the logs, and section 3 is how firstmate handles them.

Log rotation is a regular process run by the Go listener.
Each rotation moves the current message log and work log aside, and every message with a work-log entry rotates out with its entry.
Every unhandled message is carried into the new message log with its `original_time` kept.
Rotated files are kept for 7 days and then deleted.
Section 7.2 names the contradiction between this rotation and the single-writer rule for the work log.

### 1.8 Retiring the polling adapters

Each existing polling adapter is removed once push works for its source, one source at a time.

The only case that would reintroduce a shim is a source with no page we author - something that can only emit its own protocol.
None exists today.
Do not build for it speculatively; note it if one appears.

## 2 The rulings

### 2.1 Rulings of 2026-09-30 (history)

These are kept verbatim as history.
Rulings 6, 7 and 9 in the list below are superseded by section 2.2, as section 5 records.

Verbatim, captain 2026-09-30: "the command prompt in claude ai should not be invloved with this. the workers spawnwed by the backend should be interactring with a fristmate copy that shares the session data but not the session process. Polling is a nightmare model that introduces timeouts. it's the worst. yes go is cleaner and has threads and go routines. it's suprior for this purpose. we know exactly what the datastream is and can even create and forward http headers and set cookies for session state so this go process is going to really soak up lots of events for firstmate. it could even could run a firstmate task prioritizer in parrallel."

Verbatim, captain 2026-09-30: "docstrap should send http events not poll. so should lavish. it should use webworkers."

Verbatim, captain 2026-09-30: "at that point you don't even need to have the proxy."

Verbatim, captain 2026-09-30: "the go routine is the proxy into the fork of claude code, and gets a fm2 folder someplace"

1. The main conversation is out of the loop.
   No prompt content reaches the Claude command prompt.
   Only dispatch decisions reach it, and only where a decision genuinely needs the supervisor.
2. The language is Go.
   Threads and goroutines, and the captain considers it superior for this purpose.
   This is a deliberate departure from the standing Python, FastAPI and Pydantic backend stack, recorded as such rather than drifted into.
3. Not polling.
   "Polling is a nightmare model that introduces timeouts. it's the worst."
4. Pages send HTTP events, from a Web Worker, for both sources.
5. There is no proxy on the source side.
6. The proxy is on the far side: the goroutine proxies into a fork of Claude Code, and that side gets its own `fm2` folder.
7. Workers talk to a firstmate copy that shares the session data but not the session process.
8. The datastream is known, so the server may create and forward HTTP headers and set cookies for session state.
9. The server may run a firstmate task prioritizer in parallel.

### 2.2 Rulings of 2026-10-12 (history)

These are kept verbatim as history.
Items 2, 4, 5, 6 and 10 of the summary list below are superseded in part by section 2.3, as section 5 records.

The captain questioned the separate copy and the combine stage, verbatim: "q144 yes but the plan needs another review. That plan sounds baroque in this section: "Go server, **which combines them by area and dispatches workers to a separate firstmate copy.**". Why is this necessary ? Can firstmate get messages in addtion to the messages from the claude code cli? why would a copies be needed? Why do feedback items need to be sorted? Does the feedback for each message type related to tasks or projects already? What are the cases that would need to be organized mecanically to insure that firstmate gets the right context for each message?"

Firstmate's answer, which the captain then ruled on, was that firstmate already takes non-chat input as durable records plus wakes, that the supervision host already keeps routine wakes out of the main conversation so no separate copy is needed, and that each event already carries its owner, so nothing needs sorting by area.

Q145 (one small push endpoint into firstmate's existing intake, no separate firstmate copy, no combine-by-area stage), Q147 (endpoint accepts only local events with a per-session token) and Q148 (remove each polling adapter once push works for its source), verbatim: "Q145 - Q148 but not 146 are all yes and don't need to go to docstrap."

Q146, verbatim: "Q146 retries needs to be limited , and should write to logs that firstmate will read later rather than retry. The web worker to go server should be local network, but for this new log/journal with docstrap kept for bookeeping and part of cleanup, between the go process and firstmate, could be done by a shared file or unix socket. The log/journal should cover when worker idle or are stopped by firstmate. Firstmate primary is the only agent that uses the journal so when those messages fail firstmate gets timely notices and can restart these workers and relay messages to them. The go process can access and know about firstmate book keeping read-only so that it can mecahnically organize 1-6. The go process only has full crud for messages and management of the log. Reason though message events step by step and see if it makes sense given the cases and the edge cases."

Q149, verbatim: "Q149. decide: journal file or socket. updates to a file can be watched by inotify so both are not needed. jorunal file items are checked off by id as they are handled by firstmate and eventually are garbage collected."

Q150, verbatim: "Q150. No If go is down this should simply call back to the spa to notify the user that the listen unit needs a restart."

Q151, verbatim: "Q151. Right, only on the local machine machine."

Check-off by id, verbatim: "No fristmate can write to a second file. i said "By id" so the resolution is that each entry in the message log has an entry in the work log. On garbage collection the old files are rotated and then unmatched results are appended to mmessage logs with an original_time field preserved."

1. One small push endpoint feeds firstmate's existing intake; there is no separate firstmate copy and no combine-by-area stage (Q145).
2. Retries are limited, and what fails is written to the journal for firstmate to read rather than retried (Q146).
3. The listener-to-firstmate path is a file watched with inotify, not a socket (Q149).
4. Journal entries are checked off by id as firstmate handles them and are then garbage collected, with docstrap kept for bookkeeping and cleanup (Q146, Q149).
5. The journal covers workers going idle or being stopped by firstmate, and firstmate primary is its only user (Q146).
6. The listener reads firstmate's bookkeeping read-only to organize cases 1 through 6, and has full create, read, update and delete only over messages and the message log (Q146).
7. When the listener is down, the page notifies the user that it needs a restart (Q150).
8. The endpoint accepts only local events with a per-session token, and binds to this machine only (Q147, Q151).
9. Each polling adapter is removed once push works for its source (Q148).
10. The journal is two files: the listener alone writes the message log, firstmate alone writes the work log with one entry per handled message keyed by that message's id, and garbage collection rotates both and carries every unmatched message forward into the new message log with its `original_time` preserved (check-off ruling).
11. Rulings 2, 3, 4, 5 and 8 of 2026-09-30 stand, and ruling 1 stands for prompt content: entries reach firstmate primary as durable records and wakes, never through the Claude command prompt.

### 2.3 Rulings after the 2026-10-12 revision, through 2026-10-13

These are verbatim and in order.

Verbatim, captain: "lots fo confusion. first messages are not the same as the jorunal. i thought there was a clear way in the original propsal for messags to go to workers. the journal is not for workers it's for firstmate to follow up on jobs that go unhandled. what firstmate does with the journal is up to firstmate. that means7.3 is a voided issue but it also means we do not have a shared understanding of the plan for the system. as fro many of these other details they just require a sensible option. most of those other deatils don't matter."

Verbatim, captain 2026-10-13, confirming the model that messages go from the Go listener to the owning worker, that the journal is firstmate's follow-up list of unhandled messages, and that firstmate decides what to do with each: "Q152. It's the model except for b keeping handled entries in the active log. old logs can be kept for 7 days but log resolution and rotation are a more regular process and might be managed by the go listening unit. the concerns for firstmate in the log are the unhandeled messages. can you now reason about the various cases and how firstmate might handle them or not on it's side?"

Verbatim, captain 2026-10-13, on the record shape: "those logs for those entries i noted aimed at the message log should be in the work log, or maybe they are just not needed. having the files writen by mulitple processes is not a smart design."

Verbatim, captain 2026-10-13: "For resoltion when workers finish they should just pass a message-work log file path to firstmate. when firstmate gets this it should mechanically resolve the message and work logs."

Verbatim, captain 2026-10-13: "NO owner is no context and is crazy. i have no idea where you got that. try to get unconfused and re-reason with each **structured message and work log having resonable and required fields please*."

Verbatim, captain 2026-10-13, about mutable `delivered_time`, `acknowledged_time` and `unhandled_reason` fields on a message: "these parts really go against the idea that these files are append only write once and resolved at garbage collection time by firstmate"

Verbatim, captain 2026-10-13: "Q157 yes" - confirming the design that section 1 and section 3 now state.

1. Messages go from the listener to the worker of the task they belong to; the logs are not for workers.
2. The logs are firstmate's follow-up list, and firstmate's concern in them is the unhandled messages; what firstmate does with each is firstmate's decision.
3. Each file has one writer, and every record is written once and never edited.
4. Every message names its task; a message without an owning task is rejected at intake, so there is no "no owner" case.
5. A worker passes its message-work log path to firstmate when it finishes, and firstmate resolves it mechanically.
6. Old logs are kept for 7 days, and rotation is a regular process run by the Go listener.
7. Details the captain did not rule on take a sensible option, recorded in section 7 rather than asked.

## 3 Firstmate's handling of an unhandled message

An unhandled message always names its task, so firstmate handles it by that task's current state.
A message carries no extra authority: deploying, merging or discarding work still needs the captain's plain go, whatever the message says.

| Task state | Firstmate's handling | Work-log action |
| --- | --- | --- |
| Worker not running, task held for the captain, message is an answer | Record it as the captain's answer, relaunch the worker, and relay the message. | `recorded_as_answer`, then `relaunched_and_relayed` |
| Task queued, not started | Attach the message to the task's notes and start nothing early. | `attached_to_task` |
| Worker died mid-task | Relaunch once and relay the message; if the relaunch fails, escalate to the captain. | `relaunched_and_relayed` or `escalated_to_captain` |
| Task closed, message repeats the recorded answer | Close it as a duplicate. | `closed_duplicate` |
| Task closed, message carries new captain words | Reopen the task or start a follow-up, and tell the captain. | `reopened_task` |
| Worker running and busy | Leave it; the worker handles it in turn. | None yet |
| Worker running, idle, message unread | Re-ring the doorbell once. | None yet |
| Worker running and stuck | Interrupt the worker and relay the message directly. | `relayed` |

A message delivered to a running worker stays unhandled in the logs until that worker finishes and passes its message-work log, so the three running rows are the normal state of work under way, not a fault.
When a worker died mid-task and left a message-work log, firstmate resolves that file first, so messages it already handled are not relayed again.

When firstmate is offline, unhandled messages wait in the message log.
Session start presents them oldest first by `original_time`.
When several unhandled messages arrive at once, each is handled under its own task, and anything that needs the captain is batched into one captain-facing message.

## 4 Why one small listener is enough

The 2026-09-30 shape justified one large server by cross-source combining: a Lavish prompt and a docstrap answer about the same subsystem arrive as two unrelated wakes, and only a server seeing both could merge them.
The captain's 2026-10-12 questions showed that argument does not carry the weight it was given.
Every message already names the task it belongs to, so the listener's remaining work is mechanical - checking fields, checking the task, dropping repeats, keeping `seq` order, delivering, and rotating - and firstmate's own judgment handles the follow-up a combiner would have guessed at.
A smaller listener also removes the second mutating session that the separate copy would have risked.

## 5 The supersession trail - do not propose these again

The design changed several times as the captain refined it, and each change removed something a fresh reader would otherwise suggest.

1. A proxy listener per source was specified, then removed.
   The refinement was his: "the same server should be able to listen to lavish, and docstrap and contexualize the two but it might take a proxy listener for each one in order to change the protocol or port they are working on."
   The proxy existed for exactly one reason, which was to change the protocol or port each tool works on and translate it into a common shape.
   Once the page we author became the sender it emits the common shape directly, so there is nothing left to translate, and he removed it: "at that point you don't even need to have the proxy."
2. Polling on the wire was accepted, then ruled out.
   The accepted position was that polling could be removed from firstmate but not necessarily from the wire: where a tool exposes only a poll API something must still poll it, and what changed was that the poll moved into a goroutine where a timeout costs nothing and never reaches a conversation.
   Page push superseded that entirely.
3. The proxy reappeared on the far side, then was removed with the copy.
   On 2026-09-30 the goroutine was to proxy into a fork of Claude Code with its own `fm2` home, where workers would talk to a firstmate copy sharing session data but not the session process.
   Q145 removed the copy, the fork, and the `fm2` home.
4. FastAPI was the named delivery surface, and is now Go.
   See ruling 2 of 2026-09-30, which records the stack departure deliberately so it is not mistaken for drift.
5. A taskwriter with four jobs was specified, then reduced to checking the task.
   The captain's original framing, verbatim: "when you use lavish i think we need an inverted shape, a process that is a listner that refers the prompts to a contexualized firstmate taskwriter then sorts & prioritizes and combinse those prompt by area or catagory and dispaches them. You can't just run lavish or docstrap those require a server of sorts."
   Its four jobs were to contextualize a prompt against the fleet, sort and prioritize, combine by area or category, and dispatch.
   Q145 removed combining, his question "Why do feedback items need to be sorted?" removed sorting, and ruling 9 of 2026-09-30, the parallel prioritizer, went with them.
   Contextualizing survives only as the intake check of `task_id` against firstmate's records, and dispatch is delivery to the task's own worker.
   The docstrap input class from that framing still stands as the kind of event a docstrap page sends: "Use background workers to drive a fastapi plugin loop for firstmate that deleivers results from docstrap as posts events, in the context of standard documentation improvement prompts, like check off all sections that have/do not have nuance errors. That feeds to provide hints for targeted questions."
6. A socket between the listener and firstmate was considered, then ruled out.
   Q146 allowed a shared file or a unix socket, and Q149 chose the file because inotify already gives a file wake-on-change, so both are not needed.
7. Queueing in the page was considered, then ruled out.
   Q150 ruled that when the listener is down the page tells the user it needs a restart instead of holding events for later.
8. A journal that carried messages to firstmate for relay to workers was written, then ruled out.
   The 2026-10-12 revision had firstmate read every message from the journal and relay it through steering; the captain ruled that messages go to workers directly and the logs are only firstmate's follow-up list.
9. Worker idle and stop entries in the journal were written, then ruled out.
   They existed to tell firstmate that a message could not reach a worker; with delivery done by the listener and unhandled defined as no work-log entry, they are not needed, and the confirmation question about them was voided.
10. Six mechanical cases classified by the listener were written, then ruled out.
    The "no owner" case was never a ruling and is impossible, because a message without a known task is rejected at intake.
    Duplicates and ordering are intake rules in section 1.4, bursts need no rule because each message is handled under its own task, and closed tasks and stopped workers are firstmate's handling in section 3.
11. Mutable fields on a message record were proposed, then ruled out.
    `delivered_time`, `acknowledged_time` and `unhandled_reason` would have made the listener or firstmate edit records after writing them; every record is written once.
12. Several writers to one file were proposed, then ruled out.
    Each file has one writer, and a worker's handled messages reach the work log only through firstmate's mechanical resolution of the worker's own file.

## 6 Two constraints the build must design around

These are surfaced constraints, not objections to the design.

6.1 A browser tab is not a durable sender.
The existing process-event inbox captures a result to disk before anything acts on it, and a page that is closed mid-send cannot retry.
The captain's rulings answer this by making the loss visible rather than hiding it: retries are limited, the listener answers success only once the record is durable, and an unreachable listener produces a restart notice to the user (Q146, Q150).
Do not add a page-side queue to paper over it; Q150 ruled that out.

6.2 The listener must not become a second mutating session over the home.
`bin/fm-lock.sh` holds a per-home lock, and `AGENTS.md` section 3 is explicit that a lock-refused session must not spawn, steer, merge, drain the wake queue, or perform any other fleet mutation.
The listener reads firstmate's records only to check `task_id` and fill `project`, and writes only the message log and its rotated files.
Delivering a message to a worker is the one action outside that, granted by the captain's 2026-10-13 rulings; it rings the doorbell the worker already answers and never spawns, relaunches, interrupts or stops a worker.
Any later feature that has the listener write a firstmate record, act on a worker's lifecycle, or touch the backlog crosses that boundary and needs the captain's word.

## 7 Defaults chosen, and one contradiction

7.1 The defaults.
The captain ruled that the remaining details "just require a sensible option," so these are chosen, not open.

1. The listener issues a token per page load, and the page sends it with every message.
2. The listener binds to this machine only.
3. The message log, the work log and their rotated files live in docstrap's data directory.
4. Firstmate's watcher watches the message log with inotify; nothing in firstmate uses inotify today, so this is new watcher code.
5. A worker learns of a new message through the doorbell it already answers.
6. A worker keeps its message-work log in its task's data directory, and that file goes with the task's cleanup.
7. The page makes three retries with increasing delay over about thirty seconds before showing the restart notice.
8. The listener rotates once a day.

7.2 The contradiction.
Section 1.7 has the Go listener run rotation, which moves firstmate's work log aside, so a second process writes to a file whose only writer is firstmate.
The captain's ruling that "having the files writen by mulitple processes is not a smart design" forbids that.
The captain's ruling about mutable fields also describes the files as "resolved at garbage collection time by firstmate," while Q152 and Q157 have the Go listener run log resolution and rotation.
Rotation by the listener and one writer per file cannot both hold for the work log as written, and this note does not choose between them.

## 8 What already exists, so none of it gets rebuilt

Firstmate already owns the durable-record-plus-wake intake that firstmate's watch on the message log feeds.
`bin/fm-procevent.sh` arms a long-poll against a server-backed tool, captures the result durably, and delivers it as a check wake, with `bin/fm-procevent-lavish.sh`, `bin/fm-procevent-docstrap.sh` and `bin/fm-procevent-when.sh` as its adapters.
The `process-event-sources` skill owns the arming commands, the durability boundary and the handled-acknowledgement contract, and each script's own header owns its exact mechanics; read those rather than any restatement.

The steering inbox and doorbell a worker already answers are owned by `bin/fm-send.sh` and `bin/fm-task-inbox-lib.sh`.
The task identities the listener checks against already exist too: a Lavish board's owner task from its `--for` arm, and a docstrap question's held task through `bin/fm-captain-hold.sh bind`.
The listener replaces the Lavish and docstrap polling adapters one source at a time (Q148); the `when`, quota and remote-reply adapters are not page sources and are outside this design.
