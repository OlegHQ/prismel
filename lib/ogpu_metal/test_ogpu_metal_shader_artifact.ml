open Ogpu_metal
let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let expect_invalid=function Error e when e.Ogpu.Error.kind=Invalid_argument->()|_->failwith"expected invalid offline artifact"
let source="kernel void artifact_kernel() {}"
let shader=get(Ogpu.Shader.create{backend="metal";label=Some"artifact";bytes=Bytes.of_string source;entry_points=[{name="artifact_kernel";stage=Compute}];bindings=[]})
let write path text=let channel=open_out_bin path in Fun.protect~finally:(fun()->close_out channel)(fun()->output_string channel text)
let ()=
  let metallib=Filename.temp_file"prismel-artifact"".metallib"and metadata=Filename.temp_file"prismel-artifact"".metadata"in
  Fun.protect~finally:(fun()->Sys.remove metallib;Sys.remove metadata)(fun()->
    write metallib"not a real metallib";let artifact_hash=get(Shader_artifact.hash_file metallib)and source_hash=Digest.to_hex(Digest.string source)in
    write metadata(Printf.sprintf"version=1\nsource_hash=%s\nartifact_hash=%s\ncompiler=metal-test\nsdk=26.5\ntarget=air64-apple-macosx\ndeployment=13.0\nflags=-c -target air64-apple-macosx\n"source_hash artifact_hash);
    let artifact=get(Shader_artifact.load~source:shader~metallib~metadata)in if(Shader_artifact.metadata artifact).artifact_hash<>artifact_hash then failwith"artifact metadata snapshot mismatch";
    write metallib"drift";expect_invalid(Shader_artifact.load~source:shader~metallib~metadata);
    expect_invalid(Shader_artifact.load~source:shader~metallib:(metallib^".missing")~metadata));
  print_endline"ogpu_metal shader artifact: deterministic provenance/drift/missing checks; offline execution requires full Xcode"
