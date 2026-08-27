# Runtime B5 compatibility delta

`Runtime_next_compat.api_coverage` is the machine-checked map from the current
public `lib/runtime/runtime.mli`. The focused test reads that signature and
fails on an added, removed, duplicated, or unclassified value/type.

Direct mappings preserve the legacy name and string/result convention. Two
high-level values are deliberately adapted: `selected_target` exposes invalid
configuration as a result, and `drain_web_events` replaces a transient dropped
path with an owned `File_uploaded` name/byte payload. The target-neutral event
and audio types retain constructor semantics without Wap aliases.

The exact B5 deletion allowlist is five entries: raw-renderer `present` and the
four `Runtime.Private` selection/pacing/scaling helpers. No raw SDL window,
renderer, flag, Wap, Runtime, or Prismel value crosses the facade.
