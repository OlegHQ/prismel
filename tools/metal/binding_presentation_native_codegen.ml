type declaration = Binding_presentation_spec.declaration

let generated_ids =
  Binding_presentation_coverage.items
  |> List.filter_map (fun (item : Binding_presentation_coverage.item) ->
       match item.implementation with
       | Generated_typed_selector -> Some item.id
       | Handwritten_lifecycle -> None)

let contains value needle =
  let rec loop i = i + String.length needle <= String.length value &&
    (String.sub value i (String.length needle)=needle || loop (i+1)) in
  loop 0

let method_selector id =
  let left=String.index id ' ' and right=String.rindex id ']' in
  String.sub id (left+1) (right-left-1)

let snake value =
  value |> String.to_seq |> Seq.map (function
    | ('a'..'z' | '0'..'9') as c -> c
    | 'A'..'Z' as c -> Char.lowercase_ascii c | _ -> '_')
  |> String.of_seq

let split_signature signature =
  let arrow = match String.index_opt signature '-' with Some i -> i | None -> invalid_arg signature in
  let result=String.sub signature (arrow+2) (String.length signature-arrow-2)|>String.trim in
  let l=String.index signature '(' and r=String.rindex signature ')' in
  let body=String.sub signature (l+1) (r-l-1)|>String.trim in
  let args=if body="" then [] else String.split_on_char ',' body |> List.map String.trim in
  args,result

let owner_type = function
  | "CAMetalLayer" -> "CAMetalLayer *"
  | "CAMetalDrawable" -> "id<CAMetalDrawable>"
  | "MTLCommandBuffer" -> "id<MTLCommandBuffer>"
  | "MTLRenderPassDescriptor" -> "MTLRenderPassDescriptor *"
  | owner -> invalid_arg ("unsupported presentation owner "^owner)

let objc_pointer ty =
  String.starts_with ~prefix:"id<" ty || contains ty "Descriptor"
  || contains ty "CAMetalLayer *" || contains ty "CAEDRMetadata *"
  || contains ty "NSString *" || contains ty "NSDictionary *"
  || contains ty "NSError *"

let clean_type ty =
  [" _Nonnull";" _Nullable";" _Null_unspecified";" __strong";
   " __unsafe_unretained";" const";"const "]
  |> List.fold_left (fun value suffix ->
       let rec replace value =
         match String.index_opt value suffix.[0] with
         | None -> value
         | Some _ ->
             let rec find i =
               if i+String.length suffix>String.length value then value else
               if String.sub value i (String.length suffix)=suffix then
                 replace (String.sub value 0 i ^ String.sub value (i+String.length suffix)
                   (String.length value-i-String.length suffix)) else find(i+1)
             in find 0
       in replace value) ty |> String.trim

let call selector args =
  if args=[] then "[receiver "^selector^"]" else
  let pieces=String.split_on_char ':' selector |> List.filter ((<>) "") in
  if List.length pieces<>List.length args then invalid_arg ("selector arity "^selector);
  "[receiver " ^ (List.map2 (fun piece (_,name)->piece^":"^name) pieces args |> String.concat " ") ^ "]"

