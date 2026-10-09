module E = Flow.Eval
module P = Procedural
let (let*) = Result.bind
type t = {identity:int; width:int; height:int; fn:E.fn; sources:int list;
  inputs:P.Node.t list; program:Flow_ir.Executor.program; packed:Flow_ir.Packed.t}
let error message = Error (Flow.Diagnostic.error ~code:"E_IMAGE" message)
let prepare ~identity ~width ~height ~fn ~sources inputs =
  if width <= 0 || height <= 0 then error "Image dimensions must be positive."
  else if width > min Sys.max_floatarray_length Sys.max_string_length / 4 / height then
    error "Image dimensions exceed native storage bounds."
  else if not (Option.fold ~none:false ~some:(fun (_,body) -> body.Flow.Workspace.ty=Flow.Ty.Vec4)
      (E.Private.function_body fn)) then
    error "Image map needs an instantiated vec4 pixel body."
  else
    let uv = Array.make (width * height * 2) 0. in
    for y = 0 to height - 1 do
      let v = (float y +. 0.5) /. float height in
      for x = 0 to width - 1 do
        let i = (y * width + x) * 2 in
        uv.(i) <- (float x +. 0.5) /. float width; uv.(i + 1) <- v
      done
    done;
    let* values = E.Private.map_function
      ~signature:Flow.Ty.{params=[Vec2];result=Vec4} fn [E.Vec2_array uv] in
    let* program = Attribute_kernel.prepare ~sources inputs values in
    let ir = Flow_ir.Executor.graph program in
    match ir.nodes.(ir.roots.(0)).kind with
    | Flow_ir.Kernel {body=Packed_map packed;_} ->
        Ok {identity;width;height;fn;sources;inputs;program;packed}
    | _ ->
        (match values with
         | E.Residual r -> (match Flow_ir.Packed.compile_result r (E.Private.residual_view r).term with
             | Error (d :: _) -> Error d
             | _ -> Error (Flow.Diagnostic.error ~code:"E_KERNEL_FORM" "Image function needs a packed map body."))
         | _ -> error "Image function did not produce a pixel map.")
let program t = t.program
let node ?state ?elems t =
  P.Node.Private.make ~operation:"image/map" ~version:1
    ~parameters:(Printf.sprintf "%d:%d:%d" t.identity t.width t.height
      ^ Option.fold ~none:"" ~some:E.state_stamp state
      ^ Option.fold ~none:"" ~some:(fun xs -> Flow.Value.key_of
          ~residual:E.Private.residual_id (E.Record xs)) elems)
    ~cook_mode:P.Node.Generator
    ~dependencies:(if E.frame_dependent (E.Fn t.fn) || E.state_dependent (E.Fn t.fn)
      then P.Context.Dependencies.one Input else P.Context.Dependencies.static)
    ~inputs:(Array.of_list t.inputs) (fun ~node_id:_ context payloads ->
      let resolve = Attribute_kernel.resolve ~geometry:(fun id ->
        Option.bind (List.find_index ((=) id) t.sources)
          (fun i -> Result.to_option (P.Payload.geometry payloads.(i)))) in
      let result =
        if P.Context.cancelled context then Error (Flow.Diagnostic.error ~code:"E_CANCELLED" "Image kernel cancelled.")
        else Flow_ir.Packed.force ?state ?elems ~resolve t.packed ~live:(P.Context.input context) in
      Result.bind (Result.map_error (fun (d:Flow.Diagnostic.t) -> P.Diagnostic.error ~code:d.code d.message) result)
        (function
          | E.Vec4_array rgba -> Result.map (fun image -> P.Node.Private.{
              payload=P.Payload.Image image;diagnostics=[];instances=None})
              (P.Image.Private.of_vec4 ~context ~width:t.width ~height:t.height rgba)
          | _ -> Error (P.Diagnostic.error ~code:"E_IMAGE" "Image kernel must return vec4 pixels.")))
