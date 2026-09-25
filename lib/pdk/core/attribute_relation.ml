type t =
  | Identity of int
  | Constant_zero of int
  | Direct of int array
  | All of { source_count : int }
  | Csr_identity of { offsets : int array }
  | Csr_map of { offsets : int array; indices : int array }

let[@inline always] count = function
  | Identity count | Constant_zero count -> count
  | Direct values -> Array.length values
  | All _ -> 1
  | Csr_identity { offsets } | Csr_map { offsets; _ } -> Array.length offsets - 1

let[@inline always] first relation destination = match relation with
  | Identity _ | Constant_zero _ | Direct _ -> 0
  | All _ -> 0
  | Csr_identity { offsets } | Csr_map { offsets; _ } -> offsets.(destination)

let[@inline always] last relation destination = match relation with
  | Identity _ | Constant_zero _ | Direct _ -> 1
  | All { source_count } -> source_count
  | Csr_identity { offsets } | Csr_map { offsets; _ } -> offsets.(destination + 1)

let[@inline always] source relation destination slot = match relation with
  | Identity _ -> destination
  | Constant_zero _ -> 0
  | Direct values -> values.(destination)
  | All _ | Csr_identity _ -> slot
  | Csr_map { indices; _ } -> indices.(slot)

let[@inline always] incidence_count = function
  | Identity count | Constant_zero count -> count
  | Direct values -> Array.length values
  | All { source_count } -> source_count
  | Csr_identity { offsets } | Csr_map { offsets; _ } ->
      offsets.(Array.length offsets - 1)

let[@inline always] flat_first relation destination = match relation with
  | Identity _ | Constant_zero _ | Direct _ -> destination
  | All _ -> 0
  | Csr_identity { offsets } | Csr_map { offsets; _ } -> offsets.(destination)

let[@inline always] flat_last relation destination = match relation with
  | Identity _ | Constant_zero _ | Direct _ -> destination + 1
  | All { source_count } -> source_count
  | Csr_identity { offsets } | Csr_map { offsets; _ } -> offsets.(destination + 1)

let[@inline always] source_flat relation destination slot = match relation with
  | Identity _ -> destination
  | Constant_zero _ -> 0
  | Direct values -> values.(destination)
  | All _ | Csr_identity _ -> slot
  | Csr_map { indices; _ } -> indices.(slot)
