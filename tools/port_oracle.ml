(* Compile the checked-in OCaml example as the independent parity oracle,
   removing only its application entry point. *)
let () =
  let source=In_channel.with_open_text Sys.argv.(1) In_channel.input_all in
  let marker="\nlet () ="in
  let rec find i=if i<0 then failwith "Example has no application entry point"
    else if String.sub source i (String.length marker)=marker then i else find(i-1)in
  print_string(String.sub source 0 (find(String.length source-String.length marker)))
