let getter name = "method:-[CAMetalLayer " ^ name ^ "]"
let callable_ids = List.sort_uniq String.compare
  ([ "device"; "drawableSize"; "pixelFormat"; "framebufferOnly"
   ; "maximumDrawableCount"; "allowsNextDrawableTimeout"
   ; "displaySyncEnabled"; "presentsWithTransaction" ] |> List.map getter
   @ [ "method:-[CAMetalLayer wantsExtendedDynamicRangeContent]"
     ; "method:-[CAMetalLayer setWantsExtendedDynamicRangeContent:]"
     ; "property:CAMetalLayer:wantsExtendedDynamicRangeContent"
     ; "method:-[CAMetalDrawable layer]"; "property:CAMetalDrawable:layer" ])
let validate () = if List.length callable_ids <> 13 then failwith "presentation layer13 drift"
let () = validate ()
