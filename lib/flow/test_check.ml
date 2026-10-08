open Flow

let float_range = Param.{soft_min = 0.; soft_max = 2.;
  hard_min = Some 0.; hard_max = Some 4.}
let size = Check.{name = "size"; label = "Size"; ty = Some Port_type.Float;
  fields = ["size", Param.Floating_view float_range, Param.Float_value 1.]; folder = []; primary = false; unit = None}
let rows = Check.{name = "rows"; label = "Rows"; ty = Some Port_type.Int;
  fields = ["rows", Param.Integer_view Param.{soft_min = 2; soft_max = 40;
    hard_min = Some 1; hard_max = Some 100}, Param.Int_value 10]; folder = []; primary = false; unit = None}
let mode = Check.{name = "mode"; label = "Mode"; ty = None;
  fields = ["mode", Param.Choice_view [|"solid"; "wire"|],
    Param.Choice_value "solid"]; folder = []; primary = false; unit = None}
let box = Check.{qualified = "sop/box"; aliases = [];
  context = Context.sop; slots = []; parameters = [size; rows; mode];
  outputs = ["geo", Port_type.Geometry]; facts = None}
let transform = Check.{qualified = "sop/transform"; aliases = [];
  context = Context.sop; slots = [{name = "in0"; required = true; rest = false; ty = None}]; parameters = [];
  outputs = ["geo", Port_type.Geometry]; facts = None}
let catalog = Check.{version = 202609; kinds = [box; transform]}


let code = function Error (code, _) -> code | Ok _ -> "ok"

let () =
  let resolve context name = Check.resolve_kind catalog context name in
  assert (resolve Context.sop "box" |> Result.map (fun (k : Check.kind) -> k.qualified) = Ok "sop/box");
  assert (resolve Context.sop "sop/transform" |> Result.is_ok);
  assert (code (resolve Context.sop "boxx") = "E_UNKNOWN_KIND");
  assert (code (resolve Context.sop "nope/box") = "E_NAMESPACE");
  assert (code (resolve Context.scene "sop/box") = "E_WRONG_CONTEXT");
  (match Check.catalog_of_manifest "(flow_manifest (version 1) (digest \"wrong\") (kinds))" with
   | Error diagnostic -> assert (diagnostic.code = "E_CATALOG"
       && diagnostic.message = "Flow manifest digest must be 32 lowercase hex digits")
   | Ok _ -> failwith "accepted malformed Flow manifest digest");
  let manifest facts =
    let kind = "(kind \"sop/box\" (key \"box\") (aliases) (operation \"box\")\n\
      (label \"Box\") (category \"Create\") (slots) (fields) (outputs) " ^ facts ^ ")" in
    let digest = Digest.to_hex (Digest.string ("(version 1)\n(kinds " ^ kind ^ ")")) in
    "(flow_manifest (version 1) (digest \"" ^ digest ^ "\") (kinds " ^ kind ^ "))" in
  let facts elementwise reads mode tail = "(facts (cook-mode " ^ mode ^ ") (elementwise " ^ elementwise ^
    ") (reads " ^ reads ^ ") (writes \"P\") (topology preserved) " ^ tail ^ ")" in
  let valid = facts "points" "\"P\"" "duplicate-input 0" "(exact false)" in
  let catalog, _ = Check.catalog_of_manifest (manifest valid) |> Result.get_ok in
  assert ((List.hd catalog.kinds).facts = Some Check.{elementwise = Points;
    reads = ["P"]; writes = ["P"]; preserves_topology = true; exact = false});
  List.iter (fun declaration -> match Check.catalog_of_manifest (manifest declaration) with
    | Error diagnostic -> assert (diagnostic.code = "E_CATALOG")
    | Ok _ -> failwith "accepted invalid kernel facts")
    [facts "pixels" "\"P\"" "generic" "(exact false)";
     facts "points" "\"\"" "generic" "(exact false)";
     facts "points" "\"P\"" "duplicate-input -1" "(exact false)";
     facts "points" "\"P\"" "generic" "(exact false) (exact true)";
     facts "points" "\"P\"" "generic" "";
     valid ^ " " ^ valid];
  print_endline "Flow checker: kind resolution, kernel facts and the manifest reader pass"
