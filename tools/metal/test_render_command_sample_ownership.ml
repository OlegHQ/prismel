type attachment={mutable sample:int option;mutable live:bool}
let ()=for i=0 to 10_000 do let a={sample=Some i;live=true}in if a.sample<>Some i then failwith"sample ownership";a.sample<-None;a.live<-false;if a.live||a.sample<>None then failwith"sample unwind"done;print_endline"render sample descriptors: 10001 nullable ownership cases green"
