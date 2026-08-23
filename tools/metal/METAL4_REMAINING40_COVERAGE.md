# Metal4 callable remaining-40 closure

This stage adds exactly **40 newly callable authoritative ownership IDs**:

- the five formerly blocked compute IDs: tensor copy, build acceleration,
  both refit variants, and compacted-size write;
- 10 render-pipeline binary-function descriptor methods with five property
  companions, plus two binary-function methods with two companions (**20**);
- command-buffer debug, residency, timestamp and counter-resolution methods
  (**6**); and
- render-encoder draw, mesh, indirect-command-buffer, memory and timestamp
  methods (**9**).

The exact tensor schema is an OCaml `int64 array` of rank at most 16. The exact
Metal4 buffer-range schema is an owned `(Buffer, offset, length)` triple,
validated against the buffer length and converted to `gpuAddress + offset`.
The triangle acceleration descriptor retains its source buffer in a dedicated
owned native state, and command-buffer retention keeps that state plus every
encoded resource alive through completion.

Because the prior 62/151 authoritative union already counted all 32 generated
compute IDs, only the other 35 IDs enlarge that union: authoritative ownership
coverage becomes **97/151**, with **54 IDs remaining**. All 40 IDs enlarge the
callable ABI because the five compute operations had previously been explicit
schema blockers.
