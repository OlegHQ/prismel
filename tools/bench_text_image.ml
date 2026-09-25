open Prismel

let get = function Ok value -> value | Error (`Msg message) -> failwith message

let percentile values fraction =
  let sorted = Array.copy values in
  Array.sort Float.compare sorted;
  sorted.(int_of_float (ceil (fraction *. float (Array.length sorted))) - 1)

let () =
  let font = get (Font.system ~size:36 ()) in
  let content = String.concat " " (List.init 16 (fun _ -> "Prismel")) in
  let samples = Array.make 100 0. in
  let render () =
    let image = get (Font.render_text font content (Font.Blended Color.white)) in
    let width, height = Image.get_size image in
    Image.destroy image;
    width, height in
  let width, height = render () in
  Gc.full_major ();
  let allocated = Gc.allocated_bytes () in
  for index = 0 to Array.length samples - 1 do
    let started = Unix.gettimeofday () in
    if render () <> (width, height) then failwith "text extent changed";
    samples.(index) <- Unix.gettimeofday () -. started
  done;
  Printf.printf "text_image,%d,%d,%d,%.0f,%.6f,%.6f\n%!"
    (String.length content) width height
    ((Gc.allocated_bytes () -. allocated) /. float (Array.length samples))
    (percentile samples 0.5) (percentile samples 0.95)
