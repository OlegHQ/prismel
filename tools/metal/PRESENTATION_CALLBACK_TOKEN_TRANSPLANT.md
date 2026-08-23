# Callback token transplant notes

`presentation_callback_token_prototype.mm` is an isolated reference algorithm,
not a second binding implementation.  Integration should place equivalent
state beside each registered native handler and retain shared ownership in both
the Objective-C block and the command-buffer registration table.

- Registration creates the OCaml root and token, then records the token only
  after native handler installation succeeds. Installation failure removes the
  root synchronously.
- The block calls `fire`; recording-command-buffer destruction/finalization
  calls `cancel_runtime_held` for every recorded token before releasing its
  native handle.
- The atomic terminal claim makes fire versus cancel exactly once. Losing paths
  only release their shared native token reference and never touch the root.
- `fire` registers the foreign thread, acquires the runtime, invokes with
  `caml_callback_exn`, removes the root, releases the runtime, and conditionally
  unregisters the thread, in that order.
- `cancel_runtime_held` is entered from an OCaml primitive/finalizer and removes
  the root directly; it must not acquire the already-held runtime recursively.
- Submitted command buffers retain their registrations until native terminal
  callbacks fire. Destruction while submitted remains rejected.

The stress executable races fire and cancel for 10,000 independently rooted
registrations. It requires exactly one winner per registration, callback count
equal to fire wins, valid foreign-thread runtime ordering, and zero live roots
and tokens after all block/owner references are released.
