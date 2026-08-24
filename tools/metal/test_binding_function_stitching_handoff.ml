let ()=
 if Array.length Sys.argv<>2 then invalid_arg"expected inventory";
 let open Yojson.Safe.Util in
 let items=Yojson.Safe.from_file Sys.argv.(1)|>member"symbols"|>to_list|>List.filter_map(fun j->
  let id=j|>member"id"|>to_string and kind=j|>member"kind"|>to_string in
  let expected=List.mem id Binding_function_stitching_handoff.callable_ids||kind="class"||kind="protocol" in
  let classification=j|>member"classification"|>to_string in
  if expected&&j|>member"header"|>to_string="Metal/MTLFunctionStitching.h"&&(classification="unreviewed"||classification="bound")
  then Some(Binding_function_stitching_handoff.classify~kind id)else None)in
 Binding_function_stitching_handoff.validate items;
 Printf.printf"FunctionStitching43: mechanical3 ownership33 metadata7; packages3/1/10/13/9/7; no promotion\n"
