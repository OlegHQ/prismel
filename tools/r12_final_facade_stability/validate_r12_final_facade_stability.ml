let allow_smoke=ref false and compare=ref None and complete_set=ref false and paths=ref[]
let field name fields=match List.assoc_opt name fields with Some x->x|None->failwith("missing "^name)
let int name fields=match field name fields with `Int x->x|_->failwith(name^" is not int")
let float name fields=match field name fields with `Float x->x|`Int x->float x|_->failwith(name^" is not number")
let string name fields=match field name fields with `String x->x|_->failwith(name^" is not string")
type validated={target:string;hash:string}
let validate path=match Yojson.Safe.from_file path with
|`Assoc fields->
  if int"schema"fields<>1||string"qualification"fields<>"R12-final-facade"then failwith"schema drift";
  let target=string"target"fields in if not(List.mem target["native";"headless";"web"])then failwith"invalid target";
  if string"scenario"fields<>"all"then failwith"qualification scenario must be all";
  if int"frames"fields<600 then failwith"checkpoint cardinality";
  let duration=float"duration_seconds"fields in if not!allow_smoke&&duration<1790. then failwith"lane shorter than 30 minutes";
  (match field"checkpoints"fields with `List xs->let labels=List.map(function `List[`Int frame;`String hash]when hash<>""->frame|_->failwith"malformed checkpoint")xs in if labels<>[1;2;60;600]then failwith"checkpoint labels/order drift"|_->failwith"checkpoints not list");
  let capacity=int"sample_capacity"fields in if capacity<>256 then failwith"sample capacity drift";
  let period=float"sample_every_seconds"fields in if period<=0. then failwith"invalid sample period";
  let observations=int"sample_observations"fields in
  let samples=match field"samples"fields with `List xs->xs|_->failwith"samples not list"in
  if List.length samples<>min observations capacity then failwith"sample retained/observation count mismatch";
  let expected=int_of_float(duration/.period)+1 in if not!allow_smoke&&(observations<max 1(expected*4/5)||observations>expected*6/5+2)then failwith"sample observations inconsistent with duration";
  let parsed=List.map(function `Assoc fs->int"frame"fs,float"elapsed_seconds"fs,float"rss_kib"fs|_->failwith"sample is not object")samples in
  let rec ordered=function []|[_]->true|(f0,t0,_)::((f1,t1,_)::_ as rest)->f1>f0&&t1>t0&&ordered rest in
  if not(ordered parsed)then failwith"samples not strictly ordered";
  let rss=List.map(fun(_,_,rss)->rss)parsed in let tail=let n=List.length rss in List.filteri(fun i _->i>=n*3/4)rss in
  (match tail with []->if not!allow_smoke then failwith"no RSS samples"|x::xs->let lo,hi=List.fold_left(fun(a,b)v->min a v,max b v)(x,x)xs in if not!allow_smoke&&lo>0.&&100.*.(hi-.lo)/.lo>5. then failwith"final RSS window exceeds 5 percent");
  let created=int"created_resources"fields and destroyed=int"destroyed_resources"fields in if created<>destroyed then failwith"created/destroyed resource mismatch";
  if int"live_resources_after_teardown"fields<>0||int"cache_entries_after_teardown"fields<>0||int"release_queue_pending_after_teardown"fields<>0 then failwith"teardown counters nonzero";
  (match field"window_live_after_teardown"fields with `Bool false->()|_->failwith"window survived teardown");
  {target;hash=string"deterministic_hash"fields}
|_->failwith"report root is not object"
let ()=Arg.parse["--allow-smoke",Arg.Set allow_smoke,"accept short lane";"--compare",Arg.String(fun p->compare:=Some p),"compare deterministic report";"--complete-set",Arg.Set complete_set,"require native/headless/web reports"](fun p->paths:=p::!paths)"validate R12 report(s)";
  let reports=List.map validate(List.rev!paths)in
  (if!complete_set then begin if Option.is_some!compare then invalid_arg"--compare is incompatible with --complete-set";let targets=List.sort String.compare(List.map(fun report->report.target)reports)in if targets<>["headless";"native";"web"]then failwith"complete set requires exactly native, headless, and web"end else match reports with [report]->Option.iter(fun other->if report.hash<>(validate other).hash then failwith"deterministic hash mismatch")!compare|_->invalid_arg"one report required unless --complete-set is used");
  print_endline"R12 final-facade report: valid"
