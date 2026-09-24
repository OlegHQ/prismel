type t = {
  value : int
    [@sop.default 3] [@sop.min 1] [@sop.max 8] [@sop.hard_min 1];
}
[@@deriving sop_params]
