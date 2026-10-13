# The Go HTTP event listener - a decided architecture

First decided by the captain in conversation on 2026-09-30, and filed here at his instruction: "go http listner into firstmate fork notes."
Revised to the captain's rulings of 2026-10-12, which replaced the separate firstmate copy and the combine-by-area stage with one small push endpoint into firstmate's existing intake.

This is a record of rulings, not a proposal and not a plan.
The captain settled the shape himself, and the point of writing it down is that it stops being re-litigated.
Section 7 is the only part that is still unsettled, and it is marked as such; sections 1 through 4 are decided, except where a sentence is explicitly marked for the captain's confirmation.
Section 5 records what was considered and discarded, because a reader who sees only the final state will propose the discarded options again.

Nothing under `fork-notes/` is loaded at session start, which is why this file is here rather than in `AGENTS.md`, a skill, or `data/captain.md`.
The captain was explicit that nothing should clog what every session loads.

## 1 The decided shape

Pages push HTTP events from a Web Worker to one Go listener on this machine, the listener writes a message log, and firstmate primary reads that log and records each message it handles in its own work log.

    Lavish board page -> Web Worker -> HTTP POST -> |
                                                    | Go listener (127.0.0.1 only,
    docstrap surface  -> Web Worker -> HTTP POST -> | per-session token)
                                                    |   reads firstmate records read-only
                                                    |   resolves owner, classifies cases 1-6
                                                    v
                                              message log  -- inotify -->  firstmate primary
                                              (listener writes,            handles each entry,
                                               entries by id)              writes work log by id

There is no separate firstmate copy, no `fm2` home, no combine-by-area stage, and no prioritizer.
The Claude command prompt is not in the loop; the journal arrives as a durable record plus a wake, the same way firstmate already takes every other non-chat input.

1.1 The page side.
Each page sends from a Web Worker so it never blocks the page's UI thread.
The Lavish artifact is HTML we author, and docstrap's widget surfaces are pages rendered by docstrap, which the captain owns, so neither tool's server needs a push feature added and no upstream dependency blocks the build.
The page retries a failed send a limited number of times.
When the listener is still unreachable after those retries, the page tells the user that the listener needs a restart.
Nothing is queued in the page or anywhere else for later delivery.

1.2 The listener.
The listener binds to this machine only, and it accepts only local events that carry a valid per-session token.
It reads firstmate's records read-only, which is how it resolves each event's owner and mechanically classifies cases 1 through 6 in section 3.
It alone has full create, read, update and delete over the messages it receives and over the message log.
It never writes into firstmate's records, a worker's steering inbox, or the backlog.

1.3 The journal.
The journal is two files, each with exactly one writer, and there is no socket.
The message log is written only by the listener, and firstmate watches it with inotify.
Every message-log entry has an id.
Firstmate primary is the message log's only reader.
The work log is written only by firstmate: as it handles a message it appends one work-log entry keyed by that message's id, which is what checking off by id means.
A message is handled exactly when the work log holds an entry with its id.
On garbage collection the old files are rotated, and every message-log entry with no matching work-log entry is appended to the new message log with its `original_time` field preserved, so unhandled messages survive rotation and handled ones are dropped.
Docstrap is kept for bookkeeping and as part of that cleanup.
The journal also records when a worker goes idle or is stopped by firstmate, so firstmate gets timely notice of messages that could not reach a worker and can restart that worker and relay the messages to it through its ordinary steering path.

1.4 Retiring the polling adapters.
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

### 2.2 Rulings of 2026-10-12

The captain questioned the separate copy and the combine stage, verbatim: "q144 yes but the plan needs another review. That plan sounds baroque in this section: "Go server, **which combines them by area and dispatches workers to a separate firstmate copy.**". Why is this necessary ? Can firstmate get messages in addtion to the messages from the claude code cli? why would a copies be needed? Why do feedback items need to be sorted? Does the feedback for each message type related to tasks or projects already? What are the cases that would need to be organized mecanically to insure that firstmate gets the right context for each message?"

