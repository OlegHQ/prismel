let declaration j:Binding_pipeline_header_plan.declaration=let open Yojson.Safe.Util in{id=j|>member"id"|>to_string;header=j|>member"header"|>to_string;kind=j|>member"kind"|>to_string;owner=j|>member"owner"|>to_string_option;name=j|>member"name"|>to_string;signature=j|>member"signature"|>to_string}
let ()=let inventory=ref""and output=ref""in Arg.parse["--inventory",Arg.Set_string inventory,"";"--output",Arg.Set_string output,""]ignore"pipeline113";
 let js=Yojson.Safe.Util.(Yojson.Safe.from_file !inventory|>member"symbols"|>to_list)in
 let ds=js|>List.filter(fun j->Yojson.Safe.Util.(j|>member"classification"|>to_string="unreviewed"))|>List.map declaration in
 let es=Binding_pipeline_header_plan.select ds in Binding_pipeline_header_plan.validate es;let c=open_out_bin !output in Fun.protect~finally:(fun()->close_out c)(fun()->output_string c(Binding_pipeline_header_codegen.render es));
 Printf.printf"pipeline113: %d mechanical %d ownership %d metadata\n"(Binding_pipeline_header_plan.count Mechanical es)(Binding_pipeline_header_plan.count Handwritten_ownership es)(Binding_pipeline_header_plan.count Metadata es)
