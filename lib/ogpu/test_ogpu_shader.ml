let fail message = raise (Failure message)
let ok = function Ok value -> value | Error error -> fail (Ogpu.Error.to_string error)
let rejected = function Error (error : Ogpu.Error.t) when error.kind = Invalid_argument -> () | _ -> fail "expected rejection"

let entry name stage : Ogpu.Shader.entry_point = { name; stage }
let binding group binding kind visibility : Ogpu.Shader.binding = { group; binding; kind; visibility }
let descriptor bytes : Ogpu.Shader.descriptor =
  { backend = "mock"; label = Some "deterministic"
  ; bytes
  ; entry_points = [ entry "main_vertex" Vertex; entry "main_fragment" Fragment ]
  ; bindings =
      [ binding 0 0 Uniform_buffer [ Vertex; Fragment ]
      ; binding 0 1 Sampled_texture [ Fragment ] ] }

let snapshot value =
  Ogpu.Shader.backend value, Ogpu.Shader.label value, Ogpu.Shader.bytes value,
  Ogpu.Shader.entry_points value, Ogpu.Shader.bindings value, Ogpu.Shader.provenance_hash value

let run () =
  let source = Bytes.of_string "stable shader bytes" in
  let first = ok (Ogpu.Shader.create (descriptor source)) in
  Bytes.fill source 0 (Bytes.length source) 'x';
  if Ogpu.Shader.bytes first <> Bytes.of_string "stable shader bytes" then fail "artifact aliases input bytes";
  let copy = Ogpu.Shader.bytes first in
  Bytes.set copy 0 'x';
  if Bytes.get (Ogpu.Shader.bytes first) 0 = 'x' then fail "artifact snapshot is mutable";
  let make () = ok (Ogpu.Shader.create (descriptor (Bytes.of_string "stable shader bytes"))) |> snapshot in
  let sequential = make () in
  let workers = Array.init 4 (fun _ -> Domain.spawn make) in
  Array.iter (fun worker -> if Domain.join worker <> sequential then fail "domain-dependent artifact") workers;
  rejected (Ogpu.Shader.create { (descriptor (Bytes.of_string "x")) with backend = "future" });
  rejected (Ogpu.Shader.create { (descriptor Bytes.empty) with label = None });
  rejected (Ogpu.Shader.create { (descriptor (Bytes.of_string "x")) with label = Some "" });
  rejected (Ogpu.Shader.create { (descriptor (Bytes.of_string "x")) with
    entry_points = [ entry "same" Vertex; entry "same" Fragment ] });
  rejected (Ogpu.Shader.create { (descriptor (Bytes.of_string "x")) with
    bindings = [ binding 1 2 Storage_buffer [ Compute ]; binding 1 2 Sampler [ Compute ] ] });
  rejected (Ogpu.Shader.create { (descriptor (Bytes.of_string "x")) with
    bindings = [ binding 0 0 Uniform_buffer [ Fragment; Vertex ] ] });
  let compiled_descriptor =
    { (descriptor (Bytes.of_string "compiled bytes")) with backend = "metal"
    ; entry_points = [entry "kernel" Compute]
    ; bindings = [binding 0 0 Storage_buffer [Compute]] } in
  let compiled = ok (Ogpu.Shader.create_metallib compiled_descriptor
    ~constants:["TRIPLE",Bool true]) in
  if Ogpu.Shader.format compiled <> Metallib then fail "compiled shader format lost";
  if Ogpu.Shader.constants compiled <> ["TRIPLE",Bool true] then
    fail "function constants lost";
  let other = ok (Ogpu.Shader.create_metallib compiled_descriptor
    ~constants:["TRIPLE",Bool false]) in
  if Ogpu.Shader.provenance_hash compiled = Ogpu.Shader.provenance_hash other then
    fail "function constant did not change shader identity";
  rejected (Ogpu.Shader.create_metallib compiled_descriptor
    ~constants:["TRIPLE",Bool true;"TRIPLE",Bool false]);
  rejected (Ogpu.Shader.create_metallib compiled_descriptor
    ~constants:["",Bool true]);
  rejected (Ogpu.Shader.create_metallib (descriptor (Bytes.of_string "x"))
    ~constants:[]);
  rejected (Ogpu.Shader.create_metallib
    { (descriptor (Bytes.of_string "x")) with backend = "metal" }
    ~constants:["TRIPLE",Bool true]);
  print_endline "OGPU immutable deterministic shader artifact passed"
