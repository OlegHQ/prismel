let ()=
 if Array.length Sys.argv<>2 then invalid_arg"expected inventory";
 let open Yojson.Safe.Util in
 let items=Yojson.Safe.from_file Sys.argv.(1)|>member"symbols"|>to_list|>List.filter_map(fun j->
  if j|>member"classification"|>to_string="unreviewed"&&j|>member"header"|>to_string="Metal/MTLFunctionStitching.h"
  then Some(Binding_function_stitching_handoff.classify~kind:(j|>member"kind"|>to_string)(j|>member"id"|>to_string))else None)in
 Binding_function_stitching_handoff.validate items;
 Printf.printf"FunctionStitching43: mechanical3 ownership33 metadata7; packages3/1/10/13/9/7; no promotion\n"
