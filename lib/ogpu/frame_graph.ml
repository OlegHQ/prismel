type tracking=Safe|Untracked
type resource={id:int64;handle:unit Handle.t;initialized:bool}
type access={resource_id:int64;access:Command.access;stages:Command.stage list}
type pass={id:int;kind:Command.pass;accesses:access array;depends_on:int array;barriers:int64 array;native:Native_pass.plan option}
type scheduled={id:int;commands:Command.description array;native_resource_count:int}
let invalid text=Error(Error.make"Ogpu.Frame_graph.compile"Error.Invalid_argument text)
let writes=function Command.Write|Read_write->true|Read->false
let reads=function Command.Read|Read_write->true|Write->false
let compile device ~tracking ~resources ~passes=
  let resource_table=Hashtbl.create(Array.length resources)in
  let rec validate_resources i=if i=Array.length resources then Ok()else let(r:resource)=resources.(i)in if r.id<=0L||Hashtbl.mem resource_table r.id then invalid"resource declarations contain an invalid/duplicate id"else match Handle.validate_for ~operation:"Ogpu.Frame_graph.compile"device r.handle with Error _ as e->e|Ok()->Hashtbl.add resource_table r.id r;validate_resources(i+1)in
  Result.bind(validate_resources 0)(fun()->
    let pass_index=Hashtbl.create(Array.length passes)in Array.iteri(fun index (pass:pass)->if Hashtbl.mem pass_index pass.id then()else Hashtbl.add pass_index pass.id index)passes;
    if Hashtbl.length pass_index<>Array.length passes then invalid"pass ids are duplicated"else
    let edges=Array.make(Array.length passes)[]and indegree=Array.make(Array.length passes)0 in
    let add_edge from_ into=if from_<>into&&not(List.mem into edges.(from_))then(edges.(from_)<-into::edges.(from_);indegree.(into)<-indegree.(into)+1)in
    let last_access=Hashtbl.create(Array.length resources)and initialized=Hashtbl.create(Array.length resources)in Array.iter(fun(r:resource)->Hashtbl.add initialized r.id r.initialized)resources;
    let failure=ref None in
    Array.iteri(fun index (pass:pass)->
      Array.iter(fun dependency->match Hashtbl.find_opt pass_index dependency with None->if !failure=None then failure:=Some"pass dependency is missing"|Some source->add_edge source index)pass.depends_on;
      let local=Hashtbl.create(Array.length pass.accesses)in
      Array.iter(fun(access:access)->if !failure=None then match Hashtbl.find_opt resource_table access.resource_id with None->failure:=Some"pass accesses an undeclared resource"|Some _ when Hashtbl.mem local access.resource_id->failure:=Some"pass declares conflicting duplicate resource access"|Some _ when access.stages=[]||List.sort_uniq compare access.stages<>access.stages->failure:=Some"access stages must be sorted and unique"|Some _->Hashtbl.add local access.resource_id();let prior=Hashtbl.find_opt last_access access.resource_id in if reads access.access&&not(Hashtbl.find initialized access.resource_id)then failure:=Some"resource is read before initialization"else(match prior with None->()|Some(source,prior_access)when writes prior_access||writes access.access->(match tracking with Safe->add_edge source index|Untracked->if not(Array.mem access.resource_id pass.barriers)then failure:=Some"untracked hazard is missing a resource barrier")|Some _->());if writes access.access then Hashtbl.replace initialized access.resource_id true;Hashtbl.replace last_access access.resource_id(index,access.access))pass.accesses;
      match pass.native with None->()|Some plan->Array.iter(fun(declaration:Native_pass.declaration)->if not(Hashtbl.mem local declaration.resource_id) && !failure=None then failure:=Some"native pass uses a resource absent from pass declarations")(Native_pass.declarations plan))passes;
    match !failure with
    | Some text -> invalid text
    | None ->
        let ready = ref (List.init (Array.length passes) Fun.id |> List.filter (fun i -> indegree.(i)=0)) in
        let order = ref [] in
        while !ready <> [] do
          let next = List.hd !ready in
          ready := List.tl !ready;
          order := next :: !order;
          List.iter (fun target ->
            indegree.(target) <- indegree.(target) - 1;
            if indegree.(target)=0 then ready := List.sort compare (target :: !ready)) edges.(next)
        done;
        if List.length !order <> Array.length passes then invalid "pass dependency graph contains a cycle"
        else
          let schedule_pass index =
            let pass = passes.(index) in
            let command = Command.begin_encoder () in
            Result.bind (Command.begin_pass command pass.kind) (fun () ->
              let declared = Array.fold_left (fun result access ->
                Result.bind result (fun () -> Command.declare_resource command
                  ~resource_id:access.resource_id ~access:access.access ~stages:access.stages)) (Ok ()) pass.accesses in
              Result.bind declared (fun () ->
                Result.bind (Command.end_pass command) (fun () ->
                  Result.map (fun () ->
                    { id=pass.id; commands=Command.descriptions command
                    ; native_resource_count=(match pass.native with None->0|Some plan->Array.length(Native_pass.declarations plan)) })
                    (Command.end_encoder command))))
          in
          let scheduled = List.fold_left (fun result index ->
            Result.bind result (fun values -> Result.map (fun value -> value :: values) (schedule_pass index))) (Ok []) (List.rev !order) in
          Result.map (fun values -> Array.of_list (List.rev values)) scheduled)
