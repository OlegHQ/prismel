open Binding_device_header_plan
let snake value=value|>String.to_seq|>Seq.map(function
 |('a'..'z'|'0'..'9')as c->c|'A'..'Z'as c->Char.lowercase_ascii c|_->'_')|>String.of_seq
let selector id=let l=String.index id ' 'and r=String.rindex id ']'in String.sub id(l+1)(r-l-1)
let signature value=
 let a=String.index value '('and b=String.rindex value ')'in
 let body=String.sub value(a+1)(b-a-1)|>String.trim in
 let args=if body=""then[]else String.split_on_char ','body|>List.map String.trim in
 let dash=String.index value '-'in args,String.sub value(dash+2)(String.length value-dash-2)|>String.trim
let owner_type=function"MTLDevice"->"id<MTLDevice>"|"MTLArgumentDescriptor"->"MTLArgumentDescriptor *"|x->invalid_arg x
let call selector args=
 if args=[]then"[receiver "^selector^"]"else
 let pieces=String.split_on_char ':'selector|>List.filter((<>)"")in
 if List.length pieces<>List.length args then invalid_arg selector;
 "[receiver "^(List.map2(fun p(_,n)->p^":"^n)pieces args|>String.concat" ")^"]"
let render entries =
 validate entries;
 let b=Buffer.create 32768 in
 Buffer.add_string b "#import <Foundation/Foundation.h>\n#import <Metal/Metal.h>\n\n/* Exact mechanical MTLDevice.h shard; direct typed calls only. */\n";
 entries|>List.iter(fun e->match e.lane,e.declaration.kind,e.declaration.owner with
 |Mechanical,"method",Some owner->
   let args,result=signature e.declaration.signature in
   let named=List.mapi(fun i ty->ty,"arg"^string_of_int i)args in
   let name="prismel_device_header_"^snake(owner^"_"^e.declaration.name)in
   Printf.bprintf b "static %s %s(%s receiver%s) { %s%s; } /* %s */\n"
    result name(owner_type owner)
    (if named=[]then""else", "^(named|>List.map(fun(t,n)->t^" "^n)|>String.concat", "))
    (if result="void"then""else"return ")(call(selector e.declaration.id)named)e.declaration.id
 |_ ->());Buffer.contents b
