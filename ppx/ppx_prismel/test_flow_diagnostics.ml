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
  let result = Ppx_prismel.expand_flow ~loc payload in
  let error = match result.pexp_desc with
    | Pexp_extension extension -> Location.Error.of_extension extension
    | _ -> None in
  let error = Option.get error in
  assert (String.starts_with ~prefix:"E_UNKNOWN_KIND"
    (Location.Error.message error));
  let at = (Location.Error.get_location error).loc_start in
  assert (at.pos_fname = "flow_sample.ml");
  assert (at.pos_cnum = String.index text 's');
  let text = "let network = [%flow {|(graph demo (let* [cube (sop/box :size [1 2])] cube))|}]" in
  let loc, payload = parse_payload text in
  let error = match (Ppx_prismel.expand_flow ~loc payload).pexp_desc with
    | Pexp_extension extension -> Option.get (Location.Error.of_extension extension)
    | _ -> failwith "expected vector arity error" in
  assert (String.starts_with ~prefix:"E_VECTOR_ARITY"
    (Location.Error.message error))
