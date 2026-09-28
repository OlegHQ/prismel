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
  context = Context.Sop; slots = [{name = "in0"; required = true}]; parameters = [];
  outputs = ["geo", Port_type.Geometry]}
let catalog = Check.{version = 202609; kinds = [box; transform]}

let diagnostics source = snd (Check.check catalog source)
let observed = Hashtbl.create 40
let expect source expected =
  let found = diagnostics source in
  List.iter (fun (diagnostic : Diagnostic.t) ->
    let messages = Option.value ~default:[]
      (Hashtbl.find_opt observed diagnostic.code) in
    Hashtbl.replace observed diagnostic.code (diagnostic.message :: messages);
    assert (diagnostic.message <> "" && Option.is_some diagnostic.position
      && Option.is_some diagnostic.span)) found;
  let actual = List.map (fun (diagnostic : Diagnostic.t) -> diagnostic.code) found in
  if actual <> expected then failwith (Printf.sprintf "%S: expected [%s], got [%s]"
    source (String.concat ", " expected) (String.concat ", " actual))
let valid source = match Check.check catalog source with
  | Some program, diagnostics when not (List.exists (fun (d : Diagnostic.t) ->
      d.severity = Diagnostic.Error) diagnostics) -> program
  | _, diagnostics -> failwith (Printf.sprintf "%S: %s" source
      (String.concat "; " (List.map Diagnostic.to_string diagnostics)))

