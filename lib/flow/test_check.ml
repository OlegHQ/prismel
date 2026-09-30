open Flow

let float_range = Param.{soft_min = 0.; soft_max = 2.;
  hard_min = Some 0.; hard_max = Some 4.}
let size = Check.{name = "size"; label = "Size"; ty = Some Port_type.Float;
  fields = ["size", Param.Floating_view float_range, Param.Float_value 1.]}
let rows = Check.{name = "rows"; label = "Rows"; ty = Some Port_type.Int;
  fields = ["rows", Param.Integer_view Param.{soft_min = 2; soft_max = 40;
    hard_min = Some 1; hard_max = Some 100}, Param.Int_value 10]}
let mode = Check.{name = "mode"; label = "Mode"; ty = None;
  fields = ["mode", Param.Choice_view [|"solid"; "wire"|],
    Param.Choice_value "solid"]}
let box = Check.{qualified = "sop/box"; aliases = [];
  context = Context.Sop; slots = []; parameters = [size; rows; mode];
  outputs = ["geo", Port_type.Geometry]}
let transform = Check.{qualified = "sop/transform"; aliases = [];
  context = Context.Sop; slots = [{name = "in0"; required = true; rest = false}]; parameters = [];
  outputs = ["geo", Port_type.Geometry]}
let catalog = Check.{version = 202609; kinds = [box; transform]}


let code = function Error (code, _) -> code | Ok _ -> "ok"

let () =
  let resolve context name = Check.resolve_kind catalog context name in
  assert (resolve Context.Sop "box" |> Result.map (fun (k : Check.kind) -> k.qualified) = Ok "sop/box");
  assert (resolve Context.Sop "sop/transform" |> Result.is_ok);
  assert (code (resolve Context.Sop "boxx") = "E_UNKNOWN_KIND");
  assert (code (resolve Context.Sop "nope/box") = "E_NAMESPACE");
  assert (code (resolve Context.Scene "sop/box") = "E_WRONG_CONTEXT");
  (match Check.catalog_of_manifest "(flow_manifest (version 1) (digest \"wrong\") (kinds))" with
   | Error diagnostic -> assert (diagnostic.code = "E_CATALOG"
       && diagnostic.message = "Flow manifest digest must be 32 lowercase hex digits")
   | Ok _ -> failwith "accepted malformed Flow manifest digest");
  print_endline "Flow checker: kind resolution and the manifest reader pass"
