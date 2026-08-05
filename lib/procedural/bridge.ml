let to_mesh = Pdk.Prismel_mesh.to_mesh

let cook_to_mesh session ~context node =
  match Session.cook session ~context node with
  | Error _ as error -> error
  | Ok output ->
      (match Session.mesh ~cancel:(Context.cancel_token context)
          session output.geometry with
       | Ok mesh -> Ok (mesh, output.diagnostics)
       | Error cause ->
           Error (Diagnostic.error ~code:(Pdk.Error.code cause)
             ~cause:(Pdk.Error.to_string cause)
             ~hints:(Pdk.Error.hints cause)
             "cooked PDK geometry cannot be converted to a Prismel mesh"
             |> Diagnostic.prepend_trace (Node.trace node)))

let cook_to_instances session ~context instances =
  let node = Instances.source instances in
  Result.map (fun (mesh, diagnostics) ->
    mesh, Instances.transforms instances, diagnostics)
    (cook_to_mesh session ~context node)

let cook_to_scene3 ?material ?texture ?shader ?mode ?cull ?shading
    session ~context instances =
  Result.map (fun (mesh, diagnostics) ->
    Instances.Private.scene3 ?material ?texture ?shader ?mode ?cull ?shading
      mesh instances,
    diagnostics)
    (cook_to_mesh session ~context (Instances.source instances))
