(* One dependency gate over the real library graph, read from every
   lib/**/dune. Rules are "may never reach" constraints on the transitive
   closure plus token scans for Metal outside its backends and for any
   alternate renderer or backend selector. Known violations
   are listed with the plan item that removes them; delete an exception when
   its item lands, and the gate then keeps it fixed. Run from the repo root. *)

(* ---- a tiny s-expression reader: enough for dune files ---- *)
type sexp = Atom of string | List of sexp list

let parse text =
  let n = String.length text and i = ref 0 in
  let rec skip () =
    if !i < n then match text.[!i] with
      | ' ' | '\n' | '\t' | '\r' -> incr i; skip ()
      | ';' -> while !i < n && text.[!i] <> '\n' do incr i done; skip ()
      | _ -> () in
  let rec item () =
    skip ();
    match text.[!i] with
    | '(' -> incr i; let rec items acc = skip ();
               if text.[!i] = ')' then (incr i; List (List.rev acc))
               else items (item () :: acc) in items []
    | '"' -> incr i; let start = !i in
        while text.[!i] <> '"' do (if text.[!i] = '\\' then incr i); incr i done;
        incr i; Atom (String.sub text start (!i - start - 1))
    | _ -> let start = !i in
        while !i < n && not (String.contains " \n\t\r()\";" text.[!i]) do incr i done;
        Atom (String.sub text start (!i - start)) in
  let rec all acc = skip (); if !i >= n then List.rev acc else all (item () :: acc) in
  all []

let read path = In_channel.with_open_bin path In_channel.input_all

let rec files dir = Sys.readdir dir |> Array.to_list |> List.concat_map (fun name ->
  let path = Filename.concat dir name in
  if Sys.is_directory path then (if name = "_build" then [] else files path) else [path])

(* library name -> direct in-repo dependencies (public names resolved) *)
let graph roots =
  let stanzas = List.concat_map files roots
    |> List.filter (fun p -> Filename.basename p = "dune")
    |> List.concat_map (fun p -> parse (read p) |> List.filter_map (function
      | List (Atom "library" :: fields) ->
          let field key = List.find_map (function
            | List (Atom k :: values) when k = key -> Some values | _ -> None) fields in
          let atoms = function Some v -> List.filter_map (function Atom a -> Some a | _ -> None) v | None -> [] in
          (match atoms (field "name") with
           | [name] -> Some (name, atoms (field "public_name"), atoms (field "libraries"))
           | _ -> None)
      | _ -> None)) in
  let resolve = Hashtbl.create 64 in
  List.iter (fun (name, public, _) ->
    Hashtbl.replace resolve name name; List.iter (fun p -> Hashtbl.replace resolve p name) public) stanzas;
  List.map (fun (name, _, deps) -> name, List.filter_map (Hashtbl.find_opt resolve) deps) stanzas

let reach graph =
  let memo = Hashtbl.create 64 in
  let rec go name = match Hashtbl.find_opt memo name with
    | Some set -> set
    | None -> Hashtbl.replace memo name [];
        let direct = Option.value ~default:[] (List.assoc_opt name graph) in
        let set = List.sort_uniq compare (direct @ List.concat_map go direct) in
        Hashtbl.replace memo name set; set in
  go

let gpu = ["sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"; "metal"; "ogpu_core"; "ogpu"; "ogpu_mock"; "ogpu_metal"; "ogpu_metal_native";
           "runtime"; "runtime_input"; "runtime_resources"; "scene_execution"]
let upper = ["prismel"; "editor"; "pxui"; "pxui_shell"; "pxui_graph"; "sop_ui"; "procedural"; "pdk";
             "sop_catalog"; "sketch_support"; "sketch_ui"]
let foundational = ["sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"; "metal"; "ogpu_core"; "ogpu";
                    "native_layer_token"; "scene_command"; "lru"]

