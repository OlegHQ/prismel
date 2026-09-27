let () =
  let open Param in
  let field ?primary ?vec3 () = field ~name:"x" ?primary ?vec3
    ~kind:(floating ~min:(-10.) ~max:10. ()) ~default:1.
    ~get:Fun.id ~set:(fun value _ -> value) () in
  let plain = schema ~name:"position" ~default:1. [field ()] in
  let grouped = schema ~name:"position" ~default:1. [field ~primary:true ~vec3:("center",0) ()] in
  let p = List.hd (view plain 2.) and g = List.hd (view grouped 2.) in
  assert (not p.primary && p.vec3 = None);
  assert (g.primary && g.vec3 = Some ("center",0) && g.current = Float_value 2.);
  assert (key plain 2. = key grouped 2. && cook_key plain 2. = cook_key grouped 2.);
  let grouped, effects = apply_all grouped 1. ["x", Float_value 3.] |> Result.get_ok in
  assert (grouped = 3. && effects.cook);
  let invalid f = try ignore (f ()); false with Invalid_argument _ -> true in
  assert (invalid (fun () -> field ~vec3:("",0) ()));
  assert (invalid (fun () -> field ~vec3:("center",3) ()));
  assert (invalid (fun () -> Param.field ~name:"x" ~vec3:("center",0) ~kind:Toggle
    ~default:false ~get:Fun.id ~set:(fun value _ -> value) ()));
  print_endline "param: Flow row metadata preserves values and cook identity"
