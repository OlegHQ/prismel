# Pipeline113 ownership integration shard

This isolated code pairs the existing 44 mechanical method/property IDs with
typed render/compute descriptor materializers for the 63 ownership IDs.
Required vertex/compute functions and device reject null; fragment functions,
linked functions, vertex/stage descriptors and archives remain explicitly
nullable where the SDK permits it. Array elements reject null before native
entry.

Shared integration must translate exact handle kinds, reject destroyed and
cross-device functions/libraries/archives/descriptors, retain descriptor
children through asynchronous compilation, return owned pipeline/reflection
handles with distinct kinds, and unwind every retain, callback root, temporary
descriptor and `NSError` on synchronous or asynchronous failure. The raw
functor tests both render and compute partial-retain unwind. No inventory ID is
promoted by this shard.
