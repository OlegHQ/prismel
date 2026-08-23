# IO/counter/blit-pass111 ownership integration shard

This shard complements 38 generated scalar IDs with materializers and typed
CAML hooks for the 73 ownership IDs. It validates counter sample counts and
indices, overflow-safe destination ranges, required IO command/file/buffer
handles, and nullable counter attachments before native entry.

Shared hookup must enforce exact handle kinds, same-device IO queue/resources/
events/counters, recording-only encoding, queue capacity and single commit/
cancel transitions. Destination/source/event resources stay retained until the
completion callback fires. Callback roots and every partial retain unwind once
on submission failure or exception. The raw mock verifies command-resource and
callback failure unwind. This isolated shard does not promote inventory.
