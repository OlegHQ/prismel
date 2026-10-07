open Flow.Phase_timer
let () =
  let time = ref 0. in
  let clock () = !time in
  let _, timing = sample ~clock (fun () -> measure Reduce (fun () ->
    time := 1.; measure Check (fun () -> time := 3.);
    time := 4.; measure Check (fun () -> time := 5.); time := 6.)) in
  assert (timing.total = 6. && seconds timing Reduce = 3.);
  assert (calls timing Check = 2 && seconds timing Check = 3.);
  let _, outer = sample ~clock (fun () ->
    (try measure Check (fun () -> failwith "refused") with Failure _ -> ());
    ignore (sample ~clock (fun () -> measure Parse (fun () -> time := 7.)));
    measure Print (fun () -> time := 8.)) in
  assert (calls outer Check = 1 && calls outer Parse = 1 && calls outer Print = 1);
  let _, backward = sample ~clock (fun () -> measure Check (fun () -> time := 0.)) in
  assert (backward.total = 0. && seconds backward Check = 0.);
  (try ignore (sample ~clock (fun () -> failwith "outside")) with Failure _ -> ());
  measure Check (fun () -> ());
  let _, next = sample ~clock (fun () -> ()) in
  assert (next.entries = []);
  let _, parent = sample ~clock (fun () ->
    let child = Domain.spawn (fun () ->
      let _, child = sample ~clock:(fun () -> 0.) (fun () -> measure Lower (fun () -> ())) in
      assert (calls child Lower = 1)) in
    Domain.join child) in
  assert (parent.entries = [])
