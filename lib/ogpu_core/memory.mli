type storage = Shared | Private | Upload | Readback
type access = Read | Write | Read_write
type descriptor = { size:int64; alignment:int64; storage:storage; max_allocations:int }
type heap
type allocation
type mapped
type interval = { offset:int64; length:int64 }
val create : device:Handle.device -> descriptor -> (heap,Error.t) result
val destroy : heap -> unit
val allocate : device:Handle.device -> heap -> size:int64 -> alignment:int64 -> (allocation,Error.t) result
val free : allocation -> (unit,Error.t) result
val allocation_interval : allocation -> interval
val begin_alias : allocation -> (unit,Error.t) result
val end_alias : allocation -> (unit,Error.t) result
val validate_allocation : Handle.device -> allocation -> (unit,Error.t) result
val map_range : allocation -> access:access -> offset:int64 -> length:int64 -> (mapped,Error.t) result
val unmap : mapped -> (unit,Error.t) result
val mapped_active : mapped -> bool
val mapped_interval : mapped -> (interval,Error.t) result
val with_mapped_range : allocation -> access:access -> offset:int64 -> length:int64 -> (mapped -> 'a) -> ('a,Error.t) result
val free_intervals : heap -> interval list
val live_intervals : heap -> interval list
val metadata_count : heap -> int
