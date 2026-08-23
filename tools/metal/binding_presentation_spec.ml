type declaration =
  { id : string; kind : string; owner : string option; name : string
  ; signature : string; classification : string }

let owners =
  [ "CAMetalDrawable"; "CAMetalLayer"; "MTLRenderPassDescriptor"
  ; "MTLCommandBuffer" ]

let selected declaration =
  declaration.classification = "unreviewed"
  && Option.fold ~none:false ~some:(fun owner -> List.mem owner owners)
       declaration.owner
  && not (String.starts_with ~prefix:"API_UNAVAILABLE" declaration.signature)

let expected_count = 125
let expected_digest = "82710196daca14152ffc09bf9079d55ce1cd0e8dbdcfe9fbd4fb93055e680d92"
