module P = Flow_ir.Packed
module S = Ogpu.Shader
type msl = {source : string; entry : string; interface : S.binding list;
  uniform_layout : (string * int * int) list; uniform_bytes : int;
  table_seeds : int array; output_width : int; input_widths : int array}
let names = Flow.Packed_ops.names
let perlin = {|float fade(float t) { return t*t*t*(t*(t*6.0f-15.0f)+10.0f); }
float blend(float a, float b, float t) { return a+t*(b-a); }
float gradient(int h, float x, float y, float z) {
  h &= 15;
  float u=h<8?x:y, v=h<4?y:((h==12||h==14)?x:z);
  return ((h&1)==0?u:-u)+((h&2)==0?v:-v);
}
float noise(float3 p, device const int* table) {
  if(!all(isfinite(p))) return as_type<float>(0x7fc00000u);
  float3 base=floor(p), q=p-base, f=float3(fade(q.x),fade(q.y),fade(q.z));
  int x=int(fmod(base.x,256.0f))&255, y=int(fmod(base.y,256.0f))&255, z=int(fmod(base.z,256.0f))&255;
  int a=table[x]+y, b=table[x+1]+y;
  int aa=table[a]+z, ab=table[a+1]+z, ba=table[b]+z, bb=table[b+1]+z;
  float x00=blend(gradient(table[aa],q.x,q.y,q.z),gradient(table[ba],q.x-1,q.y,q.z),f.x);
  float x10=blend(gradient(table[ab],q.x,q.y-1,q.z),gradient(table[bb],q.x-1,q.y-1,q.z),f.x);
  float x01=blend(gradient(table[aa+1],q.x,q.y,q.z-1),gradient(table[ba+1],q.x-1,q.y,q.z-1),f.x);
  float x11=blend(gradient(table[ab+1],q.x,q.y-1,q.z-1),gradient(table[bb+1],q.x-1,q.y-1,q.z-1),f.x);
  return clamp((blend(blend(x00,x10,f.y),blend(x01,x11,f.y),f.z)+1.0f)*0.5f,0.0f,1.0f);
}
float fbm(float3 p, int octaves, device const int* table) {
  float frequency=1.0f, amplitude=1.0f, sum=0.0f, weights=0.0f;
  for(int octave=0;octave<octaves;octave++) {
    sum+=noise(p*frequency,table)*amplitude; weights+=amplitude;
    frequency*=2.0f; amplitude*=0.5f;
  }
  return weights==0.0f?0.0f:sum/weights;
}
|}
exception Unsupported of string
let fail message = raise (Unsupported message)
let register index = "r" ^ string_of_int index
let binary operation a b =
  let infix operator = "(" ^ a ^ operator ^ b ^ ")" in
  match operation with
  | P.Add -> infix "+" | Sub -> infix "-" | Mul -> infix "*"
  | Div -> "(" ^ b ^ "==0.0f?0.0f:" ^ a ^ "/" ^ b ^ ")"
  | Mod -> "(" ^ b ^ "==0.0f?0.0f:fmod(fmod(" ^ a ^ "," ^ b ^ ")+" ^ b ^ "," ^ b ^ "))"
  | Pow -> "pow(fabs(" ^ a ^ ")," ^ b ^ ")"
  | Min -> "min(" ^ a ^ "," ^ b ^ ")" | Max -> "max(" ^ a ^ "," ^ b ^ ")"
  | Lt -> infix "<" | Le -> infix "<=" | Gt -> infix ">" | Ge -> infix ">=" | Eq -> infix "=="
  | And -> "(" ^ a ^ "!=0.0f&&" ^ b ^ "!=0.0f)"
  | Or -> "(" ^ a ^ "!=0.0f||" ^ b ^ "!=0.0f)"
let unary operation a = match operation with
  | P.Sin -> "sin(" ^ a ^ ")" | Cos -> "cos(" ^ a ^ ")"
  | Sqrt -> "sqrt(fabs(" ^ a ^ "))" | Abs -> "fabs(" ^ a ^ ")" | Not -> "(" ^ a ^ "==0.0f)"