Firstmate's answer, which the captain then ruled on, was that firstmate already takes non-chat input as durable records plus wakes, that the supervision host already keeps routine wakes out of the main conversation so no separate copy is needed, and that each event already carries its owner, so nothing needs sorting by area.
The cases that still need mechanical handling are the six in section 3.

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

## 3 The six cases and the event walk-through

The listener does not contextualize, sort, prioritize or combine.
Every event already names its owner: a Lavish board is armed for an owner task, and a docstrap question's `<document-id>:<label>` maps to its held task through firstmate's private binding.
What remains is six cases that the listener classifies mechanically from firstmate's records, so that firstmate reads each entry with the right context already attached.

1. No owner: the event names no task firstmate knows.
2. Closed task: the owner resolves, but that task is finished or cleaned up.
3. Duplicate: the same event arrives more than once.
4. Ordering of rounds: rounds from one source arrive out of order or with a gap.
5. Worker not running: the owner task's worker is idle, stopped, or gone.
6. Bursts across projects: many events from several projects arrive close together.

### 3.1 One event, step by step

1. The page's Web Worker builds the event with a page-assigned event id, the source identity, the round number, and the per-session token.
   The event id is fixed when the event is built and reused on every retry of that event.
2. The Web Worker posts it to the listener on the local machine.
3. The listener checks the token and refuses the event when it is missing or wrong, without journaling it.
4. The listener looks the event id up in its seen-id set.
   A hit is case 3: it answers success and journals nothing new.
5. The listener resolves the owner by reading firstmate's records read-only.
   No owner is case 1, and an owner whose task is finished or cleaned up is case 2; either way the entry is still journaled, carrying that classification, and firstmate decides whether it becomes new intake, reopens work, or is dropped.
6. The listener compares the round with the rounds it has journaled for that source.
   A round older than one already journaled, or one that leaves a gap, is case 4; the entry is journaled with its round and that classification, and nothing is reordered or discarded, so firstmate reads the rounds in round order.
7. The listener reads the owner's worker state from firstmate's records.
   A worker that is idle, stopped, or gone is case 5; the entry is marked so firstmate knows it must restart the worker and relay the message.
8. The listener appends the entry with its own journal id, the event id, the project, the owner, the round, and the case classification, makes the write durable, and only then answers the page with success.
9. Firstmate's inotify watch on the journal turns the append into a wake.
10. Firstmate reads every message-log entry with no matching work-log entry, handles each through its ordinary intake and steering paths, and appends one work-log entry per handled message keyed by its id.

Case 6 needs no step of its own.
Every entry already carries its project, so a burst is many independent entries, and one wake may cover several appends; firstmate reads all unhandled entries in one pass and may group them by project for reading, but nothing merges them.

### 3.2 Worker idle and stop entries

When a worker that owns a source goes idle, or is stopped by firstmate, the listener sees the change in firstmate's records and journals it as its own entry.
That entry is what gives firstmate timely notice that later messages for that owner cannot reach a live worker.
The listener never delivers anything to a worker itself; restarting the worker and relaying the waiting messages through firstmate's ordinary steering path is firstmate's job.
Firstmate's inference, for the captain's confirmation: the listener journals only idle and stop transitions for workers that own a push source, not for every worker in the fleet.

### 3.3 Edge cases

1. Duplicate after retry.
   The listener journals the entry and makes it durable, but the success answer is lost, so the page retries with the same event id.
   Step 4 finds the id in the seen-id set, answers success, and journals nothing, so firstmate sees the event once.
   The page treats only a success answer as delivery, and the listener answers success only after the entry is durable, so a page closed after success loses nothing.
   A page closed before success is the limited-retry loss the captain accepted in Q146 and Q150, and the user sees the restart notice whenever the listener was the cause.
