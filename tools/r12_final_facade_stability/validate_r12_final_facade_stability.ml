let allow_smoke=ref false and compare=ref None and paths=ref[]
let field name fields=match List.assoc_opt name fields with Some x->x|None->failwith("missing "^name)
let int name fields=match field name fields with `Int x->x|_->failwith(name^" is not int")
let float name fields=match field name fields with `Float x->x|`Int x->float x|_->failwith(name^" is not number")
let string name fields=match field name fields with `String x->x|_->failwith(name^" is not string")
let validate path = match Yojson.Safe.from_file path with
  |`Assoc fields->
    if int"schema"fields<>1||string"qualification"fields<>"R12-final-facade"then failwith"schema drift";
    if int"frames"fields<600 then failwith"checkpoint cardinality";
    if not !allow_smoke&&float"duration_seconds"fields<1790. then failwith"lane shorter than 30 minutes";
    (match field"checkpoints"fields with `List xs when List.length xs=4->()|_->failwith"missing 1/2/60/600 checkpoints");
    let capacity=int"sample_capacity"fields in if capacity<>256 then failwith"sample capacity drift";
    let samples=match field"samples"fields with `List xs->xs|_->failwith"samples not list"in
    if List.length samples>capacity then failwith"sample ring overflow";
    let rss=List.filter_map(function `Assoc fs->Some(float"rss_kib"fs)|_->None)samples in
    let tail=let n=List.length rss in List.filteri(fun i _->i>=n*3/4)rss in
    (match tail with []->if not !allow_smoke then failwith"no RSS samples"
      |x::xs->let lo,hi=List.fold_left(fun(a,b)v->min a v,max b v)(x,x)xs in
        if not !allow_smoke&&lo>0.&&100.*.(hi-.lo)/.lo>5. then failwith"final RSS window exceeds 5 percent");
    if int"live_resources_after_teardown"fields<>0||int"cache_entries_after_teardown"fields<>0
      ||int"release_queue_pending_after_teardown"fields<>0 then failwith"teardown counters nonzero";
    (match field"window_live_after_teardown"fields with `Bool false->()|_->failwith"window survived teardown");
    string"deterministic_hash"fields
  |_ -> failwith"report root is not object"
let ()=Arg.parse["--allow-smoke",Arg.Set allow_smoke,"accept short lane";"--compare",Arg.String(fun p->compare:=Some p),"compare deterministic report"](fun p->paths:=p::!paths)"validate R12 report";
  match List.rev!paths with [path]->let hash=validate path in Option.iter(fun other->if hash<>validate other then failwith"deterministic hash mismatch")!compare;print_endline"R12 final-facade report: valid"|_->invalid_arg"one report required"
