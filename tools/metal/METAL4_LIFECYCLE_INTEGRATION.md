# Authoritative Metal4 lifecycle190 integration shard

This shard targets the authoritative `2c7e165` manifest and its 39 mechanical /
151 ownership partition; the superseded `387895c` batch remains non-countable.
Typed helpers cover allocator-backed begin, queue event waits, encoder fence
waits and overflow-safe ranges. CAML hooks demand exact queue/buffer/allocator/
event handle kinds.

The raw state model enforces Initial → Recording → Ended → Committed → Complete,
rejects encoding outside Recording, retains allocator and encoded resources,
roots completion exactly once, and releases everything on submission failure or
completion. Shared hookup must additionally enforce same-device resources,
encoder-specific range/stride/alignment rules, drawable/residency ownership,
pipeline compilation callback roots and owned pipeline/compiler-task handles.
No inventory promotion occurs here.
