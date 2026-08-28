let get = function
  | Ok value -> value
  | Error error ->
      failwith (Format.asprintf "%a" Prismel_next_execution.pp_error error)

let () =
  let open Scene_execution.Scene2_command in
  let geometry =
    { vertices = [| 2.; 2.; 30.; 2.; 2.; 30. |];
      indices = [| 0; 1; 2 |]; color = 0x4080bfffl }
  in
  let commands =
    [| Clear 0x000000ffl;
       Push_transform { xx=1.; xy=0.; yx=0.; yy=1.; tx=3.; ty=4. };
       Push_clip { x=0.; y=0.; width=32.; height=32. };
       Geometry geometry; Pop_clip; Pop_transform |]
  in
  let first = get (Prismel_next_execution.scene2_commands commands) in
  let second = get (Prismel_next_execution.scene2_commands commands) in
  if List.length first <> 1 || List.length second <> 1 then
    failwith "renderer-neutral Scene2 command lowering cardinality";
  let malformed =
    [| Push_clip { x=nan; y=0.; width=1.; height=1. }; Geometry geometry |]
  in
  if Result.is_ok (Prismel_next_execution.scene2_commands malformed) then
    failwith "renderer-neutral Scene2 command accepted a non-finite clip";
  print_endline "scene2 command: native value lowering and rejection"