let () =
  let program = valid "(graph demo :context sop :catalog 202609\n  (let* [cube (box :size 2) moved (transform cube)] moved))" in
  assert (program.graph.name = "demo"
    && List.map (fun (binding : Check.binding) -> binding.name)
      program.graph.bindings = ["cube"; "moved"]);
  let empty = valid "(graph empty :context sop nil)" in
  assert (empty.graph.results = [Check.{node = Nil; ty = None}]);
  let program = valid "(defgraph lift :context sop [(input :geometry)]\n  (transform input))\n(graph demo (let* [b (box) a (user/lift b)] a))" in
  assert (List.length program.definitions = 1);
  let named = valid "(defgraph split [(input :geometry)]
    (values :left input :right input))
    (graph demo (let* [b (box) s (user/split b)] s.left))" in
  assert ((List.hd named.definitions).outputs =
    ["left", Port_type.Geometry; "right", Port_type.Geometry]);
  let program = valid "(graph demo (let* [a (sop/box :size 3)] a))" in
  (match program.graph.bindings with
   | [{term = {node = Check.Call call; _}; _}] ->
       assert (call.kind = "sop/box")
   | _ -> failwith "checker lost the qualified call");
  let math = valid "(graph demo (let* [v (+ 1 (* 2 t)) cube (box :size v)] cube))" in
  assert (List.length math.graph.bindings = 2);
  let wired_math = valid "(graph demo (let* [v (value/value :v 2) sum (+ v 1) cube (box :size sum)] cube))" in
  (match wired_math.graph.bindings with
   | _ :: {term = {node = Check.Call call; _}; _} :: _ ->
       assert (call.kind = "value/math" && List.length call.arguments = 3)
   | _ -> failwith "referenced math did not create a math call");
  let vector = valid "(graph demo (let* [parts (value/separate_xyz :v [1 2 3]) cube (box :size parts.x)] cube))" in
  assert (List.length vector.graph.bindings = 2);
  expect "" ["E_NO_GRAPH"];
  expect "(box)" ["E_TOPLEVEL"; "E_NO_GRAPH"];
  expect "(graph a (box)) (graph b (box))" ["E_ONE_GRAPH"];
  expect "(graph a :catalog 202611 (box))" ["E_CATALOG"];
  expect "(graph a :context scene (box))" ["E_CONTEXT_PLANNED"];
  expect "(graph a :context unknown (box))" ["E_CONTEXT_UNKNOWN"];
  expect "(graph a (let* [cube (box :siz 1) moved (transform cube)] moved))"
    ["E_UNKNOWN_PARAM"];
  expect "(graph a (let* [cube (box :size 1 :size 2)] cube))"
    ["E_DUPLICATE_PARAM"];
  expect "(graph a (let* [cube (box :size)] cube))" ["E_MISSING_VALUE"];
  expect "(graph a (let* [cube (box :size 2.5)] cube))" ["W_SOFT_RANGE"];
  expect "(graph a (let* [cube (box :size 5)] cube))" ["E_HARD_RANGE"];
  expect "(graph a (let* [cube (box :rows 2.5)] cube))" ["E_INT_LITERAL"];
  expect "(graph a (let* [cube (box :mode \"wrong\")] cube))" ["E_TYPE"];
  let choice = valid "(graph a (let* [cube (box :mode \"wire\")] cube))" in
  (match choice.graph.bindings with
   | [{term = {node = Check.Call {arguments = ["mode", {node = Check.Literal
       (Param.Choice_value "wire"); _}]; _}; _}; _}] -> ()
   | _ -> failwith "choice label was not normalized for the builder");
  let numeric = valid "(graph a (let* [cube (box :size 2 :rows 3.0)] cube))" in
  (match numeric.graph.bindings with
   | [{term = {node = Check.Call {arguments = ["size", {node = Check.Literal
       (Param.Float_value 2.); _}; "rows", {node = Check.Literal
       (Param.Int_value 3); _}]; _}; _}; _}] -> ()
   | _ -> failwith "numeric literals were not normalized to parameter kinds");
  expect "(graph a (let* [cube (box 1)] cube))" ["E_EXTRA_POSITIONAL"];
  expect "(graph a (let* [cube (transform :in0 nil (box))] cube))"
    ["E_POSITIONAL_AFTER_KEYWORD"];
  expect "(graph a (let* [t (box)] (box)))" ["E_BINDING_T"];
  expect "(graph a (let* [cube (box) cube (box)] cube))"
    ["E_DUPLICATE_BINDING"];
  expect "(graph a (let* [Cube (box)] (box)))" ["E_BINDING_NAME"];
  expect "(graph a (let* [cube (box)] cube.bad))" ["E_OUTPUT_UNKNOWN"];
  expect "(graph a (let* [cube box] cube))" ["E_KIND_AS_VALUE"];
  expect "(graph a (let* [cube (sops/box)] cube))" ["E_NAMESPACE"];
  expect "(graph a (let* [cube (boz)] cube))" ["E_UNKNOWN_KIND"];
  expect "(graph a missing)" ["E_UNBOUND"];
  expect "(graph a (let* [cube (box :size [1 2])] cube))"
    ["E_VECTOR_ARITY"];
  expect "(graph a (let* [cube (box :size true)] cube))" [];
  expect "(graph a (values (box)))" ["E_VALUES_PLACE"];
  expect "(graph a (+ 1 2))" ["E_RESULT_TYPE"];
  expect "(graph a (let* [v (sin 1 2) cube (box)] cube))" ["E_ARITY"];
  expect "(graph a (let* [cube ^:other (box)] cube))" ["W_UNKNOWN_META"];
  expect "(graph a (let* [cube ^:bypass (box)] cube))" [];
  expect "(defgraph ripple :context value [] (sop/box)) (graph a (box))"
    ["E_WRONG_CONTEXT"];
  expect "(defgraph box :context value [] 1) (graph a (box))"
    ["E_AMBIGUOUS"];
  expect "(defgraph x [] 1) (defgraph x [] 1) (graph a (box))"
    ["E_DUPLICATE_DEF"];
  expect "(defgraph x [foo] 1) (graph a (box))" ["E_INTERFACE_ENTRY"];
  expect "(defgraph x [(foo :weird 1)] 1) (graph a (box))"
    ["E_UNKNOWN_TYPE"];
  expect "(defgraph x [(foo :int 2.5)] foo) (graph a (box))"
    ["E_INT_LITERAL"];
  expect "(defgraph x [(foo :float t)] foo) (graph a (box))"
    ["E_TYPE"];
  expect "(defgraph x [(foo :geometry 1)] foo) (graph a (box))"
    ["E_TYPE"];
  expect "(defgraph x [(foo :float)] foo) (graph a (box))"
    ["W_NO_DEFAULT"];
  expect "(defgraph x [] (values :same (box) :same (box))) (graph a (box))"
    ["E_INTERFACE_ENTRY"];
  expect "(defgraph x [] (values :Bad (box))) (graph a (box))"
    ["E_INTERFACE_ENTRY"];
  expect "(defgraph x [] (values :out)) (graph a (box))"
    ["E_INTERFACE_ENTRY"];
  let warning = List.hd (diagnostics
    "(graph demo\n (let* [cube (box :size 3)] cube))") in
  assert (warning.severity = Diagnostic.Warning
    && warning.position = Some Diagnostic.{line = 2; col = 25}
    && Option.is_some warning.span);
  let contains text fragment =
    let length = String.length text and width = String.length fragment in
    let rec search index = index + width <= length &&
      (String.sub text index width = fragment || search (index + 1)) in
    search 0 in
  List.iter (fun (code, fragment) ->
    match Hashtbl.find_opt observed code with
    | Some messages when List.exists (fun message -> contains message fragment) messages -> ()
    | _ -> failwith (code ^ " has no tested diagnostic message containing " ^ fragment))
    ["E_NO_GRAPH", "No (graph"; "E_TOPLEVEL", "Top-level forms";
     "E_ONE_GRAPH", "One graph per file"; "E_CATALOG", "needs catalog";
     "E_CONTEXT_PLANNED", "planned"; "E_CONTEXT_UNKNOWN", "Unknown context";
     "E_UNKNOWN_PARAM", "no parameter"; "E_DUPLICATE_PARAM", "given twice";
     "E_MISSING_VALUE", "no value"; "W_SOFT_RANGE", "outside the slider range";
     "E_HARD_RANGE", "outside its hard range"; "E_INT_LITERAL", "is an integer";
     "E_TYPE", "must be one of"; "E_EXTRA_POSITIONAL", "extra";
     "E_POSITIONAL_AFTER_KEYWORD", "before keyword";
     "E_BINDING_T", "context time"; "E_DUPLICATE_BINDING", "bound twice";
     "E_BINDING_NAME", "Binding names match";
     "E_OUTPUT_UNKNOWN", "has no output"; "E_KIND_AS_VALUE", "node kind";
     "E_NAMESPACE", "Unknown namespace"; "E_UNKNOWN_KIND", "Unknown node";
     "E_UNBOUND", "not bound"; "E_VECTOR_ARITY", "3 components";
     "E_VALUES_PLACE", "for defgraph results";
     "E_RESULT_TYPE", "returns geometry"; "E_ARITY", "takes 1 argument";
     "W_UNKNOWN_META", "only ^:bypass"; "E_WRONG_CONTEXT", "cannot appear";
     "E_AMBIGUOUS", "Write the namespace";
     "E_DUPLICATE_DEF", "defined twice";
     "E_INTERFACE_ENTRY", "Each interface entry";
     "E_UNKNOWN_TYPE", "Unknown interface type";
     "W_NO_DEFAULT", "has no default"];
  print_endline "Flow checker: resolution, typing, poisoning and located diagnostics pass"