(* (library, libraries it may never reach) *)
let rules =
  List.map (fun lib -> lib, "runtime" :: "runtime_resources"
                            :: "prismel_execution" :: upper) foundational
  @ [ "ogpu_core", ["sdl3"; "metal"; "ogpu_metal_native"; "ogpu_metal"];
      "ogpu", ["sdl3"; "metal"; "ogpu_metal_native"; "ogpu_metal"];
      "ogpu_mock", ["sdl3"; "metal"; "ogpu_metal_native"; "ogpu_metal"];
      "runtime", ["metal"; "ogpu_metal_native"; "ogpu_metal"];
      "scene_execution", ["metal"; "ogpu_metal_native"; "ogpu_metal"];
      "prismel_execution", ["metal"; "ogpu_metal_native"; "ogpu_metal"];
      "prismel", ["metal"; "ogpu_metal_native"; "ogpu_metal"];
      "ogpu_metal_native", ["sdl3"; "runtime"; "prismel"; "scene_execution"];
      "ogpu_metal", ["sdl3"; "runtime"; "prismel"; "scene_execution"];
      "runtime", upper; "runtime_input", upper;
      "prismel_execution", ["runtime_input"];
      "prismel", ["pxui"; "pxui_shell"; "pxui_graph"; "sop_ui"; "procedural"; "pdk";
                  "sop_catalog"; "sketch_support"; "sketch_ui"];
      "prismel_math", ["prismel"; "pdk_core"; "pdk_exact"; "pdk_spatial"; "pdk_attrib"; "pdk_gen"; "pdk_curve"; "pdk_mesh"; "pdk_boolean"; "pdk_io"; "pdk"; "pdk_prismel"; "procedural"] @ gpu;
      "pdk_core", "pdk_exact" :: "pdk_spatial" :: "pdk_attrib" :: "pdk_gen" :: "pdk_curve" :: "pdk_mesh" :: "pdk_boolean" :: "pdk_io" :: "prismel" :: "pdk" :: "pdk_prismel" :: "procedural" :: gpu;
      "pdk_exact", "pdk_spatial" :: "pdk_attrib" :: "pdk_gen" :: "pdk_curve" :: "pdk_mesh" :: "pdk_boolean" :: "pdk_io" :: "prismel" :: "pdk" :: "pdk_prismel" :: "procedural" :: gpu;
      "pdk_spatial", "pdk_attrib" :: "pdk_gen" :: "pdk_curve" :: "pdk_mesh" :: "pdk_boolean" :: "pdk_io" :: "prismel" :: "pdk" :: "pdk_prismel" :: "procedural" :: gpu;
      "pdk_attrib", "pdk_gen" :: "pdk_curve" :: "pdk_mesh" :: "pdk_boolean" :: "pdk_io" :: "prismel" :: "pdk" :: "pdk_prismel" :: "procedural" :: gpu;
      "pdk_gen", "pdk_curve" :: "pdk_mesh" :: "pdk_boolean" :: "pdk_io" :: "prismel" :: "pdk" :: "pdk_prismel" :: "procedural" :: gpu;
      "pdk_curve", "pdk_gen" :: "pdk_mesh" :: "pdk_boolean" :: "pdk_io" :: "prismel" :: "pdk" :: "pdk_prismel" :: "procedural" :: gpu;
      "pdk_mesh", "pdk_boolean" :: "pdk_io" :: "prismel" :: "pdk" :: "pdk_prismel" :: "procedural" :: gpu;
      "pdk_boolean", "pdk_io" :: "prismel" :: "pdk" :: "pdk_prismel" :: "procedural" :: gpu;
      "pdk_io", "prismel" :: "pdk" :: "pdk_prismel" :: "procedural" :: gpu;
      "pdk", "prismel" :: "pdk_prismel" :: "procedural" :: "pxui" :: "pxui_shell" :: "sop_ui" :: "sop_catalog" :: gpu;
      "procedural", "pxui" :: "pxui_shell" :: "pxui_graph" :: "sop_ui" :: "sop_catalog"
                    :: "sketch_support" :: "sketch_ui" :: gpu;
      "editor", ["pxui"; "pxui_shell"; "pxui_graph"; "sop_ui"; "sketch_ui"; "procedural";
                 "pdk"; "sop_catalog"];
      "pxui", ["editor"; "pxui_shell"; "procedural"; "pdk"; "pxui_graph";
               "sop_ui"; "sketch_support"; "sketch_ui"];
      "pxui_shell", ["procedural"; "pdk"; "sop_catalog"; "sop_ui";
                     "pxui_graph"; "sketch_support"; "sketch_ui"];
      "sop_ui", ["pxui_shell"; "pxui_graph"; "sketch_support"; "sketch_ui"; "sop_catalog"];
      "pxui_graph", ["pxui_shell"; "sop_ui"; "sketch_support"; "sketch_ui"; "sop_catalog"];
      "sop_catalog", ["pxui"; "pxui_shell"; "pxui_graph"; "sop_ui"; "sketch_support"; "sketch_ui"];
      "sketch_support", ["pxui"; "pxui_shell"; "pxui_graph"; "sop_ui"; "sketch_ui"] ]

(* Known violations: (library, reached, plan item that removes it). *)
let reach_exceptions =
  List.concat_map (fun (lib, item) -> List.map (fun g -> lib, g, item) gpu)
    [ "procedural", "K1" ]

