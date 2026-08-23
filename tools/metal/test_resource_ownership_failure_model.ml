type token = { mutable native : bool; mutable parent : bool; mutable completion : bool }
let create ()={native=false;parent=false;completion=false}
let construct token ~native_succeeds ~safe_attach_succeeds =
 token.native<-native_succeeds;
 if not native_succeeds then Error `Native
 else if not safe_attach_succeeds then (token.native<-false;Error `Attach)
 else (token.parent<-true;Ok())
let retain_completion token ~native_succeeds =
 token.completion<-true;
 if native_succeeds then Ok() else(token.completion<-false;Error `Native)
let destroy token = token.completion<-false;token.parent<-false;token.native<-false
let () =
 for i=0 to 10_000 do
  let token=create()in
  ignore(construct token ~native_succeeds:(i mod 3<>0) ~safe_attach_succeeds:(i mod 5<>0));
  if token.native<>token.parent then failwith "constructor unwind retained native without parent";
  ignore(retain_completion token ~native_succeeds:(i mod 7<>0));
  destroy token;
  if token.native||token.parent||token.completion then failwith "failure unwind leak"
 done;
 print_endline "resource ownership failure unwind: 10001 constructor/completion cases green"
