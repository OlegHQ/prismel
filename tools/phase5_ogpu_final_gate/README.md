# OGPU final-facade integration qualification

This deterministic, non-benchmark gate closes the locally runnable portions of
O2/O5/O7/O9 by composing the authoritative OGPU mock/state machines with
Raster2 and the installed `prismel_next_api` headless/web facade.

Covered evidence includes generational stale handles and idempotent destroy,
wrong-pass rejection, fence validation, submission-owned deferred release,
surface resize invalidation/timeout/device loss, fault-atomic mock allocation,
exact one/four-domain command and Raster2 ordering, and final Scene/Scene3
execution and teardown at frame labels 1, 2, 60, and 600.

It does not execute a native GPU, measure performance, validate Metal driver
behavior, or promote native benchmark and external-machine gates.
