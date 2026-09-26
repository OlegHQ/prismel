type boundary = Smooth.boundary =
  | Smooth_free
  | Smooth_unshared
  | Smooth_group_boundary

let run_checked = Smooth.run
