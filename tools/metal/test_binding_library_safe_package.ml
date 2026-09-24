let ok=function Ok x->x|Error e->failwith e
let error=function Error _->()|Ok _->failwith"expected MTLLibrary rejection"
let ()=
 let open Binding_library_safe_package in validate_handoff();
 let macros=[|"MODE","1"|]in let options=ok(create_options~macros~required:(Some{x=8;y=4;z=2}))in macros.(0)<-"BAD","0";if options.macros.(0)<>("MODE","1")then failwith"macros not snapshotted";
 error(create_options~macros:[|"","1"|]~required:None);error(validate_threadgroup{x=1024;y=2;z=1});
 let owner={token=1;device=7;destroyed=false}in ignore(ok(validate_owned~device:7 owner));error(validate_owned~device:8 owner);error(validate_owned~device:7{owner with destroyed=true});
 let bindings=[|"a"|]in let reflection=snapshot_reflection{bindings;annotation=Some"u"}in bindings.(0)<-"b";if reflection.bindings.(0)<>"a"then failwith"reflection not snapshotted";
 let pending=begin_async[|owner|]in if retained_count pending<>1 then failwith"async input not retained";
 let cancelled=cancel pending in if retained_count cancelled<>1 then failwith"cancel released before callback";
 let completed=ok(complete cancelled(Failed"late"))in if retained_count completed<>0 then failwith"completion did not release";
 error(complete completed(Function owner));
 let successful=ok(complete(begin_async[|owner|])(Function owner))in(match successful with Completed(Function _)->()|_->failwith"async result");
 Printf.printf"MTLLibrary safe package: callable34 Attribute12/Options6/Function6/Reflection4/Library6; snapshots/device/errors/cancel/exactly-once passed\n%!"
