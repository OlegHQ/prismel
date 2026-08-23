# Metal4 encoder/resource integration continuation

This stage adds typed buffer-copy, residency, drawable wait/signal, and render
compiler-task helpers. Buffer arithmetic is overflow-safe and validates an
operation-specific alignment before native entry; source/destination devices
must match. Shared CAML conversion must additionally compare every object to
the queue/encoder device because `MTLDrawable` does not expose one uniformly.

The raw compiler path retains compiler+descriptor until its callback fires,
roots completion once, returns an owned compiler-task handle, and unwinds on
synchronous submission failure. Encoded buffers/encoder are retained through
command completion. Native and mock tests cover null objects, misalignment,
pre-validation non-retention, native copy failure, and compiler callback unwind.
