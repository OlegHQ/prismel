type gate = { name : string; required : bool }
let gate name = { name; required = true }
let expected_ids = 125
let gates =
  List.map gate
    [ "inventory-count-and-digest"; "typed-selector-static-compilation"
    ; "pixel-format-colorspace-roundtrip"; "resize-and-drawable-loss"
    ; "next-drawable-timeout"; "render-pass-attachment-exactness"
    ; "present-completion-retention"; "10000-frame-no-handle-delta"
    ; "autorelease-and-sanitizer"; "availability-matrix" ]