2. Out-of-order rounds.
   Round 3 arrives before round 2 because a retry delayed round 2.
   Both are journaled, round 2 carries the case 4 classification, and firstmate reads the rounds of a source in round order rather than journal order.
3. Listener restart.
   The seen-id set and the per-source round record are held in memory, and on start the listener rebuilds both by reading the message log, handled and unhandled entries alike.
   Rotation drops handled entries, so garbage collection must not rotate away an entry until it is well past the page's limited retry window, so that a retry can never arrive after the entry that would have caught it is gone.
   Carried-forward entries keep their `original_time`, so the rebuild and firstmate both still see when each message first arrived.
   Events sent while the listener is down are refused, the page retries a limited number of times, and the user is told the listener needs a restart; nothing is queued.
4. Firstmate offline.
   Entries keep arriving in the message log and wait with no matching work-log entry.
   No inotify watch is running while firstmate is down, so session start must read every message-log entry that has no work-log entry as part of its startup input, and that read is the only thing that catches them.
   A rotation while firstmate is down loses nothing, because every unmatched entry is carried forward.
5. Check-off by id while the listener owns the message log.
   Settled by the captain's check-off ruling: firstmate never edits the message log, and writes its own work log instead.
   Each handled message gets one work-log entry keyed by its id, so each message-log entry has its match in the work log.
   That keeps each file with one writer and avoids a race between a firstmate write and a listener write to the same file.
   A message stays unhandled until its id appears in the work log, so a crash between handling and the work-log append only causes firstmate to see that message again, never to lose it.

## 4 Why one small endpoint is enough

The 2026-09-30 shape justified one large server by cross-source combining: a Lavish prompt and a docstrap answer about the same subsystem arrive as two unrelated wakes, and only a server seeing both could merge them.
The captain's 2026-10-12 questions showed that argument does not carry the weight it was given.
Firstmate already receives non-chat input as durable records plus wakes, the supervision host already keeps routine wakes away from the main conversation, and every event already names the task or project it belongs to.
So the remaining work is mechanical - owner resolution and the six cases - and firstmate's own judgment handles what a combiner would have guessed at.
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
   Q145 removed the copy, the fork, and the `fm2` home: the listener writes a message log and firstmate primary reads it.
4. FastAPI was the named delivery surface, and is now Go.
   See ruling 2 of 2026-09-30, which records the stack departure deliberately so it is not mistaken for drift.
5. A taskwriter with four jobs was specified, then reduced to owner resolution.
   The captain's original framing, verbatim: "when you use lavish i think we need an inverted shape, a process that is a listner that refers the prompts to a contexualized firstmate taskwriter then sorts & prioritizes and combinse those prompt by area or catagory and dispaches them. You can't just run lavish or docstrap those require a server of sorts."
   Its four jobs were to contextualize a prompt against the fleet, sort and prioritize, combine by area or category, and dispatch.
   Q145 removed combining, his question "Why do feedback items need to be sorted?" removed sorting, and ruling 9 of 2026-09-30, the parallel prioritizer, went with them.
   Contextualizing survives only as the mechanical owner resolution and case classification in section 3, and dispatch is firstmate's ordinary intake.
   The docstrap input class from that framing still stands as the kind of event a docstrap page sends: "Use background workers to drive a fastapi plugin loop for firstmate that deleivers results from docstrap as posts events, in the context of standard documentation improvement prompts, like check off all sections that have/do not have nuance errors. That feeds to provide hints for targeted questions."
6. A socket between the listener and firstmate was considered, then ruled out.
   Q146 allowed a shared file or a unix socket, and Q149 chose the file because inotify already gives a file wake-on-change, so both are not needed.
7. Queueing in the page was considered, then ruled out.
   Q150 ruled that when the listener is down the page tells the user it needs a restart instead of holding events for later.

## 6 Two constraints the build must design around

These are surfaced constraints, not objections to the design.

