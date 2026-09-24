let total_ids=105
let mechanical_properties=16
let mechanical_companions=32
let mechanical_ids=48
let handwritten_ids=57
let invariants=
  [ "mechanical descriptors are contained values, never public native handles"
  ; "functions, archives, libraries, linked functions, arrays, and pipeline creation are handwritten"
  ; "all object inputs are live and belong to the pipeline device"
  ; "buffer and color attachment indices are unique and in range"
  ; "copied labels cannot alias mutable caller storage"
  ; "constructor NSError and every partial retain unwind on failure"
  ; "pipeline state retains native dependencies through command completion" ]
