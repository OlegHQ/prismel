open Prismel_math

let guard work = Error.guard ~operation:"curve_sampling"
    ~code:"invalid_parameter" work

let check_resolution resolution =
  if resolution < 1 || resolution >= Sys.max_array_length then
    Error "resolution must be positive and fit output cardinality"
  else Ok ()

let check_cardinality spans resolution =
  if spans > (Sys.max_array_length - 1) / resolution then
    Error "sample cardinality exceeds OCaml array limits"
  else Ok ()

let ( let* ) = Result.bind

let quadratic2 ?cancel ~resolution ~from_ ~control ~to_ () = guard (fun () ->
  let* () = check_resolution resolution in
  Cancel.check_opt cancel;
  Ok (List.init (resolution + 1) (fun index ->
    if index land 4095 = 0 then Cancel.check_opt cancel;
    let amount = float_of_int index /. float_of_int resolution in
    let inverse = 1. -. amount in
    Vec2.add
      (Vec2.add
         (Vec2.scale from_ (inverse *. inverse))
         (Vec2.scale control (2. *. inverse *. amount)))
      (Vec2.scale to_ (amount *. amount)))))

let cubic2 ?cancel ~resolution ~from_ ~control1 ~control2 ~to_ () =
  guard (fun () ->
    let* () = check_resolution resolution in
    Cancel.check_opt cancel;
    Ok (List.init (resolution + 1) (fun index ->
      if index land 4095 = 0 then Cancel.check_opt cancel;
      let amount = float_of_int index /. float_of_int resolution in
      let inverse = 1. -. amount in
      Vec2.add
        (Vec2.add
           (Vec2.scale from_ (inverse *. inverse *. inverse))
           (Vec2.scale control1
              (3. *. inverse *. inverse *. amount)))
        (Vec2.add
           (Vec2.scale control2
              (3. *. inverse *. amount *. amount))
           (Vec2.scale to_ (amount *. amount *. amount))))))

let equal2 (left : Vec2.t) (right : Vec2.t) =
  left.x = right.x && left.y = right.y

let equal3 (left : Vec3.t) (right : Vec3.t) =
  left.x = right.x && left.y = right.y && left.z = right.z

let normalize ~equal ~closed supplied =
  let points = List.fold_left (fun result point -> match result with
    | previous :: _ when equal previous point -> result
    | _ -> point :: result) [] supplied |> List.rev in
  if closed then match points, List.rev points with
    | first :: _, last :: rest when equal first last -> List.rev rest
    | _ -> points
  else points

let catmull_rom2 ?cancel ?(closed = false) ?(tension = 0.) ~resolution supplied =
  guard (fun () ->
    let* () = check_resolution resolution in
    if not (Float.is_finite tension) then Error "tension must be finite"
    else begin
      Cancel.check_opt cancel;
      let controls = Array.of_list (normalize ~equal:equal2 ~closed supplied) in
      let count = Array.length controls in
      let minimum = if closed then 3 else 2 in
      if count < minimum then Error "insufficient distinct controls"
      else begin
        let span_count = if closed then count else count - 1 in
        let* () = check_cardinality span_count resolution in
        let get index =
          if closed then controls.((index mod count + count) mod count)
          else controls.(max 0 (min (count - 1) index)) in
        let tangent_scale = (1. -. tension) /. 2. in
        let samples = ref [] in
        for span = 0 to span_count - 1 do
          if span land 255 = 0 then Cancel.check_opt cancel;
          let p0 = get (span - 1) and p1 = get span
          and p2 = get (span + 1) and p3 = get (span + 2) in
          let m1 = Vec2.scale (Vec2.sub p2 p0) tangent_scale
          and m2 = Vec2.scale (Vec2.sub p3 p1) tangent_scale in
          for step = 0 to resolution - 1 do
            let t = float_of_int step /. float_of_int resolution in
            let t2 = t *. t and t3 = t *. t *. t in
            let h00 = (2. *. t3) -. (3. *. t2) +. 1.
            and h10 = t3 -. (2. *. t2) +. t
            and h01 = (-2. *. t3) +. (3. *. t2)
            and h11 = t3 -. t2 in
            let point = Vec2.add
              (Vec2.add (Vec2.scale p1 h00) (Vec2.scale m1 h10))
              (Vec2.add (Vec2.scale p2 h01) (Vec2.scale m2 h11)) in
            samples := point :: !samples
          done
        done;
        if not closed then samples := controls.(count - 1) :: !samples;
        Ok (List.rev !samples)
      end
    end)

let quadratic3 ?cancel ~resolution ~from_ ~control ~to_ () = guard (fun () ->
  let* () = check_resolution resolution in
  Cancel.check_opt cancel;
  Ok (List.init (resolution + 1) (fun index ->
    if index land 4095 = 0 then Cancel.check_opt cancel;
    let t = float_of_int index /. float_of_int resolution in
    let u = 1. -. t in
    Vec3.add (Vec3.add (Vec3.scale from_ (u *. u))
      (Vec3.scale control (2. *. u *. t))) (Vec3.scale to_ (t *. t)))))

let cubic3 ?cancel ~resolution ~from_ ~control1 ~control2 ~to_ () =
  guard (fun () ->
    let* () = check_resolution resolution in
    Cancel.check_opt cancel;
    Ok (List.init (resolution + 1) (fun index ->
      if index land 4095 = 0 then Cancel.check_opt cancel;
      let t = float_of_int index /. float_of_int resolution in
      let u = 1. -. t in
      Vec3.add (Vec3.add (Vec3.scale from_ (u *. u *. u))
        (Vec3.scale control1 (3. *. u *. u *. t)))
        (Vec3.add (Vec3.scale control2 (3. *. u *. t *. t))
          (Vec3.scale to_ (t *. t *. t))))))

let catmull_rom3 ?cancel ?(closed = false) ?(tension = 0.) ~resolution supplied =
  guard (fun () ->
    let* () = check_resolution resolution in
    if not (Float.is_finite tension) then Error "tension must be finite"
    else begin
    Cancel.check_opt cancel;
    let controls = Array.of_list (normalize ~equal:equal3 ~closed supplied) in
    let count = Array.length controls and minimum = if closed then 3 else 2 in
    if count < minimum then Error "insufficient distinct controls"
    else begin
      let spans = if closed then count else count - 1 in
      let* () = check_cardinality spans resolution in
      let get index = if closed then controls.((index mod count + count) mod count)
        else controls.(max 0 (min (count - 1) index)) in
      let output = ref [] in
      for span = 0 to spans - 1 do
        if span land 255 = 0 then Cancel.check_opt cancel;
        let p0 = get (span - 1) and p1 = get span
        and p2 = get (span + 1) and p3 = get (span + 2) in
        let m1 = Vec3.scale (Vec3.sub p2 p0) ((1. -. tension) /. 2.)
        and m2 = Vec3.scale (Vec3.sub p3 p1) ((1. -. tension) /. 2.) in
        for step = 0 to resolution - 1 do
          let t = float_of_int step /. float_of_int resolution in
          let t2 = t *. t and t3 = t *. t *. t in
          output := Vec3.add (Vec3.add (Vec3.scale p1
              (2. *. t3 -. 3. *. t2 +. 1.))
            (Vec3.scale m1 (t3 -. 2. *. t2 +. t)))
            (Vec3.add (Vec3.scale p2 (-.2. *. t3 +. 3. *. t2))
              (Vec3.scale m2 (t3 -. t2))) :: !output
        done
      done;
      if not closed then output := controls.(count - 1) :: !output;
      Ok (List.rev !output)
    end end)