let render_native declarations =
  let methods=declarations |> List.filter (fun (d:declaration)->d.kind="method" && List.mem d.id generated_ids) in
  let b=Buffer.create 65536 in
  Buffer.add_string b "#import <QuartzCore/CAMetalLayer.h>\n#import <Metal/Metal.h>\n#include <cstdint>\nextern \"C\" {\n#include <caml/alloc.h>\n#include <caml/memory.h>\n#include <caml/mlvalues.h>\n}\n\n/* Generated callable, statically typed presentation adapters and CAML entry points. */\n";
  List.iter (fun (d:declaration) -> match d.owner with None->() | Some owner ->
    let args,result=split_signature d.signature in
    let named=List.mapi(fun i ty->ty,"arg"^string_of_int i)args in
    let selector=method_selector d.id and name="prismel_presentation_"^snake(owner^"_"^d.name) in
    let class_method=String.starts_with ~prefix:"class " d.signature in
    let parameters =
      (if class_method then [] else [owner_type owner,"receiver"]) @ named
      |> List.map(fun(t,n)->t^" "^n)|>String.concat ", " in
    let expression = if class_method then "["^owner^" "^selector^"]" else call selector named in
    Printf.bprintf b "static %s %s(%s) { %s%s; } /* %s */\n"
      result name parameters (if result="void" then "" else "return ") expression d.id;
    let raw_inputs=(if class_method then [] else [owner_type owner])@args in
    let caml_args=List.mapi(fun i _->"value raw"^string_of_int i)raw_inputs in
    let param_macro=match List.length caml_args with
      |0->"CAMLparam0();"|1->"CAMLparam1(raw0);"|2->"CAMLparam2(raw0,raw1);"
      |3->"CAMLparam3(raw0,raw1,raw2);"|4->"CAMLparam4(raw0,raw1,raw2,raw3);"
      |5->"CAMLparam5(raw0,raw1,raw2,raw3,raw4);"|_->invalid_arg("CAML arity "^d.id) in
    let convert i ty =
      let raw="raw"^string_of_int i and cleaned=clean_type ty in
      if ty="BOOL" then "Bool_val("^raw^")"
      else if ty="CFTimeInterval" then "Double_val("^raw^")"
      else if ty="CGSize" then "CGSizeMake(Double_val(Field("^raw^",0)),Double_val(Field("^raw^",1)))"
      else if contains ty "*" || contains ty "id<" || contains ty "Ref" then
        (if objc_pointer ty then "(__bridge " else "(")^cleaned^")(void *)Nativeint_val("^raw^")"
      else "static_cast<"^cleaned^">(Int64_val("^raw^"))" in
    let converted=List.mapi convert raw_inputs in
    let wrapper="caml_prismel_metal_presentation_"^snake(owner^"_"^d.name) in
    Printf.bprintf b "extern \"C\" CAMLprim value %s(%s) { %s " wrapper
      (if caml_args=[] then "value raw_unit" else String.concat ", " caml_args) param_macro;
    let invoke=name^"("^String.concat ", " converted^")" in
    if result="void" then Printf.bprintf b "%s; CAMLreturn(Val_unit); }\n" invoke
    else if result="BOOL" then Printf.bprintf b "CAMLreturn(Val_bool(%s)); }\n" invoke
    else if result="CFTimeInterval" then Printf.bprintf b "CAMLreturn(caml_copy_double(%s)); }\n" invoke
    else if result="CGSize" then Printf.bprintf b "CGSize r=%s; CAMLlocal1(v); v=caml_alloc_tuple(2); Store_field(v,0,caml_copy_double(r.width)); Store_field(v,1,caml_copy_double(r.height)); CAMLreturn(v); }\n" invoke
    else if contains result "*" || contains result "id<" || contains result "Ref" then
      Printf.bprintf b "auto r=%s; CAMLreturn(caml_copy_nativeint((intnat)%s r)); }\n" invoke
        (if objc_pointer result then "(__bridge void *)" else "(void *)")
    else Printf.bprintf b "CAMLreturn(caml_copy_int64((int64_t)%s)); }\n" invoke) methods;
  Buffer.contents b

let ocaml_type ty =
  if ty="BOOL" then "bool" else if ty="CFTimeInterval" then "float"
  else if ty="CGSize" then "float * float"
  else if contains ty "*" || contains ty "id<" || contains ty "Ref" then "handle"
  else "int64"

let render_raw_externals declarations =
  let methods=declarations |> List.filter(fun (d:declaration)->d.kind="method" && List.mem d.id generated_ids) in
  "type handle = nativeint\n" ^ (methods |> List.filter_map(fun (d:declaration)->match d.owner with None->None|Some owner->
    let args,result=split_signature d.signature in
    let name="presentation_"^snake(owner^"_"^d.name) in
    let receiver=if String.starts_with ~prefix:"class " d.signature then [] else ["handle"] in
    let inputs=receiver@List.map ocaml_type args in
    let types=(if inputs=[] then ["unit"] else inputs)@
      [if result="void" then "unit" else ocaml_type result] in
    Some(Printf.sprintf "external %s : %s = \"caml_prismel_metal_%s\""
      name (String.concat " -> " types) name)) |> String.concat "\n")

let validate declarations =
  let selected=declarations|>List.filter(fun (d:declaration)->List.mem d.id generated_ids) in
  if List.length selected<>List.length generated_ids then
    invalid_arg(Printf.sprintf "presentation mechanical closure: expected %d found %d"
      (List.length generated_ids)(List.length selected));
  ignore(render_native declarations); ignore(render_raw_externals declarations)
