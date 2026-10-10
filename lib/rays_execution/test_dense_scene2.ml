open Scene_command.Render_ir

let get = function Ok value->value |Error error->
  failwith (Format.asprintf "%a" Rays_execution.pp_error error)
let identity={xx=1.;xy=0.;yx=0.;yy=1.;tx=0.;ty=0.}

let scene ~reference ~count ~phase =
  let commands=ref [] in
  let add command=commands:=command::!commands in
  add (Push_clip {x=3.;y=2.;width=57.;height=43.});
  add (Push_transform {identity with xx=0.87;yy=1.13;tx=0.375+.phase;ty=0.125});
  for group=0 to 1 do
    add (Set_blend (if group=0 then Alpha else Add));
    for i=0 to count-1 do
      let x=float (i*7 mod 64)-.2.125 and y=float (i*13 mod 48)-.1.375 in
      let color=Int32.logor (Int32.shift_left (Int32.of_int (i mod 255)) 24)
        (Int32.of_int (0x81b000 lor (45+i mod 180))) in
      add (Geometry {vertices=[|x;y;x+.7.25;y;x+.7.25;y+.4.5;x;y+.4.5|];
        indices=[|0;1;2;0;2;3|];color});
      (* Identity state barriers force the independently cached preparation
         path without changing pixels or painter order. *)
      if reference then (add (Push_transform identity);add Pop_transform)
    done
  done;
  add Pop_transform;add Pop_clip;
  Result.get_ok (create (Array.of_list (List.rev !commands)))

let run () =
  let live_handles=snd(Ogpu.Impl.create_driver()) in
  let baseline=live_handles() in
  List.iter (fun scale ->
    let execution=get (Rays_execution.create_offscreen
      {Rays_execution.
        logical_width=64;logical_height=48;drawable_width=64*scale;drawable_height=48*scale;
        title="dense-scene2";vsync=false;high_density=true}) in
    Fun.protect ~finally:(fun () -> ignore (get (Rays_execution.destroy execution)))
      (fun () ->
        let render _ir =
          get (Rays_execution.capture execution) in
        List.iter (fun count ->
          for frame=0 to 3 do
            let phase=float frame*.0.125 in
            let expected=render (scene ~reference:true ~count ~phase) in
            let ir=scene ~reference:false ~count ~phase in
            for repeat=0 to 2 do
              if render ir<>expected then failwith (Printf.sprintf
                "dense run drift: scale=%d count=%d frame=%d repeat=%d" scale count frame repeat)
            done
          done) [63;64;65;1024];
        let shifted tx=Result.get_ok (create [|Push_transform {identity with tx};
          Geometry {vertices=[|4.;4.;20.;4.;20.;20.;4.;20.|];indices=[|0;1;2;0;2;3|];
            color=0xffffffffl};Pop_transform|])
          |> Rays_execution.lower_scene2 execution ~density:scale ~resource:(fun _->None)
          |> get in
        let render_draws _draws=
          get (Rays_execution.capture execution) in
        ignore (shifted 1.);
        let first=shifted 2. in
        let expected=render_draws first in
        ignore (shifted 30.);
        if render_draws first<>expected then
          failwith "geometry cache hit rewrote an earlier lowering's transform")) [1;2];
  let after=live_handles() in
  if after<>baseline then failwith "dense scene2 handle delta";
  print_endline "dense scene2: exact 1x/2x pixels, alpha/add, fractional transforms, alternating retained payloads, zero handles"
