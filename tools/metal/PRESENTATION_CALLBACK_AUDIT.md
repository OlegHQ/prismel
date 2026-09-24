# Presentation callback safety audit

Scope: commits `df55fd4` and `57c4da5`, independently inspected against the
current presentation implementation.  This evidence does not promote any SDK
inventory entry.

## Confirmed blocker

`command_buffer_add_handler` allocates and registers a generational global root
before installing an Objective-C completion block.  The root is removed only
when that block fires or when handler installation throws.  The safe layer
then rejects `Command_buffer.destroy` whenever `callback_handlers <> 0`.

Consequently, a recording command buffer with a registered handler has no
abandon/cancel path.  If it is never committed, its block never fires and the
malloc allocation, OCaml global root, callback closure, and values reachable
from the closure remain retained indefinitely.  A finalizer cannot repair this:
the root itself can keep the graph reachable, and the native block has no
destructor that unregisters the root.

Required fix: give each native registration an exactly-once cleanup token with
two terminal paths: `fire` after scheduled/completed notification, or `cancel`
when an unsubmitted command buffer is explicitly destroyed/finalized.  Both
paths must atomically claim the token, remove the generational global root while
holding the OCaml runtime, and free the token.  The safe layer must permit
destroy/cancel while still recording.  It must continue rejecting destruction
of a submitted, nonterminal command buffer unless native ownership proves the
callbacks remain alive independently.

## Callback thread and exception findings

The callback registers a foreign Metal thread, acquires the OCaml runtime,
uses `caml_callback_exn`, removes the root, releases the runtime, and unregisters
only when this invocation registered the thread.  That ordering is sound for a
one-shot Metal handler.  The current safe wrapper also catches user exceptions,
so an exception cannot unwind through Objective-C++.

The cleanup token must preserve these properties.  In particular, cancellation
performed by an OCaml primitive already holding the runtime must not call
`caml_acquire_runtime_system` recursively.  Native block destruction on an
arbitrary thread may release Objective-C ownership, but must not touch an OCaml
root without thread registration and the runtime lock.

## Presentation ownership and one-shot findings

The safe layer flips `presentation_scheduled` only after the typed native call
succeeds and retains the drawable through the command buffer.  All public
operations are initial-domain guarded, so the mutable one-shot flag is not a
data race.  Duplicate presentation is rejected before a second native call.

The retained drawable/resource graph is released at terminal status or wait,
and on destruction of an unsubmitted callback-free command buffer.  This is
adequate once callback cancellation is added.  Keep the one-shot state even
when an unsubmitted command buffer is cancelled: a drawable already passed to
Metal must not be silently recycled.

## Adversarial executable model

`test_binding_presentation_callback_lifecycle.ml` checks 0 through 10,000
handlers on both terminal paths, repeated completion, destroy while submitted,
and duplicate presentation.  It specifies the required cardinality: every root
is consumed exactly once by either fire or cancel, never both.
