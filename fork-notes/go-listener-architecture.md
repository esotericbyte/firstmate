# The Go HTTP event listener - a decided architecture

Decided by the captain in conversation on 2026-09-30, and filed here at his instruction: "go http listner into firstmate fork notes."

This is a record of rulings, not a proposal and not a plan.
The captain settled the shape himself across several refinements the same day, and the point of writing it down is that it stops being re-litigated.
Nothing here is open for redesign.
Section 7 is the only part that is still unsettled, and it is marked as such; everything in sections 1 through 4 is decided.
Section 5 records what was considered and discarded, because a reader who sees only the final state will propose the discarded options again.

Nothing under `fork-notes/` is loaded at session start, which is why this file is here rather than in `AGENTS.md`, a skill, or `data/captain.md`.
The captain was explicit that nothing should clog what every session loads.

## 1 The decided shape

Pages push HTTP events to one Go server, which contextualizes across every stream it receives, prioritizes, combines by area, and dispatches.

    Lavish board page    -> Web Worker -> HTTP POST -> |
                                                       | Go server: contextualize across
    docstrap surface     -> Web Worker -> HTTP POST -> | both streams, prioritize,
                                                       | combine by area, dispatch
                                                       |
                                            dispatched workers -> firstmate copy
                                            (shares session data, not session process)

One server, one endpoint shape, N sources.
No proxy on the source side, no poller anywhere, no adapter in the path, and the Claude command prompt is not in the loop at all.

The sending is done from a Web Worker so it never blocks the page's UI thread.

The part worth not losing is why this needs no change to either tool's server.
The Lavish artifact is HTML we author, and docstrap's widget surfaces are pages rendered by docstrap, which the captain owns.
The Web Worker is therefore embedded in a page we control, so neither Lavish's server nor docstrap's needs a push feature added, and no upstream dependency blocks the build.
That is what makes this better than negotiating a webhook out of a tool.

The only case that would reintroduce a shim is a source with no page we author - something that can only emit its own protocol.
None exists today.
Do not build for it speculatively; note it if one appears.

## 2 The rulings

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

## 3 The taskwriter has four jobs

The captain's original framing, verbatim: "when you use lavish i think we need an inverted shape, a process that is a listner that refers the prompts to a contexualized firstmate taskwriter then sorts & prioritizes and combinse those prompt by area or catagory and dispaches them. You can't just run lavish or docstrap those require a server of sorts."

The taskwriter is the server, and its four jobs are distinct.

1. Contextualize.
   A raw prompt from a Lavish board or a docstrap answer arrives with no fleet context.
   The taskwriter resolves it against the project registry, work already under way, the backlog, and the open captain calls, so the resulting task is written against what is actually true rather than against the prompt alone.
2. Sort and prioritize.
   Arrival order is not priority order.
   A prompt that unblocks held work outranks one that opens a new thread.
3. Combine by area or category.
   Several prompts touching one subsystem should become one well-scoped task, not several competing ones.
   This is the part that most directly reduces the churn the captain is objecting to.
4. Dispatch.
   Only then, and as normal firstmate intake with a brief.

The input shape for docstrap is standard documentation-improvement prompts, from the captain's earlier framing the same day: "Use background workers to drive a fastapi plugin loop for firstmate that deleivers results from docstrap as posts events, in the context of standard documentation improvement prompts, like check off all sections that have/do not have nuance errors. That feeds to provide hints for targeted questions."
His example prompt is "check off all sections that have/do not have nuance errors", and those results feed hints for targeted questions.
The FastAPI delivery surface named in that quote is superseded by ruling 2; the background-worker shape and the prompt class are not.

## 4 Why one server, and why that argument carries the whole design

Cross-source contextualizing is the point, and it is the thing the current design structurally cannot do.

Today a Lavish prompt and a docstrap answer about the same subsystem arrive as two unrelated wakes, and nothing can notice they concern the same thing.
One server seeing both streams can combine them; two independent wake paths never can.
That is the strongest argument for this architecture and it should be stated as such rather than assumed.

## 5 The supersession trail - do not propose these again

The design changed several times as the captain refined it, and each change removed something a fresh reader would otherwise suggest.

1. A proxy listener per source was specified, then removed.
   The refinement was his: "the same server should be able to listen to lavish, and docstrap and contexualize the two but it might take a proxy listener for each one in order to change the protocol or port they are working on."
   The proxy existed for exactly one reason, which was to change the protocol or port each tool works on and translate it into a common shape.
   Once the page we author became the sender it emits the common shape directly, so there is nothing left to translate, and he removed it: "at that point you don't even need to have the proxy."