(* identifiers outside comments and string literals *)
let code_tokens text =
  let n = String.length text and out = Buffer.create (String.length text) in
  let rec go i depth =
    if i < n then
      if i + 1 < n && text.[i] = '(' && text.[i+1] = '*' then (Buffer.add_char out ' '; go (i + 2) (depth + 1))
      else if depth > 0 && i + 1 < n && text.[i] = '*' && text.[i+1] = ')' then go (i + 2) (depth - 1)
      else if depth > 0 then go (i + 1) depth
      else if text.[i] = '"' then
        let rec skip j = if j >= n then j else if text.[j] = '\\' then skip (j + 2)
          else if text.[j] = '"' then j + 1 else skip (j + 1) in
        (Buffer.add_char out ' '; go (skip (i + 1)) 0)
      else (Buffer.add_char out text.[i]; go (i + 1) 0) in
  go 0 0; Buffer.contents out

let uses_metal text =
  let code = code_tokens text in
  let rec find i = match String.index_from_opt code i 'M', String.index_from_opt code i 'O' with
    | None, None -> false
    | a, b ->
        let j = min (Option.value a ~default:max_int) (Option.value b ~default:max_int) in
        let starts word = String.length code >= j + String.length word
          && String.sub code j (String.length word) = word
          && (j = 0 || not (match code.[j-1] with 'a'..'z'|'A'..'Z'|'0'..'9'|'_'|'.' -> true | _ -> false)) in
        (starts "Metal." || starts "Ogpu_metal." || starts "Ogpu_metal_native.") || find (j + 1) in
  find 0 || List.exists (fun w -> List.mem w ["Metal"; "Ogpu_metal"; "Ogpu_metal_native"])
    (let words = String.split_on_char ' ' (String.map (function '\n'|'\t'|';' -> ' ' | c -> c) code) in
     let rec opens = function "open" :: w :: rest -> w :: opens rest | _ :: rest -> opens rest | [] -> [] in
     opens words)

let uses_key_pressed text =
  let code = code_tokens text and token = "KeyPressed" in
  let limit = String.length code - String.length token in
  let rec find index = index <= limit &&
    (String.sub code index (String.length token) = token
     || find (index + 1)) in
  find 0

(* Native-only rendering: no second renderer, GL/Vulkan window, or backend
   selector anywhere in source text, strings and comments included. *)
let forbidden_native =
  [ "Rgba_presenter"; "create_rgba_presenter";
    "SDL_CreateRenderer"; "SDL_CreateSoftwareRenderer";
    "SDL_CreateWindowAndRenderer"; "SDL_RenderPresent";
    "SDL_RenderTexture"; "SDL_RenderGeometry"; "SDL_GL_";
    "SDL_WINDOW_OPENGL"; "SDL_WINDOW_VULKAN";
    "PRISMEL_RENDER_TARGET"; "PRISMEL_HEADLESS"; "PRISMEL_WEB";
    "PRISMEL_RENDERER"; "PRISMEL_BACKEND"; "PRISMEL_OPENGL";
    "--renderer"; "--backend"; ("--head" ^ "less"); ("--open" ^ "gl"); "Dynlink" ]

let contains text needle =
  let limit = String.length text - String.length needle in
  let rec find index = index <= limit &&
    (String.sub text index (String.length needle) = needle || find (index + 1)) in
  find 0

let violations graph ~scan =
  let reach = reach graph in
  let direct_errors = List.filter_map (fun (lib, dep, message) ->
    if List.mem dep (Option.value ~default:[] (List.assoc_opt lib graph))
    then Some message else None)
    (["pxui", "sdl3", "pxui depends directly on sdl3 (text input belongs to Scene/runtime)";
      "pxui", "scene_command", "pxui depends directly on scene_command (UI batches belong to Prismel.Scene)"]
     @ List.map (fun sdl -> "prismel", sdl,
         "prismel depends directly on " ^ sdl ^ " (SDL services belong to runtime)")
         ["sdl3"; "sdl3_image"; "sdl3_ttf"; "sdl3_mixer"]) in
  let edge_errors = List.concat_map (fun (lib, forbidden) ->
    List.filter_map (fun target ->
      if List.mem target (reach lib)
         && not (List.exists (fun (l, t, _) -> l = lib && t = target) reach_exceptions)
      then Some (Printf.sprintf "%s reaches forbidden library %s" lib target) else None)
      forbidden) rules in
  let native_errors = List.concat_map (fun (path, text) ->
    List.filter_map (fun needle -> if contains text needle
      then Some (Printf.sprintf "%s names %s (Metal is the only renderer)" path needle)
      else None) forbidden_native) scan in
  let ocaml path = Filename.check_suffix path ".ml" || Filename.check_suffix path ".mli" in
  let token_errors = List.filter_map (fun (path, text) ->
    if not (ocaml path) then None else
    let allowed = String.starts_with ~prefix:"lib/metal/" path
      || String.starts_with ~prefix:"lib/ogpu_metal/" path in
    if not allowed && uses_metal text then Some (path ^ " uses Metal outside lib/metal and lib/ogpu_metal")
    else if (String.starts_with ~prefix:"lib/pxui_graph/" path
          || String.starts_with ~prefix:"lib/sop_ui/" path)
        && uses_key_pressed text then
      Some (path ^ " matches KeyPressed inside a presentation adapter")
    else None) scan in
  direct_errors @ edge_errors @ token_errors @ native_errors

