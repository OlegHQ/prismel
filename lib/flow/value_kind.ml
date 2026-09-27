type kind = Time | Value | Math | Combine_xyz | Separate_xyz | Remap
type t = Parameters : {
  kind : kind;
  schema : 'a Param.schema;
  value : 'a;
  evaluate : time:float -> 'a -> ((string * Port_type.value) list, Diagnostic.t) result;
  active : 'a -> string -> bool;
} -> t

let all = [Time; Value; Math; Combine_xyz; Separate_xyz; Remap]
let key = function Time -> "time" | Value -> "value" | Math -> "math"
  | Combine_xyz -> "combine_xyz" | Separate_xyz -> "separate_xyz" | Remap -> "remap"
let of_key name = match List.find_opt (fun kind -> key kind = name) all with
  | Some kind -> Ok kind
  | None -> Error (Diagnostic.error ~code:"E_KIND_UNKNOWN" ("Unknown value kind value/" ^ name))
let label = function Time -> "Time" | Value -> "Value" | Math -> "Math"
  | Combine_xyz -> "Combine XYZ" | Separate_xyz -> "Separate XYZ" | Remap -> "Remap"
let category = function Math | Remap -> ["Math"]
  | Combine_xyz | Separate_xyz -> ["Vector"] | Time | Value -> ["Value"]
let outputs = function
  | Time -> ["t", Port_type.Float]
  | Combine_xyz -> ["out", Port_type.Vec3]
  | Separate_xyz -> ["x", Port_type.Float; "y", Port_type.Float; "z", Port_type.Float]
  | Value | Math | Remap -> ["out", Port_type.Float]

let floating ?vec3 ~name ~default ~min ~max ~get ~set () =
  Param.field ~name ~primary:true ?vec3 ~kind:(Param.floating ~min ~max ())
    ~default ~get ~set ()
let scalar_schema kind ~name ~default ~min ~max =
  Param.schema ~name:("value/" ^ key kind) ~default
    [floating ~name ~default ~min ~max ~get:Fun.id ~set:(fun value _ -> value) ()]
let time_schema = scalar_schema Time ~name:"speed" ~default:1. ~min:(-4.) ~max:4.
let value_schema = scalar_schema Value ~name:"v" ~default:0. ~min:(-2.) ~max:2.

type math = { op : Expr.op; a : float; b : float }
let math_schema =
  let default = {op = Expr.Mul; a = 0.; b = 1.} in
  Param.schema ~name:"value/math" ~default
    [Param.field ~name:"op" ~primary:true ~kind:(Param.choice ~equal:( = ) Expr.operators)
       ~default:default.op ~get:(fun p -> p.op) ~set:(fun op p -> {p with op}) ();
     floating ~name:"a" ~default:default.a ~min:(-2.) ~max:2.
       ~get:(fun p -> p.a) ~set:(fun a p -> {p with a}) ();
     floating ~name:"b" ~default:default.b ~min:(-2.) ~max:2.
       ~get:(fun p -> p.b) ~set:(fun b p -> {p with b}) ()]

let vector_schema kind =
  let component index name get set =
    let name, vec3 = if kind = Separate_xyz then "v_" ^ name, Some ("v", index)
      else name, None in
    floating ~name ?vec3 ~default:0. ~min:(-3.) ~max:3. ~get ~set () in
  Param.schema ~name:("value/" ^ key kind) ~default:(0.,0.,0.)
    [component 0 "x" (fun (x,_,_) -> x) (fun x (_,y,z) -> x,y,z);
     component 1 "y" (fun (_,y,_) -> y) (fun y (x,_,z) -> x,y,z);
     component 2 "z" (fun (_,_,z) -> z) (fun z (x,y,_) -> x,y,z)]
let combine_schema = vector_schema Combine_xyz
let separate_schema = vector_schema Separate_xyz

type remap = {
  v : float; from_min : float; from_max : float;
  to_min : float; to_max : float; clamp : bool;
}
let remap_schema =
  let default = {v = 0.; from_min = 0.; from_max = 1.; to_min = 0.; to_max = 1.; clamp = false} in
  let field name default get set = floating ~name ~default ~min:(-10.) ~max:10. ~get ~set () in
  Param.schema ~name:"value/remap" ~default
    [field "v" default.v (fun p -> p.v) (fun v p -> {p with v});
     field "from_min" default.from_min (fun p -> p.from_min) (fun from_min p -> {p with from_min});
     field "from_max" default.from_max (fun p -> p.from_max) (fun from_max p -> {p with from_max});
     field "to_min" default.to_min (fun p -> p.to_min) (fun to_min p -> {p with to_min});
     field "to_max" default.to_max (fun p -> p.to_max) (fun to_max p -> {p with to_max});
     Param.field ~name:"clamp" ~primary:true ~kind:Param.Toggle ~default:default.clamp
       ~get:(fun p -> p.clamp) ~set:(fun clamp p -> {p with clamp}) ()]

let scalar_output name number = [name, Port_type.Float_value number]
let make kind =
  let pack ?(active = fun _ _ -> true) schema evaluate =
    Parameters {kind; schema; value = Param.default schema; evaluate; active} in
  match kind with
  | Time -> pack time_schema (fun ~time speed -> Ok (scalar_output "t" (time *. speed)))
  | Value -> pack value_schema (fun ~time:_ value -> Ok (scalar_output "out" value))
  | Math -> pack math_schema
      ~active:(fun p name -> name <> "b" || Expr.arity p.op = 2)
      (fun ~time:_ p -> Result.map (scalar_output "out")
        (Expr.apply p.op (if Expr.arity p.op = 1 then [p.a] else [p.a;p.b])))
  | Combine_xyz -> pack combine_schema (fun ~time:_ (x,y,z) -> Ok ["out", Port_type.Vec3_value (x,y,z)])
  | Separate_xyz -> pack separate_schema (fun ~time:_ (x,y,z) -> Ok
      ["x", Port_type.Float_value x; "y", Port_type.Float_value y; "z", Port_type.Float_value z])
  | Remap -> pack remap_schema (fun ~time:_ p ->
      let output = if p.from_min = p.from_max then p.to_min else
        let fraction = (p.v -. p.from_min) /. (p.from_max -. p.from_min) in
        let fraction = if p.clamp then Float.max 0. (Float.min 1. fraction) else fraction in
        p.to_min +. fraction *. (p.to_max -. p.to_min) in
      Ok (scalar_output "out" output))

let kind (Parameters p) = p.kind
let fields (Parameters p) = Param.view p.schema p.value
let field_active (Parameters p) ~name = p.active p.value name
let parameter_key (Parameters p) = Param.cook_key p.schema p.value
let eval ~time (Parameters p) = p.evaluate ~time p.value
let apply_parameters (Parameters p as original) changes =
  let rec apply value effects = function
    | [] -> Ok ((if Param.has_effects effects then Parameters {p with value} else original), effects)
    | (name, candidate) :: rest ->
        (match Param.apply p.schema value ~name candidate with
         | Error message -> Error (Diagnostic.error ~code:"E_TYPE" message)
         | Ok None -> Error (Diagnostic.error ~code:"E_UNKNOWN_PARAM" ("Unknown parameter " ^ name))
         | Ok (Some (value, impact)) ->
             let effects = match impact with None -> effects | Some impact -> Param.add_impact impact effects in
             apply value effects rest)
  in apply p.value Param.no_effects changes
