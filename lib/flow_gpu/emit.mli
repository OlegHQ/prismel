type msl = private {source : string; entry : string; interface : Ogpu.Shader.binding list;
  uniform_layout : (string * int * int) list; uniform_bytes : int;
  table_seeds : int array; output_width : int; input_widths : int array}
val names : string list
val kernel : Flow_ir.Packed.t -> (msl, Flow.Diagnostic.t) result
