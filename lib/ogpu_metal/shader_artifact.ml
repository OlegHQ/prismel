type metadata={source_hash:string;artifact_hash:string;compiler:string;sdk:string;target:string;deployment:string;flags:string list}
type t={metallib:string;metadata:metadata}
let error text=Error(Ogpu.Error.make"Ogpu_metal.Shader_artifact.load"Ogpu.Error.Invalid_argument text)
let hash_file path=try Ok(Digest.to_hex(Digest.file path))with Sys_error text->Error(Ogpu.Error.make"Ogpu_metal.Shader_artifact.hash_file"Ogpu.Error.Invalid_argument text)
let fields path=try let input=open_in_bin path in Fun.protect~finally:(fun()->close_in input)(fun()->let rec loop values=match input_line input with line->(match String.index_opt line '=' with None->raise(Exit)|Some i->loop((String.sub line 0 i,String.sub line(i+1)(String.length line-i-1))::values))|exception End_of_file->List.rev values in Ok(loop[]))with Sys_error text->error text|Exit->error"artifact metadata has a malformed line"
let load ~source ~metallib ~metadata:path=if Filename.is_relative metallib||Filename.is_relative path then error"artifact and metadata paths must be absolute"else match fields path,hash_file metallib with Error e,_->Error e|_,Error e->Error e|Ok values,Ok actual->let get key=List.assoc_opt key values in match get"version",get"source_hash",get"artifact_hash",get"compiler",get"sdk",get"target",get"deployment",get"flags"with
  |Some"1",Some source_hash,Some artifact_hash,Some compiler,Some sdk,Some target,Some deployment,Some flags when source_hash=Digest.to_hex(Digest.string(Bytes.to_string(Ogpu.Shader.bytes source)))&&artifact_hash=actual&&target="air64-apple-macosx"&&compiler<>""&&sdk<>""&&deployment<>""->Ok{metallib;metadata={source_hash;artifact_hash;compiler;sdk;target;deployment;flags=if flags=""then[]else String.split_on_char ' ' flags}}
  |Some"1",_,_,_,_,_,_,_->error"artifact provenance, hash, target, or deployment is incompatible"
  |_->error"artifact metadata is incomplete or has an unsupported version"
let metallib value=value.metallib
let metadata value=value.metadata
