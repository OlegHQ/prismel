# Mesh/tile ownership integration shard

This isolated shard complements the existing 48 contained scalar/helper IDs
with typed materialization paths for the 57 ownership/lifecycle IDs. Native
object fields use their concrete Metal protocol/class types; required mesh/tile
functions reject null, optional stage functions remain nullable, array elements
reject null, and indexed descriptor arrays validate the Metal limits (31 buffer
slots, 8 color attachments) before native entry.

The eventual shared bridge must translate every incoming handle with an exact
kind (`Function`, `Binary_archive`, `Dynamic_library`, `Linked_functions`,
`Pipeline_buffer_descriptor`, or `Color_attachment_descriptor`), verify all
objects share the target device, root dependencies until pipeline completion,
and release every partial retain plus `NSError` on all failure paths. The raw
functor's failure test proves deterministic unwind. This shard does not expose
or classify any ID by itself.
