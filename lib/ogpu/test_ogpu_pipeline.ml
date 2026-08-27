let fail message = raise (Failure message)
let ok = function Ok value -> value | Error error -> fail (Ogpu.Error.to_string error)
let reject = function Error (error : Ogpu.Error.t) when error.kind = Invalid_argument -> () | _ -> fail "expected rejection"
let caps = Ogpu.Capabilities.minimum_m1

let shader ~backend ~entries ~bindings =
  ok (Ogpu.Shader.create { backend; label = None; bytes = Bytes.of_string "artifact"; entry_points = entries; bindings })
let entry name stage : Ogpu.Shader.entry_point = { name; stage }
let reflected group binding kind visibility : Ogpu.Shader.binding = { group; binding; kind; visibility }
let layout device kind visibility =
  let group = ok (Ogpu.Binding.create_layout [ { binding = 0; kind; visibility } ]) in
  ok (Ogpu.Binding.create_pipeline_layout ~device ~capabilities:caps [ 0, group ])

let () =
  let device = Ogpu.Handle.create_device () in
  let compute_shader = shader ~backend:"mock" ~entries:[ entry "main" Ogpu.Shader.Compute ]
    ~bindings:[ reflected 0 0 Ogpu.Shader.Storage_buffer [ Ogpu.Shader.Compute ] ] in
  let compute_layout = layout device Ogpu.Binding.Buffer [ Ogpu.Binding.Compute ] in
  let compute () = ok (Ogpu.Pipeline.create_compute caps
    { backend = "mock"; label = Some "compute"; layout = compute_layout; shader = compute_shader; entry = "main" }) in
  let first = compute () in
  if Ogpu.Pipeline.kind first <> Ogpu.Pipeline.Compute then fail "wrong pipeline kind";
  let expected = Ogpu.Pipeline.cache_key first, Ogpu.Pipeline.description first in
  let workers = Array.init 4 (fun _ -> Domain.spawn (fun () -> let value = compute () in
    Ogpu.Pipeline.cache_key value, Ogpu.Pipeline.description value)) in
  Array.iter (fun worker -> if Domain.join worker <> expected then fail "domain-dependent pipeline key") workers;
  reject (Ogpu.Pipeline.create_compute caps
    { backend = "future"; label = None; layout = compute_layout; shader = compute_shader; entry = "main" });
  reject (Ogpu.Pipeline.create_compute caps
    { backend = "metal"; label = None; layout = compute_layout; shader = compute_shader; entry = "main" });
  reject (Ogpu.Pipeline.create_compute caps
    { backend = "mock"; label = None; layout = compute_layout; shader = compute_shader; entry = "missing" });
  let wrong_layout = layout device Ogpu.Binding.Texture [ Ogpu.Binding.Compute ] in
  reject (Ogpu.Pipeline.create_compute caps
    { backend = "mock"; label = None; layout = wrong_layout; shader = compute_shader; entry = "main" });
  let hidden_layout = layout device Ogpu.Binding.Buffer [ Ogpu.Binding.Vertex ] in
  reject (Ogpu.Pipeline.create_compute caps
    { backend = "mock"; label = None; layout = hidden_layout; shader = compute_shader; entry = "main" });
  let vertex = shader ~backend:"mock" ~entries:[ entry "vs" Ogpu.Shader.Vertex ] ~bindings:[] in
  let fragment = shader ~backend:"mock" ~entries:[ entry "fs" Ogpu.Shader.Fragment ] ~bindings:[] in
  let empty = ok (Ogpu.Binding.create_pipeline_layout ~device ~capabilities:caps []) in
  let render sample_count fragment fragment_entry = Ogpu.Pipeline.create_render caps
    { backend = "mock"; label = None; layout = empty; vertex; vertex_entry = "vs"
    ; fragment; fragment_entry; color_format = Ogpu.Pipeline.Bgra8_unorm
    ; depth_format = Ogpu.Pipeline.Depth32_float; sample_count } in
  ignore (ok (render 4 (Some fragment) (Some "fs")));
  let descriptor : Ogpu.Pipeline.render_descriptor =
    { backend = "mock"; label = None; layout = empty; vertex; vertex_entry = "vs"
    ; fragment = Some fragment; fragment_entry = Some "fs"; color_format = Ogpu.Pipeline.Bgra8_unorm
    ; depth_format = Ogpu.Pipeline.Depth32_float; sample_count = 1 } in
  let blend_keys = List.map (fun blend -> Ogpu.Pipeline.create_render ~blend caps descriptor
    |> ok |> Ogpu.Pipeline.cache_key)
    [Ogpu.Pipeline.Replace; Alpha; Add; Multiply; Screen; Subtract] in
  if List.length (List.sort_uniq String.compare blend_keys) <> 6 then
    fail "render blend state missing from canonical cache key";
  reject (render 3 (Some fragment) (Some "fs"));
  reject (render max_int (Some fragment) (Some "fs"));
  reject (render 1 (Some fragment) None);
  reject (render 1 None (Some "fs"));
  reject (Ogpu.Pipeline.create_render caps
    { backend = "mock"; label = Some ""; layout = empty; vertex; vertex_entry = "vs"
    ; fragment = None; fragment_entry = None; color_format = Ogpu.Pipeline.Rgba8_unorm
    ; depth_format = Ogpu.Pipeline.No_depth; sample_count = 1 });
  Ogpu.Handle.destroy_device device;
  print_endline "OGPU deterministic pipeline descriptions passed"
