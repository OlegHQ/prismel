type severity = Info | Warning

type trace = {
  node_id : int;
  label : string;
  operation : string;
}

type t = {
  severity : severity;
  code : string;
  message : string;
  node : trace;
}

type error = {
  code : string;
  message : string;
  trace : trace list;
  cause : string option;
  hints : string list;
}

let make severity ~node ~code message = { severity; code; message; node }
let error ?cause ?(hints = []) ~code message =
  { code; message; trace = []; cause; hints }
let prepend_trace node value = { value with trace = node :: value.trace }

let error_to_string value =
  let path =
    match value.trace with
    | [] -> ""
    | trace ->
        let labels = List.map (fun item -> item.label) trace in
        String.concat "/" labels ^ ": "
  in
  let cause = match value.cause with None -> "" | Some cause -> "\n  cause: " ^ cause in
  let hints = match value.hints with
    | [] -> ""
    | hints -> "\n  hint: " ^ String.concat "\n  hint: " hints
  in
  Printf.sprintf "%s[%s] %s%s%s" path value.code value.message cause hints