2. Polling on the wire was accepted, then ruled out.
   The accepted position was that polling could be removed from firstmate but not necessarily from the wire: where a tool exposes only a poll API something must still poll it, and what changed was that the poll moved into a goroutine where a timeout costs nothing and never reaches a conversation.
   Page push superseded that entirely.
   There is no polling anywhere in the design, on the wire or off it.
3. The proxy reappeared on the far side.
   It was not removed, it moved: the goroutine is the proxy into a fork of Claude Code, with its own `fm2` home.
4. FastAPI was the named delivery surface, and is now Go.
   See ruling 2, which records the stack departure deliberately so it is not mistaken for drift.

## 6 Two constraints the build must design around

These are surfaced constraints, not objections to the design.

6.1 A browser tab is not a durable sender.
The thing being replaced was durable: the existing process-event inbox captures a result to disk before anything acts on it.
A page can be closed mid-send, and a page that is gone cannot retry.
Do not quietly regress that durability while moving the send into the page.
The delivery guarantee itself is open, and is recorded in section 7.

6.2 The per-home session lock means `fm2` must not silently become a second mutating session over one home.
`bin/fm-lock.sh` holds a per-home lock, and `AGENTS.md` section 3 is explicit that a lock-refused session must remain read-only and must not spawn, steer, merge, drain the wake queue, or perform any other fleet mutation.
A separate `fm2` folder is a separate home, so it takes its own lock and the contention the earlier shape would have caused does not arise - the lock boundary and the data-sharing boundary are now different things, which is the point of giving it its own folder.
What survives as a constraint is the failure the lock exists to prevent.
Whatever "shares the session data" turns out to mean concretely, it must not end with two mutating sessions over one home, and that is precisely where the risk would come back.

## 7 Still open - do not resolve these in passing

Five items are unsettled.
They are the captain's to settle, and the firstmate convention is to put them to him as lettered plans rather than as questions.

1. Delivery guarantee from a page that can be closed mid-send: retry, queue in the worker, or accept loss.
   The Lavish adapter's known loss limitation, recorded in the `process-event-sources` skill, is the same class of problem and may already have a settled answer to reuse.
2. Authentication of a page-originated POST, given the captain's note that the server may create and forward HTTP headers and set cookies for session state.
3. Whether the existing `bin/fm-procevent-lavish.sh` and `bin/fm-procevent-docstrap.sh` adapters are retired by this, or kept as a fallback path for surfaces with no page of their own.
4. What "shares the session data" means concretely across two homes.
   The candidates are that `fm2` reads the main home's `data/` directly, that the data lives in a third location both homes point at, or that it is synchronised.
   Each has a different answer for who may write, and the whole of constraint 6.2 turns on that.
   The existing secondmate model already solves a related problem - a persistent isolated `FM_HOME` with inherited local material pushed into it - so `secondmate-provisioning` may hold a reusable answer rather than a new mechanism.
5. Whether `fm2` is a secondmate in the existing sense or a genuinely new role.
   If it can be a secondmate, most of the provisioning, liveness and restart machinery already exists.

Three further items from the earlier design conversation were never settled and are not superseded, so they are still open too: whether the taskwriter is a long-running process or a pass that runs per event, whether combining happens before or after contextualizing, and whether it writes briefs directly or proposes them for firstmate to approve.
Which fork of Claude Code, and what the goroutine speaks to it over, is also open.

## 8 What already exists, so none of it gets rebuilt

Firstmate already owns the listener half, and the captain's premise that these tools require a server of sorts is exactly what it was built for.
`bin/fm-procevent.sh` arms a long-poll against a server-backed tool, captures the result durably, and delivers it as a check wake, with `bin/fm-procevent-lavish.sh`, `bin/fm-procevent-docstrap.sh` and `bin/fm-procevent-when.sh` as its adapters.
The `process-event-sources` skill owns the arming commands, the durability boundary and the handled-acknowledgement contract, and each script's own header owns its exact mechanics; read those rather than any restatement.

The gap this architecture fills sits between capture and dispatch, where there is nothing today.
Each captured result becomes its own wake, handled singly, in arrival order.
The taskwriter in section 3 is that missing middle, and whether the existing adapters survive alongside it is open item 7.3.
