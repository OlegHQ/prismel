(* The .plisp file a running sketch was built from: found once, polled for edits,
   saved over.  Immutable; the caller keeps the returned value.  [digest] is the
   SHA-256 of the text the running document last came from (built from, reloaded
   or saved), so an edit from any other writer differs from it. *)

type t = { file : string; digest : string; mtime : float; polled : float; broken : bool }

let sha = Editor_document.Contexts.sha256
let stat file = try Some (Unix.stat file) with Unix.Unix_error _ -> None
let read file = Editor_core.Store.read_text ~filename:file

let interval = 0.5

(* the file as it is now, whose text has [digest] *)
let synced ~file ~digest =
  { file; digest; mtime = Option.fold ~none:0. ~some:(fun s -> s.Unix.st_mtime) (stat file);
    polled = neg_infinity; broken = false }

(* No mtime is remembered: the first poll reads the file, so a file that already differs from
   the text the sketch was built from (edited since the build) reloads at once. *)
let at ~file ~digest = { (synced ~file ~digest) with mtime = neg_infinity }

(* the first [dune-project] at or above [dir] that is not inside a [_build] *)
let rec root dir =
  if not (List.mem "_build" (String.split_on_char '/' dir))
     && Sys.file_exists (Filename.concat dir "dune-project") then Some dir
  else let parent = Filename.dirname dir in if parent = dir then None else root parent

let find ~path ~digest =
  let absolute p = if Filename.is_relative p then Filename.concat (Sys.getcwd ()) p else p in
  List.find_map (fun start ->
    Option.bind (root start) (fun dir ->
      let file = Filename.concat dir path in
      if Sys.file_exists file then Some (at ~file ~digest) else None))
    [ Filename.dirname (absolute Sys.executable_name); Sys.getcwd () ]
  (* ponytail: a sketch launched from outside its project has no source and only presets *)

let file t = t.file

(* One [stat] per interval; the text when the file changed and is not what the document has. *)
let poll ~now t =
  if now -. t.polled < interval then t, None
  else
    let t = { t with polled = now } in
    match stat t.file with
    | Some { Unix.st_mtime; _ } when st_mtime <> t.mtime ->
        let t = { t with mtime = st_mtime } in
        (match read t.file with
         | Ok text when t.broken || sha text <> t.digest -> t, Some text
         | Ok _ | Error _ -> t, None)
    | Some _ | None -> t, None

let accepted t text = { t with digest = sha text; broken = false }
let rejected t = { t with broken = true }

(* Only over the text the document came from; the file keeps its permissions
   (a temporary file is created 0600). *)
let save t text =
  let text = if String.ends_with ~suffix:"\n" text then text else text ^ "\n" in
  match read t.file with
  | Ok disk when sha disk = t.digest ->
      let perm = Option.fold ~none:0o644 ~some:(fun s -> s.Unix.st_perm) (stat t.file) in
      Result.map (fun () ->
        (try Unix.chmod t.file perm with Unix.Unix_error _ -> ());
        { (synced ~file:t.file ~digest:(sha text)) with polled = t.polled })
        (Editor_core.Store.write_text ~filename:t.file text)
      |> Result.map_error (fun m -> `Failed m)
  | Ok _ | Error _ -> Error `Changed
