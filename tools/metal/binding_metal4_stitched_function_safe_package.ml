type fn = { token : int; device : int; destroyed : bool }
type graph = { token : int; device : int; functions : fn list; destroyed : bool }
type t =
  { device : int; mutable descriptors : fn list option; mutable graph : graph option
  ; mutable destroyed : bool }

let callable_ids =
  [ "method:-[MTL4StitchedFunctionDescriptor setFunctionGraph:]"
  ; "property:MTL4StitchedFunctionDescriptor:functionGraph" ]

let validate_functions ~device (functions : fn list) =
  let rec loop seen (remaining : fn list) = match remaining with
    | [] -> Ok ()
    | fn :: _ when fn.destroyed -> Error "destroyed stitched function"
    | fn :: _ when fn.device <> device -> Error "stitched function belongs to another device"
    | fn :: _ when List.mem fn.token seen -> Error "duplicate stitched function"
    | fn :: rest -> loop (fn.token :: seen) rest
  in
  if functions = [] then Error "stitched function array must be nonempty" else loop [] functions

let validate_pair ~device (descriptors : fn list option) (graph : graph option) =
  match descriptors, graph with
  | None, None -> Ok ()
  | None, Some _ | Some _, None -> Error "stitched descriptor and graph must be replaced together"
  | Some descriptors, Some graph ->
      if graph.destroyed then Error "destroyed stitching graph"
      else if graph.device <> device then Error "stitching graph belongs to another device"
      else match validate_functions ~device descriptors, validate_functions ~device graph.functions with
      | Error error, _ | _, Error error -> Error error
      | Ok (), Ok () ->
          let descriptor_tokens = List.map (fun (fn : fn) -> fn.token) descriptors |> List.sort compare in
          let graph_tokens = List.map (fun (fn : fn) -> fn.token) graph.functions |> List.sort compare in
          if descriptor_tokens <> graph_tokens then Error "stitched graph/function cardinality mismatch" else Ok ()

let create ~device ~descriptors ~graph =
  Result.map (fun () -> { device; descriptors; graph; destroyed = false })
    (validate_pair ~device descriptors graph)

let set_pair descriptor ~descriptors ~graph =
  if descriptor.destroyed then Error "destroyed MTL4 stitched descriptor"
  else match validate_pair ~device:descriptor.device descriptors graph with
  | Error error -> Error error
  | Ok () -> descriptor.descriptors <- descriptors; descriptor.graph <- graph; Ok ()

let function_graph descriptor = descriptor.graph

let retained_tokens descriptor =
  let functions = match descriptor.descriptors with None -> []
    | Some functions -> List.map (fun (fn : fn) -> fn.token) functions in
  match descriptor.graph with None -> functions | Some graph -> graph.token :: functions

let destroy descriptor =
  if not descriptor.destroyed then begin
    descriptor.destroyed <- true; descriptor.descriptors <- None; descriptor.graph <- None
  end

let validate_handoff () =
  if List.length callable_ids <> 2 || List.length (List.sort_uniq String.compare callable_ids) <> 2 then
    invalid_arg "MTL4StitchedFunctionDescriptor callable2 drift"