6.1 A browser tab is not a durable sender.
The existing process-event inbox captures a result to disk before anything acts on it, and a page that is closed mid-send cannot retry.
The captain's rulings answer this by making the loss visible rather than hiding it: retries are limited, the listener answers success only once the entry is durable, and an unreachable listener produces a restart notice to the user (Q146, Q150).
Do not add a page-side queue to paper over it; Q150 ruled that out.

6.2 The listener must not become a second mutating session over the home.
`bin/fm-lock.sh` holds a per-home lock, and `AGENTS.md` section 3 is explicit that a lock-refused session must not spawn, steer, merge, drain the wake queue, or perform any other fleet mutation.
The listener stays clear of that boundary because it only reads firstmate's records and only writes its own messages and the message log (Q146); the work log it may read is firstmate's own record.
Any later feature that has the listener write a firstmate record, steer a worker, or touch the backlog crosses that boundary and needs the captain's word.

## 7 Still open - do not resolve these in passing

The earlier list's items 1, 3, 4 and 5 are settled or moot, and item 2 is mostly settled.

1. Delivery guarantee from a page closed mid-send: settled by Q146 and Q150 as limited retries and a user-facing restart notice, with no queueing.
2. Authentication of a page-originated POST: settled in principle by Q147 and Q151 as local-only events with a per-session token on a listener bound to this machine; how the token is issued to the page and what bounds a session remain open, as item 7.1 below.
3. Whether `bin/fm-procevent-lavish.sh` and `bin/fm-procevent-docstrap.sh` are retired: settled by Q148, each is removed once push works for its source.
4. What "shares the session data" means across two homes: moot under Q145, because there is no second home.
5. Whether `fm2` is a secondmate or a new role: moot under Q145, because there is no `fm2`.

The three further items from the earlier design conversation are also settled or moot.
The listener is a long-running process, which Q150's restart notice presumes.
Whether combining happens before or after contextualizing is moot, because there is no combining (Q145).
Whether it writes briefs or proposes them is moot, because it writes only journal entries and firstmate does intake (Q146).
Which fork of Claude Code it speaks to is moot under Q145.

What remains open after these rulings:

7.1 How the per-session token reaches the page, and what a session is: a firstmate session, a listener run, or one page load.

7.2 Who runs garbage collection, and when.
The mechanism is settled: rotate the old files and carry every unmatched message forward with its `original_time` preserved.
What is open is what runs it and how it is triggered, given that docstrap's collector is not built (`fork-notes/lifecycles-and-docstrap.md` section 2.4) and its roadmap design covers docstrap metadata rows only.
Rotation must also not break the one-writer rule: the new message log is written by the listener, and the new work log by firstmate.
How long a handled entry is kept before rotation drops it is open; section 3.3(3) sets the floor of well past the page's retry window.

7.3 The confirmation marked in section 3.2: that only workers owning a push source get idle and stop entries.

7.4 Where the message log and the work log live, and how firstmate's watcher gains the inotify trigger; nothing in firstmate uses inotify today.

7.5 How many retries the page makes and over what interval; the rulings say only that retries are limited.

## 8 What already exists, so none of it gets rebuilt

Firstmate already owns the durable-record-plus-wake intake the journal feeds.
`bin/fm-procevent.sh` arms a long-poll against a server-backed tool, captures the result durably, and delivers it as a check wake, with `bin/fm-procevent-lavish.sh`, `bin/fm-procevent-docstrap.sh` and `bin/fm-procevent-when.sh` as its adapters.
The `process-event-sources` skill owns the arming commands, the durability boundary and the handled-acknowledgement contract, and each script's own header owns its exact mechanics; read those rather than any restatement.

The owner identities the listener resolves against already exist too: a Lavish board's owner task from its `--for` arm, and a docstrap question's held task through `bin/fm-captain-hold.sh bind`.
The listener replaces the Lavish and docstrap polling adapters one source at a time (Q148); the `when`, quota and remote-reply adapters are not page sources and are outside this design.
