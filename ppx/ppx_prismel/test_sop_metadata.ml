open Ppxlib

let declaration fields attributes =
  let source = "type parameters = { " ^ fields ^ " } " ^ attributes in
  let lexbuf = Lexing.from_string source in
  Location.init lexbuf "metadata.ml";
  match Parse.implementation lexbuf with
  | [{ pstr_desc = Pstr_type (_, [declaration]); _ }] -> declaration
  | _ -> assert false

let reject expected check =
  match check () with
  | _ -> failwith ("accepted invalid declaration: " ^ expected)
  | exception error ->
      (match Location.Error.of_exn error with
       | Some error ->
           assert (Location.Error.message error = expected);
           assert ((Location.Error.get_location error).loc_start.pos_fname = "metadata.ml")
       | None -> raise error)

let float name group folder = Printf.sprintf
    "%s : float [@sop.default 0.] [@sop.min (-1.)] [@sop.max 1.] %s %s;"
    name group folder

let vector = List.map (fun name -> float name "[@sop.vec3 \"center\"]" "")
    ["center_x"; "center_y"; "center_z"] |> String.concat "\n"

let node key slots = Printf.sprintf
    "[@@sop.node_key %S] [@@sop.node_label \"Fixture\"]\n\
     [@@sop.node_category \"Test\"] [@@sop.node_inputs 2] %s" key slots

let () =
  let valid = declaration vector "" in
  assert (List.length (Ppx_prismel.generate_type valid) = 2);
  let bad_vector = "sop.vec3 \"center\" requires exactly three consecutive float fields in one folder" in
  List.iter (fun fields -> reject bad_vector (fun () ->
      Ppx_prismel.generate_type (declaration fields "")))
    [float "x" "[@sop.vec3 \"center\"]" "";
     vector ^ float "w" "[@sop.vec3 \"center\"]" "";
     float "x" "[@sop.vec3 \"center\"]" ""
       ^ float "gap" "" ""
       ^ float "y" "[@sop.vec3 \"center\"]" ""
       ^ float "z" "[@sop.vec3 \"center\"]" "";
     float "x" "[@sop.vec3 \"center\"]" ""
       ^ float "y" "[@sop.vec3 \"center\"]" "[@sop.folder \"Other\"]"
       ^ float "z" "[@sop.vec3 \"center\"]" "";
     "x : bool [@sop.default false] [@sop.vec3 \"center\"];"
       ^ float "y" "[@sop.vec3 \"center\"]" ""
       ^ float "z" "[@sop.vec3 \"center\"]" "";
     vector ^ "hidden : float [@sop.default 0.] [@sop.ignore] [@sop.vec3 \"center\"];" ];
  reject "sop.vec3 \"center\" clashes with a parameter name" (fun () ->
    Ppx_prismel.generate_type (declaration (vector ^ float "center" "" "") ""));
  reject "sop.vec3 \"\" must not be blank" (fun () ->
    Ppx_prismel.generate_type (declaration (float "x" "[@sop.vec3 \"\"]" "") ""));
  List.iter (fun key -> reject
      (Printf.sprintf "sop.node_key must match [a-z][a-z0-9_]*, not %S" key)
      (fun () -> Ppx_prismel.node_metadata (declaration vector (node key ""))))
    ["Upper"; "bad-key"; "9start"; "white space"];
  List.iter (fun slots -> reject
      "sop.node_slots requires 2 distinct names matching [a-z][a-z0-9_]*"
      (fun () -> Ppx_prismel.node_metadata
        (declaration vector (node "fixture" ("[@@sop.node_slots " ^ slots ^ "]")))))
    ["\"input\""; "\"input, input\""; "\"input, Target\""; "\"input, \""];
  reject "sop.node_slots name \"center\" clashes with a parameter name" (fun () ->
    Ppx_prismel.node_metadata (declaration vector
      (node "fixture" "[@@sop.node_slots \"center, target\"]")));
  reject "sop.node_slots name \"in0\" clashes with a parameter name" (fun () ->
    Ppx_prismel.node_metadata (declaration (float "in0" "" "") (node "fixture" "")));
  let _, _, _, _, _, _, slots = Ppx_prismel.node_metadata
      (declaration vector (node "fixture" "")) in
  assert (slots = ["in0"; "in1"]);
  let _, _, _, _, _, _, slots = Ppx_prismel.node_metadata
      (declaration vector (node "fixture" "[@@sop.node_slots \"input, target\"]")) in
  assert (slots = ["input"; "target"])
