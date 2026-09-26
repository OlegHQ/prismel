open Procedural

module Mesh_cache = Lru.Make (Int)

type stats = { hits : int; misses : int; retained : int }

type t = {
  session : Session.t;
  max_entries : int;
  max_payload_bytes : int;
  cache : Prismel.Mesh.t Mesh_cache.t;
  mutable hits : int;
  mutable misses : int;
}

let create ~max_entries ~max_payload_bytes session =
  if max_entries < 0 then Error "Bridge.create: max_entries must be non-negative"
  else if max_payload_bytes < 0 then
    Error "Bridge.create: max_payload_bytes must be non-negative"
  else Ok { session; max_entries; max_payload_bytes;
            cache = Mesh_cache.create ~byte_capacity:max_payload_bytes max_entries;
            hits = 0; misses = 0 }

let session bridge = bridge.session

let context_of_frame ?seed ?domains ?grain (frame : Prismel.Frame.t) =
  Context.create ~frame:(Int64.of_int frame.count) ~time:frame.time ?seed ?domains
    ?grain ()

let mesh ?cancel bridge geometry =
  if Session.is_closed bridge.session then Error (Pdk.Error.make
      ~operation:"bridge_mesh" ~code:"session_closed" "Bridge.mesh: session is closed")
  else
    let id = Pdk.Geometry.data_id geometry in
    match Mesh_cache.find bridge.cache id with
    | mesh -> bridge.hits <- bridge.hits + 1; Ok mesh
    | exception Not_found ->
        bridge.misses <- bridge.misses + 1;
        Result.bind (Pdk_prismel.Prismel_mesh.to_mesh ?cancel geometry) (fun mesh ->
          match cancel with
          | Some token when Pdk.Cancel.is_cancelled token ->
              Error (Pdk.Error.make ~operation:"bridge_mesh" ~code:"cancelled"
                "mesh conversion was cancelled")
          | _ ->
              let bytes = Pdk.Geometry.payload_bytes geometry in
              if bridge.max_entries > 0 && bytes <= bridge.max_payload_bytes then
                Mesh_cache.add bridge.cache ~bytes id mesh;
              Ok mesh)

let cook_to_mesh bridge ~context node =
  match Session.cook bridge.session ~context node with
  | Error _ as error -> error
  | Ok output ->
      (match mesh ~cancel:(Context.cancel_token context) bridge output.geometry with
       | Ok mesh -> Ok (mesh, output.diagnostics)
       | Error cause ->
           Error (Diagnostic.error ~code:(Pdk.Error.code cause)
             ~cause:(Pdk.Error.to_string cause)
             ~hints:(Pdk.Error.hints cause)
             "cooked PDK geometry cannot be converted to a Prismel mesh"
             |> Diagnostic.prepend_trace (Node.trace node)))

let cook_to_instances bridge ~context instances =
  Result.map (fun (mesh, diagnostics) ->
    mesh, Instances.transforms instances, diagnostics)
    (cook_to_mesh bridge ~context (Instances.source instances))

let cook_to_scene3 ?material ?texture ?mode ?cull ?shading
    bridge ~context instances =
  Result.map (fun (mesh, transforms, diagnostics) ->
    Prismel.Scene3.instances_array ?material ?texture ?mode ?cull ?shading
      mesh transforms,
    diagnostics)
    (cook_to_instances bridge ~context instances)

let stats bridge =
  { hits = bridge.hits; misses = bridge.misses;
    retained = Mesh_cache.length bridge.cache }

let clear bridge = Mesh_cache.clear bridge.cache
