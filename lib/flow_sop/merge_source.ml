(* The [:source_attribute] / [:source_base] of a lowered [sop/merge].  The lowering already tags
   every primitive with the input it came from ([tag], [base + input index]); a program that names
   an attribute of its own gets it from a second merge of the same inputs, so its values and its
   handling of inputs that carry the attribute already are those of [Rdk.Mesh_merge]. *)

let node ~tag ~attribute ~base ~source_base inputs =
  Sop.Node.Private.make_geometry ~label:"Merge" ~operation:"merge" ~version:1
    ~parameters:(Printf.sprintf "tag=%S;base=%d;source=%S;source_base=%d" tag base attribute
      source_base)
    ~cook_mode:Sop.Node.Generic ~dependencies:Sop.Context.Dependencies.static
    ~inputs:(Array.of_list inputs)
    (fun ~node_id:_ context geometries ->
      let failed error = Error (Sop.Diagnostic.error ~code:(Rdk.Error.code error)
        ~cause:(Rdk.Error.to_string error) ~hints:(Rdk.Error.hints error)
        (Rdk.Error.operation error ^ " could not produce valid geometry")) in
      let merge ~source_attribute ~source_base =
        Rdk.Mesh_merge.run ~cancel:(Sop.Context.cancel_token context)
          ~grain:(Sop.Context.grain context) ~source_attribute ~source_base
          (Array.to_list geometries) in
      match merge ~source_attribute:tag ~source_base:base, merge ~source_attribute:attribute ~source_base with
      | Error error, _ | _, Error error -> failed error
      | Ok tagged, Ok named ->
          let owner = Rdk.Attribute.Primitive in
          match Rdk.Geometry.find_attribute ~owner attribute named with
          | Some values when Rdk.Geometry.find_attribute ~owner attribute tagged = None ->
              (match Rdk.Geometry.with_attribute values tagged with
               | Ok geometry ->
                   Ok Sop.Node.Private.{ geometry; diagnostics = []; instances = None }
               | Error message ->
                   Error (Sop.Diagnostic.error ~code:"invalid_geometry" ~cause:message
                     ~hints:[] "merge could not produce valid geometry"))
          | _ -> Ok Sop.Node.Private.{ geometry = tagged; diagnostics = []; instances = None })
