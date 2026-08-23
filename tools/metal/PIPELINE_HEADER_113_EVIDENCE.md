# Conventional pipeline header qualification (113 IDs)

Exact sorted-ID digest: `ca20299ddb844da5bd51c664b71b1d33e21491f8db75346144d170a96f098a0c`.

The batch selects current unreviewed declarations in `MTLRenderPipeline.h` and
`MTLComputePipeline.h`, excluding the six mesh/tile owners already claimed by
the mesh batch and every acceleration/function-table method already claimed by
the acceleration batch. It contains 113 unique IDs: 44 mechanical/property
companion IDs, 63 ownership-bearing IDs, and 6 metadata IDs.

Mechanical methods generate statically typed direct Objective-C calls. Object
references, arrays, errors, reflections, descriptor graphs, and constructors
remain handwritten. The safe model retains descriptor children, rejects
cross-device functions before native entry, requires a vertex function before
materialization, retains the descriptor through pipeline lifetime, and makes
release idempotent. This isolated qualification does not promote inventory.

Exact sorted-ID intersections at qualification time:

| Existing batch | IDs | Intersection |
|---|---:|---:|
| resource manifest | 100 | 0 |
| corrected presentation manifest (67 mechanical / 58 lifecycle) | 125 | 0 |
| shader graph manifest | 157 | 0 |
| mesh/tile pipeline | 105 | 0 (excluded owners) |
| acceleration operations | 115 | 0 (excluded selector/signature tokens) |
| classic render encoder | 106 | 0 (different owner) |
| layout headers | 102 | 0 (different headers) |
| corrected device qualification | 94 | 0 (different owner/header) |

The generated artifact contains 27 unique callable methods representing the 44
mechanical method/property IDs. Its SHA-256 is
`1552bfd54024912bb85b49d90301afb7bc03e931e030e962db2385c4bbc87f5d`.
