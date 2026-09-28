open Ppxlib

let parse_payload text =
  let lexbuf = Lexing.from_string text in
  Location.init lexbuf "flow_sample.ml";
  match Parse.implementation lexbuf with
  | [{pstr_desc = Pstr_value (_, [{pvb_expr =
        {pexp_desc = Pexp_extension (_, PStr [{pstr_desc = Pstr_eval (payload, _); _}]);
         pexp_loc = loc; _}; _}]); _}] -> loc, payload
  | _ -> failwith "invalid PPX test fixture"

let () =
  Ppx_prismel.flow_manifest_path := Some Sys.argv.(1);
  let text = "let network = [%flow {|(graph demo (let* [cube (sop/boz)] cube))|}]" in
  let loc, payload = parse_payload text in
  let result = Ppx_prismel.expand_flow ~loc ~locals:[] payload in
  let error = match result.pexp_desc with
    | Pexp_extension extension -> Location.Error.of_extension extension
    | _ -> None in
  let error = Option.get error in
  assert (String.starts_with ~prefix:"E_UNKNOWN_KIND"
    (Location.Error.message error));
  let at = (Location.Error.get_location error).loc_start in
  assert (at.pos_fname = "flow_sample.ml");
  assert (at.pos_cnum = String.index text 's');
  let text = "let network = [%flow {|(graph demo\n  (sop/boz))|}]" in
  let loc, payload = parse_payload text in
  let error = match (Ppx_prismel.expand_flow ~loc ~locals:[] payload).pexp_desc with
    | Pexp_extension extension -> Option.get (Location.Error.of_extension extension)
    | _ -> failwith "expected second-line kind error" in
  let at = (Location.Error.get_location error).loc_start in
  assert (at.pos_lnum = 2 && at.pos_cnum = String.index text 's');
  let text = "let network = [%flow {|(graph demo (let* [cube (sop/box :size [1 2])] cube))|}]" in
  let loc, payload = parse_payload text in
  let error = match (Ppx_prismel.expand_flow ~loc ~locals:[] payload).pexp_desc with
    | Pexp_extension extension -> Option.get (Location.Error.of_extension extension)
    | _ -> failwith "expected vector arity error" in
  assert (String.starts_with ~prefix:"E_VECTOR_ARITY"
    (Location.Error.message error));
  let declaration = "module Rings = struct\n\
    type parameters = {\n\
      steps : int [@sop.default 2] [@sop.min 1] [@sop.max 8];\n\
      mode : string [@sop.default \"solid\"] [@sop.kind mode_kind];\n\
    } [@@sop.node_key \"rings\"] [@@sop.node_label \"Rings\"]\n\
      [@@sop.node_category \"Test\"] [@@sop.node_inputs 0]\n\
    end [@@sop.register]" in
  let lexbuf = Lexing.from_string declaration in
  Location.init lexbuf "local.ml";
  let item = List.hd (Parse.implementation lexbuf) in
  let local = Option.get (Ppx_prismel.local_registered item) in
  let manifest = In_channel.with_open_text Sys.argv.(1) In_channel.input_all in
  let catalog, _ = Flow.Check.catalog_of_manifest manifest |> Result.get_ok in
  let catalog = {catalog with Flow.Check.kinds = catalog.kinds @ [snd local]} in
  let codes text = Flow.Check.check catalog text |> snd
    |> List.map (fun diagnostic -> diagnostic.Flow.Diagnostic.code) in
  assert (List.mem "E_INT_LITERAL" (codes
    "(graph test (user/rings :steps 2.5))"));
  assert (List.mem "E_TYPE" (codes
    "(graph test (user/rings :mode 3))"));
  assert (List.mem "E_DUPLICATE_DEF" (codes
    "(defgraph rings [] (sop/box)) (graph test (user/rings))"));
  let lexbuf = Lexing.from_string (declaration ^ "\n" ^ declaration) in
  Location.init lexbuf "duplicate.ml";
  (match Ppx_prismel.flow_structure (Parse.implementation lexbuf) with
   | _ -> failwith "accepted duplicate file-local Flow node"
   | exception error ->
       (match Location.Error.of_exn error with
        | Some error -> assert (String.starts_with
            ~prefix:"duplicate file-local Flow node"
            (Location.Error.message error))
        | None -> raise error))
