let declaration j:Binding_layout_header_plan.declaration=let open Yojson.Safe.Util in{id=j|>member"id"|>to_string;kind=j|>member"kind"|>to_string;owner=j|>member"owner"|>to_string_option;name=j|>member"name"|>to_string;signature=j|>member"signature"|>to_string}
let ()=let inventory=ref""and output=ref""in Arg.parse["--inventory",Arg.Set_string inventory,"";"--output",Arg.Set_string output,""]ignore"layout102";
 let js=Yojson.Safe.Util.(Yojson.Safe.from_file !inventory|>member"symbols"|>to_list)in
 let ds=js|>List.filter(fun j->Yojson.Safe.Util.(j|>member"classification"|>to_string="unreviewed"&&List.mem(j|>member"header"|>to_string)Binding_layout_header_plan.headers))|>List.map declaration in
 let es=Binding_layout_header_plan.select ds in Binding_layout_header_plan.validate es;let c=open_out_bin !output in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c(Binding_layout_header_codegen.render es));
 Printf.printf"layout102: %d mechanical %d ownership %d metadata\n"(Binding_layout_header_plan.count Mechanical es)(Binding_layout_header_plan.count Handwritten_ownership es)(Binding_layout_header_plan.count Metadata es)