let run () =
  let has_library_field path name key value =
    parse (read path) |> List.exists (function
      | List (Atom "library" :: fields) ->
          List.mem (List [Atom "name"; Atom name]) fields
          && List.mem (List [Atom key; Atom value]) fields
      | _ -> false) in
  if not (has_library_field "lib/ogpu/dune" "ogpu" "virtual_modules" "Impl"
      && has_library_field "lib/ogpu/dune" "ogpu" "default_implementation" "ogpu_metal"
      && has_library_field "lib/ogpu_metal/dune" "ogpu_metal" "implements" "ogpu"
      && has_library_field "lib/ogpu_mock/dune" "ogpu_mock" "implements" "ogpu") then
    failwith "OGPU virtual implementations or default selection missing";
  let graph = graph ["lib"; "ppx"] in
  if List.length graph < 20 then failwith "dependency gate found too few libraries (wrong cwd?)";
  (* injected violations must fire *)
  let inject lib dep = List.map (fun (l, d) -> l, if l = lib then dep :: d else d) graph in
  List.iter (fun (lib, dep) ->
    if violations (inject lib dep) ~scan:[] = [] then
      failwith (Printf.sprintf "gate accepted injected edge %s -> %s" lib dep))
    ["ogpu_core", "metal"; "ogpu", "ogpu_metal_native"; "ogpu_mock", "metal"; "prismel", "pxui"; "pxui", "procedural"; "pxui", "sdl3"; "pxui", "scene_command"; "sdl3", "prismel";
     "pdk", "prismel"; "pdk_core", "pdk_exact";
     "pdk_exact", "pdk_boolean"; "pdk_spatial", "pdk_attrib";
     "pdk_attrib", "pdk_boolean"; "pdk_gen", "pdk_curve";
     "pdk_curve", "pdk_gen"; "pdk_mesh", "pdk_boolean"; "pdk_boolean", "pdk_io"; "pdk_io", "pdk";
     "pdk_core", "prismel";
     "prismel_math", "prismel"; "prismel_execution", "runtime_input";
     "prismel", "sdl3_ttf"];
  if violations graph ~scan:["lib/prismel/injected.ml", "let x = Metal.Device.system_default"] = []
     || violations graph ~scan:["lib/prismel/injected.ml", "open Ogpu_metal_native"] = []
     || violations graph ~scan:["lib/prismel/injected.ml", "open Ogpu_metal"] = [] then
    failwith "gate accepted injected Metal reference";
  if violations graph ~scan:["lib/prismel/ok.ml", "(* Metal.foo *) let s = \"Metal.framework\""] <> [] then
    failwith "gate flagged Metal inside a comment or string";
  if violations graph ~scan:["lib/pxui_graph/injected.ml", "Event.KeyPressed key"] = [] then
    failwith "gate accepted adapter key handling";
  if violations graph ~scan:["lib/pxui_graph/ok.ml", "(* KeyPressed *) let s = \"KeyPressed\""] <> [] then
    failwith "gate flagged KeyPressed inside a comment or string";
  if violations graph ~scan:["lib/sdl3/injected.c", "SDL_CreateRenderer(window, 0)"] = []
     || violations graph ~scan:["lib/prismel/injected.ml", "Sys.getenv \"PRISMEL_BACKEND\""] = [] then
    failwith "gate accepted an injected alternate renderer or backend selector";
  let scan = List.concat_map files ["lib"; "examples"; "sketches"]
    |> List.filter (fun p -> List.exists (Filename.check_suffix p)
      [".ml"; ".mli"; ".c"; ".h"; ".m"])
    |> List.map (fun p -> p, read p) in
  (* The one native path stays wired: SDL Metal view -> OGPU driver. *)
  List.iter (fun (path, anchor) -> if not (contains (read path) anchor) then
    failwith (path ^ " lost native anchor " ^ anchor))
    [ "lib/sdl3/sdl3_stubs.c", "SDL_Metal_CreateView";
      "lib/runtime/runtime.ml", "Ogpu.Impl.create_driver";
      "lib/prismel_execution/prismel_execution.ml", "Runtime.create" ];
  match violations graph ~scan with
  | [] -> Printf.printf "dependency gate: %d libraries, %d rules, %d listed exceptions\n"
            (List.length graph) (List.length rules)
            (List.length reach_exceptions)
  | errors -> List.iter prerr_endline errors; exit 1
