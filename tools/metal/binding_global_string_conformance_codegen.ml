open Binding_global_string_spec

let safe_name entry =
  let generated = ocaml_name entry in
  let prefix_length = String.length "generated_global_" in
  String.sub generated prefix_length (String.length generated - prefix_length)

let render entries =
  let output = Buffer.create 16384 in
  Buffer.add_string output
    "module Make\n  (Api : sig\n    type error\n    type common_counter\n    type common_counter_set\n    val common_counter_to_string : common_counter -> string\n    val common_counter_set_to_string : common_counter_set -> string\n    val pp_error : Format.formatter -> error -> unit\n";
  List.iter
    (fun entry ->
      let result_type =
        match entry.family with
        | Common_counter -> "common_counter"
        | Common_counter_set -> "common_counter_set"
        | Error_domain | Error_user_info_key | Device_notification -> "string"
      in
      Printf.bprintf output "    val %s : unit -> (%s, error) result\n"
        (safe_name entry) result_type)
    entries;
  Buffer.add_string output
    "  end)\n  (Accounting : sig\n    type snapshot\n    val snapshot : unit -> snapshot\n    val equal : snapshot -> snapshot -> bool\n  end) = struct\n\
     let get = function\n\
       | Ok value -> value\n\
       | Error error -> failwith (Format.asprintf \"%a\" Api.pp_error error)\n\
     let require condition message = if not condition then failwith message\n\n\
     let run () =\n\
       let before = Accounting.snapshot () in\n";
  List.iter
    (fun entry ->
      let name = safe_name entry in
      let to_string =
        match entry.family with
        | Common_counter -> "Api.common_counter_to_string "
        | Common_counter_set -> "Api.common_counter_set_to_string "
        | Error_domain | Error_user_info_key | Device_notification -> ""
      in
      Printf.bprintf output
        "    let first_value_%s = get (Api.%s ()) in\n    let first_%s = %sfirst_value_%s in\n    require (String.length first_%s > 0) %S;\n    let second_value_%s = get (Api.%s ()) in\n    let second_%s = %ssecond_value_%s in\n    require (String.equal first_%s second_%s) %S;\n    require (first_%s != second_%s) %S;\n"
        name name name to_string name name (entry.name ^ " returned an empty NSString")
        name name name to_string name name name (entry.name ^ " changed between reads")
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

let render_executable entries =
  render entries
  ^ {|

module Api = struct
  type error = Metal.error
  type common_counter = Metal.Global.Common_counter.t
  type common_counter_set = Metal.Global.Common_counter_set.t
  let common_counter_to_string = Metal.Global.Common_counter.to_string
  let common_counter_set_to_string = Metal.Global.Common_counter_set.to_string
  let pp_error = Metal.pp_error
  include Metal.Global
end

module Accounting = struct
  type snapshot = int * int64 * int64

  let snapshot () =
    match Metal.Release_queue.stats () with
    | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)
    | Ok stats ->
        stats.live_handles, stats.total_created, stats.total_released

  let equal = ( = )
end

module Test = Make (Api) (Accounting)
let () = Test.run ()
|}
