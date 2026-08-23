open Binding_presentation_callback_lifecycle

let get = function Ok value -> value | Error _ -> failwith "unexpected rejection"

let expect_error = function
  | Error _ -> ()
  | Ok _ -> failwith "expected lifecycle rejection"

let () =
  for handlers = 0 to 10_000 do
    let recording =
      let rec add remaining value =
        if remaining = 0 then value else add (remaining - 1) (get (add_handler value))
      in
      add handlers empty
    in
    let abandoned = get (destroy recording) in
    if pending_roots abandoned <> 0 || cancelled abandoned <> handlers then
      failwith "destroy-before-commit did not cancel every callback root";
    let submitted = get (commit recording) in
    expect_error (destroy submitted);
    let completed = complete submitted in
    if pending_roots completed <> 0 || fired completed <> handlers then
      failwith "completion did not consume every callback root";
    let completed_again = complete completed in
    if fired completed_again <> handlers then
      failwith "completion callback was not one-shot"
  done;
  let presented = get (present empty) in
  expect_error (present presented);
  expect_error (present (get (commit presented)));
  print_endline
    "presentation callback lifecycle: 10001 cancellation/completion cardinalities and one-shot presentation green"
