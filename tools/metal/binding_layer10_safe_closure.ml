let callable_ids =
  [ "method:-[CAMetalLayer developerHUDProperties]"
  ; "method:-[CAMetalLayer preferredDevice]"
  ; "method:-[CAMetalLayer residencySet]"
  ; "method:-[CAMetalLayer setDeveloperHUDProperties:]"
  ; "property:CAMetalLayer:developerHUDProperties"
  ; "property:CAMetalLayer:preferredDevice"
  ; "property:CAMetalLayer:residencySet" ]

let type_ids =
  [ "class:CAMetalLayer"; "protocol:CAMetalDrawable" ]

let opaque_abi_ids = [ "record:_CAMetalLayerPrivate" ]

let promotable_ids = callable_ids @ type_ids @ opaque_abi_ids

let validate () =
  let expected =
    [ "class:CAMetalLayer"
           ; "method:-[CAMetalLayer developerHUDProperties]"
           ; "method:-[CAMetalLayer preferredDevice]"
           ; "method:-[CAMetalLayer residencySet]"
           ; "method:-[CAMetalLayer setDeveloperHUDProperties:]"
           ; "property:CAMetalLayer:developerHUDProperties"
           ; "property:CAMetalLayer:preferredDevice"
           ; "property:CAMetalLayer:residencySet"
           ; "protocol:CAMetalDrawable"
           ; "record:_CAMetalLayerPrivate" ]
    |> List.sort String.compare
  in
  if List.length callable_ids <> 7 || List.length type_ids <> 2
     || opaque_abi_ids <> [ "record:_CAMetalLayerPrivate" ]
     || List.sort_uniq String.compare promotable_ids <> expected
  then failwith "CAMetalLayer10 exact closure drift"

let () = validate ()
