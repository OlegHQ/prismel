open Metal

let fail format = Printf.ksprintf failwith format
let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)
let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> fail "unexpected error: %s" (Format.asprintf "%a" pp_error error)
  | Ok _ -> fail "expected rejection"

let run () =
  let device = get (Device.system_default ()) in
  let layer = get (Metal_layer.create device (Metal_layer.default ~width:8 ~height:8)) in
  expect Unsupported
    (Metal_layer.configure layer
       { (Metal_layer.default ~width:8 ~height:8) with
         format = Texture.Rgba8_unorm
       });
  get
    (Metal_layer.configure layer
       (Metal_layer.default ~width:16 ~height:8))
