let declaration json : Binding_device_header_plan.declaration =
 let open Yojson.Safe.Util in {id=json|>member"id"|>to_string;kind=json|>member"kind"|>to_string;
 owner=json|>member"owner"|>to_string_option;name=json|>member"name"|>to_string;
 signature=json|>member"signature"|>to_string}
let ()=
 let inventory=ref""and output=ref""in Arg.parse
  ["--inventory",Arg.Set_string inventory,"inventory";"--output",Arg.Set_string output,"output"]ignore"device header shard";
 let symbols=Yojson.Safe.Util.(Yojson.Safe.from_file !inventory|>member"symbols"|>to_list)in
 let declarations=symbols|>List.filter(fun j->Yojson.Safe.Util.(j|>member"classification"|>to_string="unreviewed"&&j|>member"header"|>to_string=Binding_device_header_plan.header))|>List.map declaration in
 let entries=Binding_device_header_plan.select declarations in Binding_device_header_plan.validate entries;
 let channel=open_out_bin !output in Fun.protect~finally:(fun()->close_out channel)(fun()->output_string channel(Binding_device_header_codegen.render entries));
 Printf.printf"MTLDevice.h: %d exact IDs (%d mechanical, %d ownership, %d metadata)\n"
  (List.length entries)(Binding_device_header_plan.count Mechanical entries)
  (Binding_device_header_plan.count Handwritten_ownership entries)(Binding_device_header_plan.count Metadata entries)
