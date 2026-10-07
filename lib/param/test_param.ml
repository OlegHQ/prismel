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
  (* inspection text shows a float as the shortest decimal that reads back exactly *)
  assert (List.map (cook_text plain) [1.5; 0.1; 0.1 +. 0.2; -0.] = ["x=1.5"; "x=0.1"; "x=0.30000000000000004"; "x=-0"]);
  let grouped, effects = apply_all grouped 1. ["x", Float_value 3.] |> Result.get_ok in
  assert (grouped = 3. && effects.cook);
  let invalid f = try ignore (f ()); false with Invalid_argument _ -> true in
  assert (invalid (fun () -> field ~vec3:("",0) ()));
  assert (invalid (fun () -> field ~vec3:("center",3) ()));
  assert (invalid (fun () -> Param.field ~name:"x" ~vec3:("center",0) ~kind:Toggle
    ~default:false ~get:Fun.id ~set:(fun value _ -> value) ()));
  let choice_schema labels = schema ~name:"switch" ~default:0
      [Param.field ~name:"input" ~kind:(index_choice labels) ~default:0
         ~get:Fun.id ~set:(fun value _ -> value) ()] in
  let initial = choice_schema ["cube"; "grid"] in
  let renamed = choice_schema ["box"; "replacement"] in
  assert (cook_key initial 1 = cook_key renamed 1);
  assert ((List.hd (view initial 1)).current = Int_value 1);
  let selected, effects = apply_all initial 0 ["input", Int_value 1] |> Result.get_ok in
  assert (selected = 1 && effects.cook);
  assert (Result.is_error (apply_all initial 0 ["input", Int_value (-1)]));
  assert (Result.is_error (apply_all initial 0 ["input", Int_value 2]));
  assert (invalid (fun () -> index_choice []));
  assert (invalid (fun () -> index_choice ["duplicate"; "duplicate"]));
  print_endline "param: Flow row metadata preserves values and cook identity"

type normalization_probe = { count : int; amount : float; title : string }

let () =
  let open Param in
  let amount_kind = floating ~min:0. ~max:10. ~hard_min:0. ~hard_max:10. () in
  let fields = [
    field ~name:"count" ~kind:(integer ~min:0 ~max:10 ~hard_min:0 ~hard_max:10 ())
      ~default:3 ~get:(fun value -> value.count)
      ~set:(fun count value -> {value with count}) ();
    field ~name:"amount" ~kind:amount_kind ~default:2.
      ~get:(fun value -> value.amount)
      ~set:(fun amount value -> {value with amount}) ();
    field ~name:"title" ~kind:Text ~default:"ok" ~get:(fun value -> value.title)
      ~set:(fun title value -> {value with title}) ();
  ] in
  let original = {count=3; amount=2.; title="ok"} in
  let template = schema ~name:"normalization" ~default:original fields in
  assert (default template == original);
  assert (Result.get_ok (normalize template original) == original);
  let outside = {original with count=20; amount=(-2.)} in
  let expected = {original with count=10; amount=0.} in
  assert (Result.get_ok (normalize template outside) = expected);
  assert (default (schema ~name:"clamped" ~default:outside fields) = expected);
  assert (outside.count = 20 && outside.amount = -2.);
  let signed_zero = {original with amount=(-0.)} in
  let normalized = Result.get_ok (normalize template signed_zero) in
  let expected_zero = Result.get_ok (normalize_value amount_kind (-0.)) in
  assert (Int64.bits_of_float normalized.amount = Int64.bits_of_float expected_zero);
  assert (Result.is_error (normalize template {original with amount=Float.nan}));
  assert (Result.is_error (normalize template {original with amount=Float.infinity}))