let kernel program = try
  let view = P.Private.view program in
  if not view.collecting || not view.zipped || view.skip<>[||] then
    fail "GPU kernels require Collect with Zip iteration and no skipped elements.";
  if Array.exists (function P.Accumulator _ -> true | _ -> false) view.code then
    fail "Ordered accumulators stay on the CPU.";
  let offset = ref 4 and uniform_layout = ref [] in
  let uniform name width =
    let first = !offset in offset := first+width*4;
    uniform_layout := (name,first,width) :: !uniform_layout; first/4 in
  let uniforms = Array.mapi (fun index width -> uniform ("uniform:" ^ string_of_int index) width) view.uniform_widths in
  let frames = Array.mapi (fun index -> function
    | P.Frame name -> uniform (Printf.sprintf "frame:%d:%s" index name) 1 | _ -> 0) view.code in
  let used=Array.make (Array.length view.code) false in
  let rec use slot = if not used.(slot) then begin
    used.(slot)<-true;
    match view.code.(slot) with
    | P.Binary (_,a,b) -> use a;use b | Unary (_,a) -> use a
    | Select (a,b,c) | Noise3 (a,b,c,_,_) -> use a;use b;use c
    | _ -> ()
  end in
  Array.iter use view.output;
  let table_seeds = Array.to_list(Array.mapi(fun index instruction->index,instruction)view.code)
    |> List.filter_map (function
      | index,P.Noise3 (_,_,_,seed,octaves) when used.(index) ->
          if octaves<1 || octaves>32 then fail "GPU noise supports 1 to 32 octaves.";
          Some seed | _ -> None) |> List.sort_uniq Int.compare |> Array.of_list in
  let table seed = match Array.find_index ((=) seed) table_seeds with Some index -> index*512 | None -> assert false in
  let body = Buffer.create 4096 in
  Array.iteri (fun slot instruction ->
    if used.(slot) then begin
    let expression = match instruction with
      | P.Const value ->
          if not (Float.is_finite (Int32.float_of_bits(Int32.bits_of_float value))) then
            fail "Nonfinite float32 shader constants require reference evaluation.";
          Printf.sprintf "as_type<float>(0x%lxu)" (Int32.bits_of_float value)
      | Input (input,width,component) -> Printf.sprintf "input%d[i*%d+%d]" input width component
      | Uniform (index,component) -> Printf.sprintf "as_type<float>(uniforms[%d])" (uniforms.(index)+component)
      | Frame _ -> Printf.sprintf "as_type<float>(uniforms[%d])" frames.(slot)
      | Accumulator _ -> assert false
      | Binary (op,a,b) -> binary op (register a) (register b)
      | Unary (op,a) -> unary op (register a)
      | Select (condition,yes,no) -> Printf.sprintf "(%s!=0.0f?%s:%s)" (register condition) (register yes) (register no)
      | Noise3 (x,y,z,seed,octaves) -> Printf.sprintf "fbm(float3(%s,%s,%s),%d,table+%d)"
          (register x) (register y) (register z) octaves (table seed) in
    Printf.bprintf body "  float r%d=%s;\n" slot expression
    end) view.code;
  Array.iteri (fun component slot ->
    Printf.bprintf body "  if(!isfinite(r%d)) atomic_store_explicit(status,1u,memory_order_relaxed);\n" slot;
    Printf.bprintf body "  output[i*%d+%d]=r%d;\n"
      (Array.length view.output) component slot) view.output;
  let count = Array.length view.widths in
  let arguments = Array.to_list (Array.mapi (fun index _ -> Printf.sprintf
    "device const float* input%d [[buffer(%d)]]" index index) view.widths)
    @ [Printf.sprintf "device float* output [[buffer(%d)]]" count;
       Printf.sprintf "constant uint* uniforms [[buffer(%d)]]" (count+1);
       Printf.sprintf "device atomic_uint* status [[buffer(%d)]]" (count+2)]
    @ (if table_seeds=[||] then [] else [Printf.sprintf "device const int* table [[buffer(%d)]]" (count+3)])
    @ ["uint i [[thread_position_in_grid]]"] in
  let prefix = "#include <metal_stdlib>\nusing namespace metal;\n" ^
    (if table_seeds=[||] then "" else perlin) in
  let signature = String.concat ",\n  " arguments in
  let body = "  if(i>=uniforms[0]) return;\n  if(i==0) atomic_fetch_or_explicit(status,0u,memory_order_relaxed);\n" ^ Buffer.contents body in
  let digest = Digest.to_hex (Digest.string (prefix ^ signature ^ body)) in
  let entry = "kernel_" ^ digest in
  let source = prefix ^ "kernel void " ^ entry ^ "(\n  " ^ signature ^ ") {\n" ^ body ^ "}\n" in
  let input_used=Array.make count false in
  Array.iteri(fun slot->function P.Input(input,_,_)when used.(slot)->input_used.(input)<-true|_->())view.code;
  let interface = List.init (count+3+(if table_seeds=[||] then 0 else 1)) Fun.id
    |>List.filter(fun binding->binding>=count || input_used.(binding))
    |>List.map(fun binding->S.{group=0;binding;kind=(if binding=count+1 then Uniform_buffer else Storage_buffer);visibility=[Compute]})in
  Ok {source;entry;interface;uniform_layout=List.rev !uniform_layout;uniform_bytes= !offset;
    table_seeds;output_width=Array.length view.output;input_widths=view.widths}
with Unsupported message -> Error (Flow.Diagnostic.error ~code:"E_GPU_FORM" message)
