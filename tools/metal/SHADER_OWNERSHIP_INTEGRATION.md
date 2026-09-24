# Shader157 ownership integration shard

This shard complements the 54 generated value/scalar IDs with typed ownership
materializers for the 103 graph/object IDs. Function-node names and graph
outputs are required; graph/node/archive/attribute arrays reject null elements.
The existing safe graph validator remains authoritative for duplicate IDs,
unknown edges, cycles, destroyed objects and cross-device references.

Shared hookup must translate exact function/library/archive/node/graph/
reflection/argument-encoder/stage-descriptor handle kinds, run cycle and device
validation before native construction, retain the complete graph through async
library compilation, root callbacks exactly once, and unwind roots, retained
children, partial graphs and `NSError` on every synchronous/asynchronous error.
The raw functor tests node failure and callback submission failure unwind. This
isolated shard does not promote inventory.
