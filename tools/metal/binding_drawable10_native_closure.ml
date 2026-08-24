let mechanical_ids =
  [ "method:-[MTLDrawable drawableID]"
  ; "method:-[MTLDrawable presentedTime]"
  ; "property:MTLDrawable:drawableID"
  ; "property:MTLDrawable:presentedTime" ]

let effect_ids =
  [ "method:-[MTLDrawable addPresentedHandler:]"
  ; "method:-[MTLDrawable presentAfterMinimumDuration:]"
  ; "method:-[MTLDrawable presentAtTime:]"
  ; "method:-[MTLDrawable present]" ]

let metadata_ids = [ "protocol:MTLDrawable"; "typedef:MTLDrawablePresentedHandler" ]

let () =
  let ids = mechanical_ids @ effect_ids @ metadata_ids in
  if List.length mechanical_ids <> 4 || List.length effect_ids <> 4
     || List.length metadata_ids <> 2
     || List.length (List.sort_uniq String.compare ids) <> 10
  then invalid_arg "Drawable10 native closure drift"
