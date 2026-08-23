open Binding_global_string_spec

let safe_name entry =
  let generated = ocaml_name entry in
  let prefix_length = String.length "generated_global_" in
  String.sub generated prefix_length (String.length generated - prefix_length)

let render entries =
  let output = Buffer.create 16384 in
  Buffer.add_string output
    "module Make\n  (Api : sig\n";
  List.iter
    (fun entry ->
      Printf.bprintf output "    val %s : unit -> (string, string) result\n"
        (safe_name entry))
    entries;
  Buffer.add_string output
    "  end)\n  (Accounting : sig\n    type snapshot\n    val snapshot : unit -> snapshot\n    val equal : snapshot -> snapshot -> bool\n  end) = struct\n\
     let get = function Ok value -> value | Error message -> failwith message\n\
     let require condition message = if not condition then failwith message\n\n\
     let run () =\n\
       let before = Accounting.snapshot () in\n";
  List.iter
    (fun entry ->
      let name = safe_name entry in
      Printf.bprintf output
        "    let first_%s = get (Api.%s ()) in\n    require (String.length first_%s > 0) %S;\n    let second_%s = get (Api.%s ()) in\n    require (String.equal first_%s second_%s) %S;\n    require (first_%s != second_%s) %S;\n"
        name name name (entry.name ^ " returned an empty NSString")
        name name name name (entry.name ^ " changed between reads")
        name name (entry.name ^ " did not return an independent OCaml copy"))
    entries;
  Buffer.add_string output
    "    for _iteration = 1 to 64 do\n";
  List.iter
    (fun entry ->
      let name = safe_name entry in
      Printf.bprintf output "      ignore (get (Api.%s ()));\n" name)
    entries;
  Buffer.add_string output
    "    done;\n\
       let after = Accounting.snapshot () in\n\
       require (Accounting.equal before after)\n\
         \"Metal global NSString reads changed native handle accounting\"\n\
     end\n";
  Buffer.contents output

