# Docstrap answers through the existing intake - and the set-aside Go listener

First decided by the captain in conversation on 2026-09-30 as a Go HTTP event listener, and filed here at his instruction: "go http listner into firstmate fork notes."
Revised to the captain's rulings of 2026-10-12 and of 2026-10-13, which shaped that listener into a message log, worker message-work logs and a firstmate work log.
Revised again on 2026-10-13, when the captain set the Go listener design aside by Q159 and adopted the smaller design in section 2.

This is a record of rulings, not a proposal and not a plan.
The point of writing it down is that it stops being re-litigated.
Sections 1 and 2 are the current decision.
Section 3 keeps every verbatim ruling as history, section 4 summarizes the set-aside listener design, and section 5 records what was considered and discarded, because a reader who sees only the final state will propose the discarded options again.

Nothing under `fork-notes/` is loaded at session start, which is why this file is here rather than in `AGENTS.md`, a skill, or `data/captain.md`.
The captain was explicit that nothing should clog what every session loads.

## 1 The Go listener design is set aside, and why

The Go listener is not being built.

1.1 Firstmate's existing path already delivers board answers to workers.
It writes each one into the worker's steering inbox, the worker confirms it by moving the message into `handled/`, an unacknowledged message is re-rung, and a stuck one is detected and escalated.
The listener design rebuilt that delivery and confirmation a second time.

1.2 The only real problem was docstrap's 5-second poll.
Lavish already has its own result path, and nothing else in the design needed a new process.

1.3 The listener could not reach a worker or firstmate without writing firstmate's files.
Delivering to a worker means writing its steering inbox, and telling firstmate means writing into firstmate's intake, so a separate listener process either becomes a second writer over firstmate's home or does nothing that firstmate cannot do itself.

1.4 Docstrap's event model differs from Lavish's.
Docstrap saves edits continuously to local storage and has no submit buttons, while a Lavish board sends a per-round event from a per-question button that docstrap will not adopt.
What docstrap does expect is one moment that says the answers are done.
Fusing the two event models into one listener would conflict, and the captain noted they might conflict under the Go model too.

## 2 The adopted design

1. Docstrap offers one "answers done" prompt per document or questions page.
   There are no per-question buttons and no submit buttons.
2. Pressing it makes docstrap's server write one notice into firstmate's watched intake, naming the project and the document.
3. On that notice, the existing docstrap bridge reads the answer store once, without consuming it.
4. The bridge routes each answer to its held task through the existing intake, which delivers it to the worker through the steering inbox as it does today.
5. The 5-second poller is removed.
6. Lavish keeps its own result path, unchanged.

There is no Go process, no message log, no worker message-work log and no work log.
The notice is the only new thing firstmate's intake receives, and everything after it runs on paths firstmate already has, listed in section 6.

## 3 The rulings

### 3.1 Rulings of 2026-09-30 (history)

These are kept verbatim as history.
Rulings 6, 7 and 9 in the list below are superseded by section 3.2, as section 5 records.

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

### 3.2 Rulings of 2026-10-12 (history)

These are kept verbatim as history.
Items 2, 4, 5, 6 and 10 of the summary list below are superseded in part by section 3.3, as section 5 records.

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

### 3.3 Rulings after the 2026-10-12 revision, through 2026-10-13

These are kept verbatim as history, and the whole listener design they confirmed is set aside by section 3.4.

Verbatim, captain: "lots fo confusion. first messages are not the same as the jorunal. i thought there was a clear way in the original propsal for messags to go to workers. the journal is not for workers it's for firstmate to follow up on jobs that go unhandled. what firstmate does with the journal is up to firstmate. that means7.3 is a voided issue but it also means we do not have a shared understanding of the plan for the system. as fro many of these other details they just require a sensible option. most of those other deatils don't matter."

Verbatim, captain 2026-10-13, confirming the model that messages go from the Go listener to the owning worker, that the journal is firstmate's follow-up list of unhandled messages, and that firstmate decides what to do with each: "Q152. It's the model except for b keeping handled entries in the active log. old logs can be kept for 7 days but log resolution and rotation are a more regular process and might be managed by the go listening unit. the concerns for firstmate in the log are the unhandeled messages. can you now reason about the various cases and how firstmate might handle them or not on it's side?"

Verbatim, captain 2026-10-13, on the record shape: "those logs for those entries i noted aimed at the message log should be in the work log, or maybe they are just not needed. having the files writen by mulitple processes is not a smart design."

Verbatim, captain 2026-10-13: "For resoltion when workers finish they should just pass a message-work log file path to firstmate. when firstmate gets this it should mechanically resolve the message and work logs."

Verbatim, captain 2026-10-13: "NO owner is no context and is crazy. i have no idea where you got that. try to get unconfused and re-reason with each **structured message and work log having resonable and required fields please*."

