let emit_ocaml_contract () =
  String.concat "\n"
    [ "type drawable_result = Acquired of drawable | Temporarily_unavailable"
    ; "val resize : layer -> width:int -> height:int -> (unit, error) result"
    ; "val next_drawable : layer -> (drawable_result, error) result"
    ; "val present : command_buffer -> drawable -> (unit, error) result" ]

let emit_native_contract () =
  String.concat "\n"
    [ "// generated typed selectors; never objc_msgSend"
    ; "id<CAMetalDrawable> drawable = [layer nextDrawable];"
    ; "[command_buffer presentDrawable:drawable];"
    ; "// completion owner retains layer/drawable/texture until callback" ]
