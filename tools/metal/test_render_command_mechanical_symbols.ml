let read p=let c=open_in_bin p in let n=in_channel_length c in let s=really_input_string c n in close_in c;s
let count text needle=let n=String.length needle in let rec f i c=if i+n>String.length text then c else if String.sub text i n=needle then f(i+n)(c+1)else f(i+1)c in f 0 0
let ()=let s=read "tools/metal/metal_render_command_mechanical_generated.inc" in
 let names=["draw";"draw_instances";"depth_clip";"depth_bounds";"fragment_buffer_offset";"mesh_buffer_offset";"object_buffer_offset";"object_threadgroup_memory";"stencil_reference";"tessellation_scale";"threadgroup_memory";"tile_buffer_offset";"vertex_buffer_offset";"vertex_buffer_offset_stride"]in
 List.iter(fun n->if count s("caml_prismel_metal_render_command_"^n)=0 then failwith("missing "^n))names;
 print_endline "render command mechanical14 typed wrapper source green"
