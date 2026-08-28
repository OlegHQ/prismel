# Phase 5 final facade qualification

This gate records the native-only final facade. It requires the public render
target to be exactly `Native`, rejects Headless and Web variants, and checks
that the retired Headless/Web providers and the old Wap-aware Runtime owner
candidate fixtures are absent.

The gate is intentionally structural. Native rendering correctness and
lifetime qualification remain covered by their dedicated Metal tests; this
fixture prevents deleted target candidates from being silently reintroduced.
