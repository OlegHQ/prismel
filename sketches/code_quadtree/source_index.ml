(* A read-only stdio LSP client. One server, one open document at a time; all
   indexing completes before the native application loop starts. *)
type symbol = {name:string; kind:int; first_line:int; last_line:int;
  children:symbol list}

let member name = function `Assoc fields -> Option.value (List.assoc_opt name fields) ~default:`Null | _ -> `Null
let integer = function `Int n -> n | _ -> 0
let string = function `String value -> value | _ -> ""
let list = function `List values -> values | _ -> []
let rec symbols json = (match json with `Null->[] |`List values->values
  |_->failwith "Malformed LSP document-symbol response") |> List.map (fun value ->
  let range=match member "range" value with
    |`Null -> member "range" (member "location" value) |range -> range in
  let symbol={name=string (member "name" value);kind=integer (member "kind" value);
   first_line=integer (member "line" (member "start" range));
   last_line=integer (member "line" (member "end" range));
   children=symbols (member "children" value)} in
  if symbol.name="" || symbol.kind<=0 || symbol.first_line<0 ||
     symbol.last_line<symbol.first_line || range=`Null then
    failwith "Malformed LSP symbol name, kind, or source range";
  symbol)
let rec count symbols = List.fold_left (fun n s -> n+1+count s.children) 0 symbols
let rec symbol_json s = `Assoc ["name",`String s.name;"kind",`Int s.kind;
  "range",`Assoc ["start",`Assoc ["line",`Int s.first_line];
                   "end",`Assoc ["line",`Int s.last_line]];
  "children",`List (List.map symbol_json s.children)]

let uri path =
  let out=Buffer.create (String.length path+16) in
  Buffer.add_string out "file://";
  String.iter (function
    |('a'..'z'|'A'..'Z'|'0'..'9'|'/'|'-'|'_'|'.'|'~') as c -> Buffer.add_char out c
    |c -> Buffer.add_string out (Printf.sprintf "%%%02X" (Char.code c))) path;
  Buffer.contents out

type connection = {pid:int; input:Unix.file_descr; output:Unix.file_descr;
  mutable next_id:int; mutable closed:bool}

let send c value =
  let body=Yojson.Basic.to_string value in
  let message=Bytes.of_string (Printf.sprintf "Content-Length: %d\r\n\r\n%s"
    (String.length body) body) in
  let rec write offset =
    if offset<Bytes.length message then
      let n=Unix.write c.output message offset (Bytes.length message-offset) in
      if n=0 then failwith "LSP pipe closed" else write (offset+n) in
  write 0

let receive c deadline =
  let read bytes offset length =
    let rec loop offset left =
      if left>0 then begin
        let remaining=deadline-.Unix.gettimeofday () in
        if remaining<=0. || (let ready,_,_=Unix.select [c.input] [] [] remaining in ready=[]) then
          failwith "OCaml LSP response timed out";
        let n=Unix.read c.input bytes offset left in
        if n=0 then failwith "OCaml LSP exited before replying";
        loop (offset+n) (left-n)
      end in
    loop offset length in
  let header=Buffer.create 128 and byte=Bytes.create 1 in
  let rec headers length =
    Buffer.clear header;
    let rec line () =
      read byte 0 1;
      let c=Bytes.get byte 0 in
      if c<>'\n' then begin
        if Buffer.length header>8192 then failwith "oversized LSP header";
        Buffer.add_char header c;line ()
      end in
    line ();
    let line=String.trim (Buffer.contents header) in
    if line="" then length else
    match String.index_opt line ':' with
    |Some colon when String.lowercase_ascii (String.sub line 0 colon)="content-length" ->
        headers (int_of_string (String.trim (String.sub line (colon+1) (String.length line-colon-1))))
    |_->headers length in
  let length=headers (-1) in
  if length<0 || length>64*1024*1024 then failwith "invalid LSP Content-Length";
  let bytes=Bytes.create length in
  read bytes 0 length;
  Yojson.Basic.from_string (Bytes.unsafe_to_string bytes)

let params_field = function `Null -> [] |params -> ["params",params]
let notify c method_ params = send c (`Assoc (["jsonrpc",`String "2.0";
  "method",`String method_] @ params_field params))

let request c method_ params =
  let id=c.next_id in c.next_id<-id+1;
  send c (`Assoc (["jsonrpc",`String "2.0";"id",`Int id;
    "method",`String method_] @ params_field params));
  let deadline=Unix.gettimeofday ()+.30. in
  let rec await () =
    let value=receive c deadline in
    if member "id" value=`Int id && member "method" value=`Null then
      match member "error" value with
      |`Null -> member "result" value
      |error -> failwith (method_^": "^Yojson.Basic.to_string error)
    else begin
      (* Advertise no dynamic features; still answer server requests rather
         than deadlocking if a server asks for configuration. *)
      (match member "method" value,member "id" value with
       |`String "workspace/configuration",(`Int _|`String _ as id) ->
           let items=list (member "items" (member "params" value)) in
           send c (`Assoc ["jsonrpc",`String "2.0";"id",id;
             "result",`List (List.map (fun _ -> `Null) items)])
       |`String _,(`Int _|`String _ as id) ->
           send c (`Assoc ["jsonrpc",`String "2.0";"id",id;
             "error",`Assoc ["code",`Int (-32601);"message",`String "Unsupported client method"]])
       |_->());
      await ()
    end in
  await ()

let start server =
  let child_in,parent_out=Unix.pipe ~cloexec:true () in
  let parent_in,child_out=Unix.pipe ~cloexec:true () in
  let log=Unix.openfile "/dev/null" [Unix.O_WRONLY] 0 in
  let pid=try Unix.create_process server [|server|] child_in child_out log with exn ->
    List.iter Unix.close [child_in;parent_out;parent_in;child_out;log];raise exn in
  List.iter Unix.close [child_in;child_out;log];
  {pid;input=parent_in;output=parent_out;next_id=1;closed=false}

let stop c =
  if not c.closed then begin
    c.closed<-true;
    (try ignore (request c "shutdown" `Null);notify c "exit" `Null with _ -> ());
    Unix.close c.output;Unix.close c.input;
    (* A non-cooperative server cannot leave an orphan behind on shutdown. *)
    let deadline=Unix.gettimeofday ()+.1. in
    let rec reap () = match Unix.waitpid [Unix.WNOHANG] c.pid with
      |0,_ when Unix.gettimeofday ()<deadline -> ignore (Unix.select [] [] [] 0.01);reap ()
      |0,_ -> Unix.kill c.pid Sys.sigkill;ignore (Unix.waitpid [] c.pid)
      |_->() in
    reap ()
  end

let read_file path =
  let input=open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr input)
    (fun () -> really_input_string input (in_channel_length input))

let supported path = Filename.check_suffix path ".ml" || Filename.check_suffix path ".mli"

type report = {server_version:string; parsed:int; reused:int; unsupported:int;
  symbol_count:int; elapsed:float}

let load ?cache_directory ~server ~root paths =
  let started=Unix.gettimeofday () and root=Unix.realpath root in
  let c=start server in
  Fun.protect ~finally:(fun () -> stop c) (fun () ->
    let initialized=request c "initialize" (`Assoc [
      "processId",`Int (Unix.getpid ());"rootUri",`String (uri root);
      "capabilities",`Assoc ["textDocument",`Assoc ["documentSymbol",`Assoc [
        "hierarchicalDocumentSymbolSupport",`Bool true]]]]) in
    if member "documentSymbolProvider" (member "capabilities" initialized)=`Null then
      failwith "LSP server does not provide document symbols";
    notify c "initialized" (`Assoc []);
    let server_version=string (member "version" (member "serverInfo" initialized)) in
    let stamp=root^"|"^server^"|"^server_version^"|source-strata-v1" in
    (* One bounded snapshot per working directory, replaced atomically. *)
    let cache_dir=Option.value cache_directory
      ~default:(Filename.concat (Sys.getcwd ()) "_build/code_quadtree") in
    if not (Sys.file_exists (Filename.dirname cache_dir)) then
      Unix.mkdir (Filename.dirname cache_dir) 0o755;
    if not (Sys.file_exists cache_dir) then Unix.mkdir cache_dir 0o755;
    let cache_path=Filename.concat cache_dir "symbols.json" in
    let cached=try
      let json=Yojson.Basic.from_file cache_path in
      if member "stamp" json=`String stamp then list (member "files" json) else []
      with Sys_error _|Yojson.Json_error _ -> [] in
    let old=Hashtbl.create (List.length cached) in
    List.iter (fun entry -> Hashtbl.replace old (string (member "path" entry)) entry) cached;
    let parsed=ref 0 and reused=ref 0 and unsupported=ref 0 and total=ref 0
    and last_progress=ref 0 in
    let entries=ref [] in
    let results=Array.mapi (fun i relative ->
      if not (supported relative) then (incr unsupported;None) else begin
        let absolute=Filename.concat root relative in
        let source=read_file absolute in
        let digest=Digest.to_hex (Digest.string source) in
        let result=match Hashtbl.find_opt old relative with
          |Some entry when member "digest" entry=`String digest ->
              incr reused;member "symbols" entry
          |_->
              let document_uri=uri absolute in
              notify c "textDocument/didOpen" (`Assoc ["textDocument",`Assoc [
                "uri",`String document_uri;"languageId",`String "ocaml";
                "version",`Int 1;"text",`String source]]);
              let result=Fun.protect ~finally:(fun () ->
                notify c "textDocument/didClose" (`Assoc ["textDocument",`Assoc ["uri",`String document_uri]]))
                (fun () -> request c "textDocument/documentSymbol"
                  (`Assoc ["textDocument",`Assoc ["uri",`String document_uri]])) in
              incr parsed;result in
        let tree=symbols result in
        total:= !total+count tree;
        entries:=`Assoc ["path",`String relative;"digest",`String digest;
          "symbols",`List (List.map symbol_json tree)] :: !entries;
        if !parsed >= !last_progress+100 then begin
          last_progress:= !parsed;
          Printf.eprintf "LSP index %d/%d files, %d symbols\n%!"
            (i+1) (Array.length paths) !total
        end;
        Some tree
      end) paths in
    let temporary=cache_path^Printf.sprintf ".%d.tmp" (Unix.getpid ()) in
    Fun.protect ~finally:(fun () -> if Sys.file_exists temporary then Sys.remove temporary)
      (fun () -> Yojson.Basic.to_file temporary (`Assoc ["stamp",`String stamp;
        "files",`List (List.rev !entries)]);Sys.rename temporary cache_path);
    let report={server_version;parsed= !parsed;reused= !reused;unsupported= !unsupported;
      symbol_count= !total;elapsed=Unix.gettimeofday ()-.started} in
    Printf.eprintf "OCaml LSP %s: %d symbols, %d parsed / %d cached / %d non-OCaml, %.2fs\n%!"
      report.server_version report.symbol_count report.parsed report.reused
      report.unsupported report.elapsed;
    results,report)
