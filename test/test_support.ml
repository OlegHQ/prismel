(* The assertions the test_main modules share. A test opens this module unless it reports
   under its own name; tools/dedupe removes a local copy the compiler resolves to the
   definition here. *)

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
