type glyph_atlas = {
  width : int;
  height : int;
  pitch : int;
  bytes : bytes;
  cell_width : int;
  cell_height : int;
}

type resource = Image of Surface.t | Glyph_atlas of glyph_atlas
type depth={attachment:Depth_stencil.t;state:Depth_stencil.state;value:float;clear:float;clear_stencil:int}
type error = Missing_resource of int | Wrong_resource_kind of int | Invalid_resource of int | Surface_error | Scratch_limit

let execute ?depth ~lookup ~target ir =
  let commands = Render_ir.commands ir in
  let resources = Hashtbl.create 16 and failure = ref None in
  let fail error = if !failure = None then failure := Some error in
  Array.iter
    (function
      | Render_ir.Image image ->
          (match lookup image.resource_id with
          | None -> fail (Missing_resource image.resource_id)
          | Some (Image _ as resource) -> Hashtbl.replace resources image.resource_id resource
          | Some _ -> fail (Wrong_resource_kind image.resource_id))
      | Render_ir.Glyphs glyphs ->
          (match lookup glyphs.resource_id with
          | None -> fail (Missing_resource glyphs.resource_id)
          | Some (Glyph_atlas atlas as resource) ->
              if atlas.width < 0 || atlas.height < 0 || atlas.cell_width <= 0
                 || atlas.cell_height <= 0 || atlas.pitch < atlas.width
                 || (atlas.height <> 0 && atlas.pitch > max_int / atlas.height)
                 || Bytes.length atlas.bytes < atlas.pitch * atlas.height
              then fail (Invalid_resource glyphs.resource_id)
              else Hashtbl.replace resources glyphs.resource_id resource
          | Some _ -> fail (Wrong_resource_kind glyphs.resource_id))
      | _ -> ())
    commands;
  (match depth with Some d when Depth_stencil.width d.attachment<>Surface.width target||Depth_stencil.height d.attachment<>Surface.height target->fail Surface_error|_->());
  match !failure with
  | Some error -> Error error
  | None when Bytes.length (Surface.bytes target) > 268_435_456 -> Error Scratch_limit
  | None ->
      let target_bytes = Surface.bytes target in
      let working_bytes = Bytes.copy target_bytes in
      match Surface.of_bytes ~width:(Surface.width target) ~height:(Surface.height target)
              ~pitch:(Surface.pitch target) working_bytes with
      | Error _ -> Error Surface_error
      | Ok working ->
          let depth_copy=match depth with None->None|Some d->let bytes=Bytes.copy(Depth_stencil.bytes d.attachment)in(match Depth_stencil.of_bytes~width:(Depth_stencil.width d.attachment)~height:(Depth_stencil.height d.attachment)~pitch:(Depth_stencil.pitch d.attachment)bytes with Ok attachment->Some(d,attachment)|Error _->fail Surface_error;None)in
          let clips = Stack.create () and transforms = Stack.create () in
          let identity = { Render_ir.xx=1.; xy=0.; yx=0.; yy=1.; tx=0.; ty=0. } in
          Stack.push identity transforms;
          let active_clip = ref None in
          let active_blend = ref Composite.Source_over in
          let compose (a : Render_ir.transform) (b : Render_ir.transform) =
            { Render_ir.xx=(a.xx *. b.xx) +. (a.xy *. b.yx);
              xy=(a.xx *. b.xy) +. (a.xy *. b.yy);
              yx=(a.yx *. b.xx) +. (a.yy *. b.yx);
              yy=(a.yx *. b.xy) +. (a.yy *. b.yy);
              tx=(a.xx *. b.tx) +. (a.xy *. b.ty) +. a.tx;
              ty=(a.yx *. b.tx) +. (a.yy *. b.ty) +. a.ty }
          in
          let point (t : Render_ir.transform) x y =
            (int_of_float (Float.round ((t.xx *. x) +. (t.xy *. y) +. t.tx)),
             int_of_float (Float.round ((t.yx *. x) +. (t.yy *. y) +. t.ty)))
          in
          let inside x y =
            match !active_clip with
            | None -> true
            | Some (r : Render_ir.rect) ->
                float x >= r.x && float y >= r.y && float x < r.x +. r.width
                && float y < r.y +. r.height
          in
          let draw action =
            match !active_clip with
            | None -> action ()
            | Some _ ->
                let before = Bytes.copy working_bytes in
                action ();
                for y = 0 to Surface.height working - 1 do
                  for x = 0 to Surface.width working - 1 do
                    if not (inside x y) then
                      let offset = (y * Surface.pitch working) + (x * 4) in
                      Bytes.blit before offset working_bytes offset 4
                  done
                done
          in
          Array.iter
            (function
              | Render_ir.Clear color -> Surface.clear working color;(match depth_copy with None->()|Some(d,a)->if Depth_stencil.clear a~depth:d.clear~stencil:d.clear_stencil<>Ok()then fail Surface_error)
              | Set_blend blend -> active_blend := blend
              | Push_clip rect ->
                  Stack.push !active_clip clips;
                  active_clip := Some rect
              | Pop_clip -> active_clip := Stack.pop clips
              | Push_transform transform ->
                  Stack.push (compose (Stack.top transforms) transform) transforms
              | Pop_transform -> ignore (Stack.pop transforms)
              | Geometry geometry ->
                  let transform = Stack.top transforms in
                  for triangle = 0 to (Array.length geometry.indices / 3) - 1 do
                    let vertex corner = geometry.indices.((triangle * 3) + corner) * 2 in
                    let a = vertex 0 and b = vertex 1 and c = vertex 2 in
                    let make index=let x,y=point transform geometry.vertices.(index)geometry.vertices.(index+1)in {Triangle.x=float x;y=float y;depth=(match depth with None->0.|Some d->d.value);color=geometry.color;u=0.;v=0.}in
                    let clip=match !active_clip with None->{Triangle.x=0;y=0;width=Surface.width working;height=Surface.height working}|Some r->{Triangle.x=int_of_float r.x;y=int_of_float r.y;width=int_of_float r.width;height=int_of_float r.height}in
                    Triangle.draw~color:working~depth:(Option.map snd depth_copy)~depth_state:(match depth with None->{Depth_stencil.depth_compare=Always;depth_write=false;stencil=None}|Some d->d.state)~blend:!active_blend~cull:Triangle.Cull_none~clip~texture:None(make a)(make b)(make c)
                  done
              | Image image ->
                  let source = match Hashtbl.find resources image.resource_id with Image value -> value | _ -> assert false in
                  let convert (r : Render_ir.rect) =
                    { Image.x=int_of_float (Float.round r.x); y=int_of_float (Float.round r.y);
                      width=int_of_float (Float.round r.width); height=int_of_float (Float.round r.height) }
                  in
                  draw (fun () -> match Image.blit_scaled_blend ~blend:!active_blend ~src:source ~src_rect:(convert image.source)
                    ~dst:working ~dst_rect:(convert image.destination) ~filter:Image.Bilinear with
                    | Ok () -> () | Error _ -> fail Surface_error)
              | Glyphs glyphs ->
                  let atlas = match Hashtbl.find resources glyphs.resource_id with Glyph_atlas value -> value | _ -> assert false in
                  let columns = atlas.width / atlas.cell_width in
                  Array.iter
                    (fun (glyph : Render_ir.glyph) ->
                      if columns = 0 || glyph.glyph_id / columns * atlas.cell_height >= atlas.height
                      then fail (Invalid_resource glyphs.resource_id)
                      else
                        let column = glyph.glyph_id mod columns and row = glyph.glyph_id / columns in
                        let mask = Bytes.create (atlas.cell_width * atlas.cell_height) in
                        for y = 0 to atlas.cell_height - 1 do
                          Bytes.blit atlas.bytes (((row * atlas.cell_height) + y) * atlas.pitch + (column * atlas.cell_width))
                            mask (y * atlas.cell_width) atlas.cell_width
                        done;
                        draw (fun () -> match Image.alpha_mask_blend ~dst:working
                          ~dst_x:(int_of_float glyph.x) ~dst_y:(int_of_float glyph.y)
                          ~width:atlas.cell_width ~height:atlas.cell_height ~pitch:atlas.cell_width
                          mask ~blend:!active_blend ~color:glyphs.color with Ok () -> () | Error _ -> fail Surface_error))
                    glyphs.glyphs)
            commands;
          match !failure with
          | Some error -> Error error
          | None -> Bytes.blit working_bytes 0 target_bytes 0 (Bytes.length target_bytes);(match depth,depth_copy with Some d,Some(_,a)->Bytes.blit(Depth_stencil.bytes a)0(Depth_stencil.bytes d.attachment)0(Bytes.length(Depth_stencil.bytes a))|_->());Ok ()