Verbatim, captain 2026-10-13, about mutable `delivered_time`, `acknowledged_time` and `unhandled_reason` fields on a message: "these parts really go against the idea that these files are append only write once and resolved at garbage collection time by firstmate"

Verbatim, captain 2026-10-13: "Q157 yes" - confirming the listener design that section 4 summarizes.

1. Messages go from the listener to the worker of the task they belong to; the logs are not for workers.
2. The logs are firstmate's follow-up list, and firstmate's concern in them is the unhandled messages; what firstmate does with each is firstmate's decision.
3. Each file has one writer, and every record is written once and never edited.
4. Every message names its task; a message without an owning task is rejected at intake, so there is no "no owner" case.
5. A worker passes its message-work log path to firstmate when it finishes, and firstmate resolves it mechanically.
6. Old logs are kept for 7 days, and rotation is a regular process run by the Go listener.
7. Details the captain did not rule on take a sensible option rather than a question.

### 3.4 Rulings of 2026-10-13 setting the listener aside

Verbatim, captain 2026-10-13, on Q158 (drop the Go listener for docstrap server pushes into the existing intake): "That simpler design might be better but note that docstrap does not have a bunch of button and continuously saves edits to local storage.  It has a different event model. Fusing the two clearly will conflict but maybe they also would under the go model. There are no submit buttons in the docstrap model. The lavish question answer as jankny per question button that docstrap won't be adopting. on the other hand docstrap does expact a notice or prompt that the answers are done."

Verbatim, captain 2026-10-13, on Q159 (adopt: docstrap's single "answers done" notice triggers the existing bridge's one non-consuming read of the answer store, through the existing intake; the 5-second poller is removed; the Go listener design is set aside, with the note recording why): "Q159 yes".

1. The Go listener design is set aside (Q159).
2. Docstrap's single "answers done" notice triggers the existing bridge's one non-consuming read of the answer store, through the existing intake (Q159).
3. The 5-second poller is removed (Q159).
4. Docstrap has no submit buttons and will not adopt Lavish's per-question button, but expects a notice or prompt that the answers are done (Q158).

## 4 The set-aside listener design, in short

This summarizes what Q157 confirmed and Q159 set aside, so it is not proposed again.
Pages pushed HTTP events from a Web Worker to a Go listener bound to this machine, with a token per page load.
The listener checked each message's required fields and its task against firstmate's records, wrote it once to a message log it alone wrote, dropped repeated ids, and delivered messages to the owning task's worker in sequence order.
Each worker kept its own message-work log of the messages it handled and passed that file's path to firstmate when it finished.
Firstmate resolved that file by script into a work log it alone wrote, and a message with no work-log entry was unhandled and followed up by the owning task's state.
The listener rotated both logs regularly, kept old logs for 7 days, and carried unhandled messages forward with their original time.
Its one unresolved contradiction was that rotation by the listener moved firstmate's work log, making a second writer of a file meant to have one.

## 5 The supersession trail - do not propose these again

1. A proxy listener per source was specified, then removed once the pages we author emitted the common shape themselves: "at that point you don't even need to have the proxy."
2. Polling on the wire was accepted, then ruled out by page push, and the docstrap poll is now replaced by the "answers done" notice.
3. A far-side proxy into a fork of Claude Code with its own `fm2` home and a firstmate copy was removed by Q145.
4. FastAPI was the named delivery surface, then Go by ruling 2 of 2026-09-30, and now neither, because no server is built.
5. A taskwriter that contextualized, sorted, prioritized, combined and dispatched was reduced by Q145 and the captain's sorting question, and is gone with the listener.
6. A socket between the listener and firstmate was ruled out by Q149 in favour of a file.
7. Queueing in the page was ruled out by Q150.
8. A journal that carried messages to firstmate for relay, worker idle and stop entries, six mechanical cases including "no owner", mutable fields on message records, and several writers to one file were each ruled out on 2026-10-13, as section 3.3 records.
9. The Go listener itself, with its message log, worker message-work logs and work log, was set aside by Q159, for the reasons in section 1.

## 6 What already exists, so none of it gets rebuilt

`bin/fm-procevent-docstrap.sh` is the existing docstrap bridge: it reads the captain's answers out of the answer store docstrap already writes and routes them into the keyed-answer intake, and its own header owns its exact mechanics.
`bin/fm-procevent.sh` captures results durably and delivers them as check wakes, and the `process-event-sources` skill owns the arming commands, the durability boundary and the handled-acknowledgement contract.
A docstrap question's held task is bound through `bin/fm-captain-hold.sh bind`.
The steering inbox, its `handled/` confirmation, re-ring and stuck escalation are owned by `bin/fm-send.sh` and `bin/fm-task-inbox-lib.sh`.
Lavish keeps its own result path through `bin/fm-procevent-lavish.sh`.
