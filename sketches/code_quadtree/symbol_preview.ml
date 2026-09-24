type source = {path:string;lines:string array;error:string option}

let density span = 25 + min 64 (int_of_float (log (float (max 1 span+1))*.12.))
let kind = function
  |1->"FILE"|2->"MODULE"|3->"NAMESPACE"|4->"PACKAGE"|5->"CLASS"
  |6->"METHOD"|7->"PROPERTY"|8->"FIELD"|9->"CONSTRUCTOR"|10->"ENUM"
  |11->"INTERFACE"|12->"FUNCTION"|13->"VARIABLE"|14->"CONSTANT"
  |15->"STRING"|16->"NUMBER"|17->"BOOLEAN"|18->"ARRAY"|19->"OBJECT"
  |20->"KEY"|21->"NULL"|22->"ENUM MEMBER"|23->"STRUCT"|24->"EVENT"
  |25->"OPERATOR"|26->"TYPE PARAMETER"|_->"SYMBOL"

let shorten limit text =
  if String.length text<=limit then text else
    let stop=ref (max 0 (limit-3)) in
    while !stop>0 && Char.code text.[!stop] land 0xc0=0x80 do decr stop done;
    String.sub text 0 !stop ^ "..."

(* Only the current hover file is retained. Hovering another symbol in that
   file performs no I/O. A restart refreshes the source/LSP snapshot. *)
let load ~root ~path previous = match previous with
  |Some source when source.path=path -> source
  |_->
      try
        let full=Filename.concat root path in
        if (Unix.stat full).Unix.st_size>8*1024*1024 then
          {path;lines=[||];error=Some "Source preview exceeds 8 MiB"}
        else
          let input=open_in_bin full in
          let lines=Fun.protect ~finally:(fun ()->close_in_noerr input) (fun () ->
            let lines=ref [] and bytes=ref 0 in
            (try while true do
              let line=input_line input in
              bytes:= !bytes+String.length line+1;
              if !bytes>8*1024*1024 then failwith "Source preview exceeds 8 MiB";
              lines:=line::!lines
            done with End_of_file->());
            Array.of_list (List.rev !lines)) in
          {path;lines;error=None}
      with Sys_error message|Failure message -> {path;lines=[||];error=Some message}
        |Unix.Unix_error (_,_,_) -> {path;lines=[||];error=Some "Source file unavailable"}

let excerpt source ~first ~last =
  let first=max 0 first in
  let count=max 0 (min 3 (min (last-first+1) (Array.length source.lines-first))) in
  Array.init count (fun i -> first+i+1,
    String.concat "    " (String.split_on_char '\t' source.lines.(first+i)))
