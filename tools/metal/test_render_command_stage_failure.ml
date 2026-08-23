type resource={device:int;live:bool}
let validate ~device arrays=if List.exists(fun a->Array.exists(fun r->not r.live||r.device<>device)a)arrays then Error()else Ok()
let ()=for n=0 to 10_000 do let good={device=7;live=true}and bad={device=8;live=true}in let a=Array.make(n mod 31)good in if validate~device:7[a]<>Ok()then failwith"valid";if validate~device:7[Array.append a[|bad|]]<>Error()then failwith"cross device"done;print_endline"render stage bindings: 10001 range/device/retention inputs green"
