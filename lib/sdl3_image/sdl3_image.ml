type error_kind =
  | Decoder_error
  | Wrong_domain
  | Invalid_argument
  | Incompatible_version
  | Surface_error of Sdl3.error

type error = {
  operation : string;
  kind : error_kind;
  message : string;
}

let pp_error formatter error =
  Format.fprintf formatter "%s: %s" error.operation error.message

let error operation kind message = Error { operation; kind; message }

type decoded = {
  width : int;
  height : int;
  pixels : bytes;
}

external linked_version_number : unit -> int = "caml_sdl3_image_version"
external decode_file : string -> (decoded, string) result
  = "caml_sdl3_image_decode_file"
external decode_bytes_raw : bytes -> string option -> (decoded, string) result
  = "caml_sdl3_image_decode_bytes"

module Version = struct
  type t = { major : int; minor : int; patch : int }

  let compiled =
    let value = Generated_provenance.header_version in
    { major = value.major; minor = value.minor; patch = value.patch }

  let of_number value = {
    major = value / 1_000_000;
    minor = (value / 1_000) mod 1_000;
    patch = value mod 1_000;
  }

  let number value =
    (value.major * 1_000_000) + (value.minor * 1_000) + value.patch

  let stable value = value.minor mod 2 = 0 && value.patch mod 2 = 0
  let linked () = of_number (linked_version_number ())
  let stable_headers = Generated_provenance.stable_headers
  let generator_version = Generated_provenance.generator_version
  let header_sha256 = Generated_provenance.header_sha256
  let function_count = Generated_provenance.function_count
  let safe_function_count = Generated_provenance.safe_function_count

  let string value =
    Printf.sprintf "%d.%d.%d" value.major value.minor value.patch

  let check ?(release = true) () =
    let linked = linked () in
    if release && not stable_headers then
      error "SDL3_image.Version.check" Incompatible_version
        ("compiled against prerelease SDL3_image headers " ^ string compiled)
    else if number linked < number compiled then
      error "SDL3_image.Version.check" Incompatible_version
        (Printf.sprintf "linked SDL3_image %s is older than compiled headers %s"
          (string linked) (string compiled))
    else if release && not (stable linked) then
      error "SDL3_image.Version.check" Incompatible_version
        ("linked SDL3_image is a development release: " ^ string linked)
    else Ok ()
end

let contains_nul value =
  try ignore (String.index value '\x00'); true with Not_found -> false

let on_main operation callback =
  if not (Sdl3.Thread.is_initial_domain ())
      || not (Sdl3.Thread.is_sdl_main_thread ()) then
    error operation Wrong_domain
      "SDL3_image decoding must run on the initial OCaml domain and SDL main thread"
  else
    match Version.check () with
    | Error _ as failure -> failure
    | Ok () -> callback ()

let surface operation decoded =
  match Sdl3.Surface.of_rgba ~width:decoded.width ~height:decoded.height
      decoded.pixels with
  | Ok surface -> Ok surface
  | Error surface_error ->
      error operation (Surface_error surface_error)
        (Format.asprintf "%a" Sdl3.pp_error surface_error)

let load_file path =
  let operation = "SDL3_image.load_file" in
  if contains_nul path then
    error operation Invalid_argument "image path contains a NUL byte"
  else on_main operation (fun () ->
    match decode_file path with
    | Ok decoded -> surface operation decoded
    | Error message -> error operation Decoder_error message)

let load_bytes ?kind bytes =
  let operation = "SDL3_image.load_bytes" in
  match kind with
  | Some kind when kind = "" || contains_nul kind ->
      error operation Invalid_argument "decoder kind must be non-empty and NUL-free"
  | _ -> on_main operation (fun () ->
      match decode_bytes_raw bytes kind with
      | Ok decoded -> surface operation decoded
      | Error message -> error operation Decoder_error message)
