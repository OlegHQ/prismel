type stage = Vertex | Fragment | Compute
type binding_kind = Uniform_buffer | Storage_buffer | Sampled_texture | Storage_texture | Sampler
type entry_point = { name : string; stage : stage }
type binding =
  { group : int; binding : int; kind : binding_kind; visibility : stage list }
type descriptor =
  { backend : string
  ; label : string option
  ; bytes : bytes
  ; entry_points : entry_point list
  ; bindings : binding list
  }
type t =
  { backend : string
  ; label : string option
  ; artifact : bytes
  ; entries : entry_point list
  ; layout : binding list
  ; hash : string
  }

let error message = Error (Error.make "Ogpu.Shader.create" Error.Invalid_argument message)
let valid_text value = value <> "" && not (String.contains value '\000')
let stage_code = function Vertex -> "v" | Fragment -> "f" | Compute -> "c"
let kind_code = function
  | Uniform_buffer -> "ub" | Storage_buffer -> "sb" | Sampled_texture -> "st"
  | Storage_texture -> "wt" | Sampler -> "s"

let add_field output value =
  Buffer.add_string output (string_of_int (String.length value));
  Buffer.add_char output ':';
  Buffer.add_string output value

let canonical (descriptor : descriptor) =
  let output = Buffer.create (Bytes.length descriptor.bytes + 128) in
  add_field output descriptor.backend;
  add_field output (Option.value descriptor.label ~default:"");
  add_field output (Bytes.unsafe_to_string descriptor.bytes);
  List.iter (fun entry -> add_field output entry.name; add_field output (stage_code entry.stage))
    descriptor.entry_points;
  List.iter
    (fun binding ->
      add_field output (string_of_int binding.group);
      add_field output (string_of_int binding.binding);
      add_field output (kind_code binding.kind);
      List.iter (fun stage -> add_field output (stage_code stage)) binding.visibility)
    descriptor.bindings;
  Buffer.contents output

let validate_entries entries =
  let rec loop seen = function
    | [] -> Ok ()
    | entry :: _ when not (valid_text entry.name) -> error "entry-point name is empty or contains NUL"
    | entry :: _ when List.mem entry.name seen -> error "duplicate entry point"
    | entry :: rest -> loop (entry.name :: seen) rest
  in
  loop [] entries

let validate_bindings bindings =
  let rec loop seen = function
    | [] -> Ok ()
    | value :: _ when value.group < 0 || value.binding < 0 -> error "binding indices must be nonnegative"
    | value :: _ when value.visibility = [] -> error "binding visibility is empty"
    | value :: _ when List.sort_uniq compare value.visibility <> value.visibility ->
        error "binding visibility must be sorted and unique"
    | value :: _ when List.mem (value.group, value.binding) seen -> error "duplicate reflected binding"
    | value :: rest -> loop ((value.group, value.binding) :: seen) rest
  in
  loop [] bindings

let create (descriptor : descriptor) =
  if descriptor.backend <> "metal" && descriptor.backend <> "mock" then
    error "unknown shader backend"
  else if Option.fold ~none:false ~some:(fun value -> not (valid_text value)) descriptor.label then
    error "shader label is empty or contains NUL"
  else if Bytes.length descriptor.bytes = 0 then error "shader artifact is empty"
  else
    match validate_entries descriptor.entry_points with
    | Error _ as result -> result
    | Ok () ->
        match validate_bindings descriptor.bindings with
        | Error _ as result -> result
        | Ok () ->
            let descriptor = { descriptor with bytes = Bytes.copy descriptor.bytes } in
            Ok { backend = descriptor.backend; label = descriptor.label
               ; artifact = descriptor.bytes; entries = descriptor.entry_points
               ; layout = descriptor.bindings; hash = Digest.to_hex (Digest.string (canonical descriptor)) }

let backend value = value.backend
let label value = value.label
let bytes value = Bytes.copy value.artifact
let entry_points value = value.entries
let bindings value = value.layout
let provenance_hash value = value.hash
