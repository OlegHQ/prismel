type t = bool Atomic.t
exception Cancelled

let create () = Atomic.make false
let cancel value = Atomic.set value true
let is_cancelled value = Atomic.get value
let check value = if is_cancelled value then raise Cancelled
let check_opt = function None -> () | Some value -> check value
