# Metal4-190 exact integration coverage after compute-owner stage

The authoritative partition is 39 mechanical and 151 ownership IDs. Commits
`74df5d7` and `4ceac5b` safely cover 8 ownership selectors. The complete
`MTL4ComputeCommandEncoder` closure contains 32 callable ownership methods.
One selector (buffer-to-buffer copy) overlaps the earlier stage. Also, the
compiler helper prepared in `4ceac5b` is absent from the authoritative pinned
manifest and therefore is useful code but contributes zero coverage. The exact
authoritative union after this stage is **38/151 ownership IDs**;
**113 ownership IDs remain**. `Binding_metal4_integration_coverage` contains the
exact sorted covered and remaining lists and its test freezes these counts.

The generated native shard supplies typed direct calls for all 32 compute-owner
methods. The handwritten validator covers liveness, same-device resources,
overflow-safe aligned buffer ranges, and overflow-safe 3D texture regions.
Object-kind conversion, operation-specific alignment, texture layout, indirect
range, acceleration scratch sizing and command-state retention remain mandatory
at shared hookup; generation alone does not promote these IDs.

The deterministic 32-wrapper native shard digest is
`fa0658c2187c59accdbcd01f6ffbe70d1b671c32dbe3307e4ec14f8a53857f2e`.
