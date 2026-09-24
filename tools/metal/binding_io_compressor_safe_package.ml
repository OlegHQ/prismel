type method_ = Lz4 | Lzfse | Lzma | Zlib
type state = Open | Failed | Finalized
type t = { path : string; method_ : method_; chunk_size : int; mutable appended : int; mutable state : state }

let callable_ids =
  [ "function:MTLIOCompressionContextAppendData"
  ; "function:MTLIOCompressionContextDefaultChunkSize"
  ; "function:MTLIOCreateCompressionContext"
  ; "function:MTLIOFlushAndDestroyCompressionContext" ]

let default_chunk_size ~native_value =
  if native_value <= 0 then Error "invalid native IO compression chunk size" else Ok native_value

let valid_path path = path <> "" && not (String.contains path '\000')

let create ~path ~method_ ~chunk_size ~native_ok =
  if not (valid_path path) then Error "invalid IO compression output path"
  else if chunk_size <= 0 then Error "IO compression chunk size must be positive"
  else if not native_ok then Error "MTLIOCreateCompressionContext returned null"
  else Ok { path = String.sub path 0 (String.length path); method_; chunk_size; appended = 0; state = Open }

let append compressor bytes ~offset ~length ~native_ok =
  if compressor.state <> Open then Error "IO compression context is not open"
  else if offset < 0 || length < 0 || offset > Bytes.length bytes || length > Bytes.length bytes - offset then
    Error "IO compression append range out of bounds"
  else if length = 0 then Ok ()
  else if compressor.appended > max_int - length then Error "IO compression byte count overflow"
  else if not native_ok then begin compressor.state <- Failed; Error "IO compression append failed" end
  else begin
    (* The native append consumes the bytes synchronously; no caller buffer is retained. *)
    compressor.appended <- compressor.appended + length;
    Ok ()
  end

let flush_and_destroy compressor ~native_status =
  match compressor.state with
  | Finalized -> Error "IO compression context already finalized"
  | Open | Failed ->
      compressor.state <- Finalized;
      native_status

let appended_bytes compressor = compressor.appended
let configuration compressor = compressor.path, compressor.method_, compressor.chunk_size
let is_finalized compressor = compressor.state = Finalized

let validate_handoff () =
  if List.length callable_ids <> 4 || List.length (List.sort_uniq String.compare callable_ids) <> 4 then
    invalid_arg "IOCompressor callable4 drift"
