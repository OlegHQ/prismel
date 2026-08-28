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

module Workspace = struct
  type t = { mutable color : bytes; mutable clip : bytes; mutable depth : bytes;
    mutable transformed : Float.Array.t }
  let create () = { color=Bytes.empty; clip=Bytes.empty; depth=Bytes.empty;
    transformed=Float.Array.create 0 }
  let storage bytes length =
    if Bytes.length bytes = length then bytes else Bytes.create length
  let color t length = let bytes=storage t.color length in t.color<-bytes;bytes
  let clip t length = let bytes=storage t.clip length in t.clip<-bytes;bytes
  let depth t length = let bytes=storage t.depth length in t.depth<-bytes;bytes
  let transformed t length =
    if Float.Array.length t.transformed < length then begin
      let capacity=ref(max 16(Float.Array.length t.transformed))in
      while!capacity<length do
        capacity:=if!capacity>length/2 then length else!capacity*2
      done;
      t.transformed<-Float.Array.create !capacity
    end;
    t.transformed
end

let execute ?depth ?workspace ~lookup ~target ir =
  (* Execution is synchronous and never retains a command or nested payload.
     Borrow the validated immutable storage instead of defensively cloning the
     complete geometry graph on every frame. *)
  let commands = Render_ir.Private.commands_readonly ir in
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
      (* A workspace is exclusively borrowed for this synchronous execution.
         Its buffers are only staging storage: the authoritative attachments
         are updated together after every command has succeeded. *)
      let workspace = Option.value workspace ~default:(Workspace.create ()) in
      let target_bytes = Surface.bytes target in
      let working_bytes = Workspace.color workspace (Bytes.length target_bytes) in
      Bytes.blit target_bytes 0 working_bytes 0 (Bytes.length target_bytes);
      match Surface.of_bytes ~width:(Surface.width target) ~height:(Surface.height target)
              ~pitch:(Surface.pitch target) working_bytes with
      | Error _ -> Error Surface_error
      | Ok working ->
          let depth_copy=match depth with None->None|Some d->let source=Depth_stencil.bytes d.attachment in let bytes=Workspace.depth workspace(Bytes.length source)in Bytes.blit source 0 bytes 0(Bytes.length source);(match Depth_stencil.of_bytes~width:(Depth_stencil.width d.attachment)~height:(Depth_stencil.height d.attachment)~pitch:(Depth_stencil.pitch d.attachment)bytes with Ok attachment->Some(d,attachment)|Error _->fail Surface_error;None)in
          let clips = Stack.create () and transforms = Stack.create () in
          let identity = { Render_ir.xx=1.; xy=0.; yx=0.; yy=1.; tx=0.; ty=0. } in
          Stack.push identity transforms;
          let active_clip = ref None in
          let active_blend = ref Composite.Source_over in
          let default_depth_state =
            { Depth_stencil.depth_compare=Always; depth_write=false; stencil=None }
          in
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
                let before = Workspace.clip workspace (Bytes.length working_bytes) in
                Bytes.blit working_bytes 0 before 0 (Bytes.length working_bytes);
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
                  let vertex_count = Array.length geometry.vertices / 2 in
                  (* Transform each referenced vertex once.  Tessellated paths share
                     vertices heavily; rebuilding three records (and rounding twice)
                     per triangle made the command consumer allocate in proportion to
                     index count rather than vertex count. *)
                  let packed=match depth with Some _->None|None->
                    let packed=Workspace.transformed workspace(vertex_count*2)in
                    for index=0 to vertex_count-1 do
                      let x,y=point transform geometry.vertices.(index*2)
                        geometry.vertices.(index*2+1)in
                      Float.Array.unsafe_set packed(index*2)(float x);
                      Float.Array.unsafe_set packed(index*2+1)(float y)
                    done;Some packed in
                  let transformed = match depth with None->[||]|Some _->
                    Array.init vertex_count (fun index ->
                      let x,y=point transform geometry.vertices.(index*2)
                        geometry.vertices.(index*2+1)in
                      { Triangle.x=float x;y=float y;
                        depth=(match depth with None->0. | Some d->d.value);
                        color=geometry.color; u=0.; v=0. })
                  in
                  let clip =
                    match !active_clip with
                    | None -> { Triangle.x=0; y=0; width=Surface.width working;
                                height=Surface.height working }
                    | Some r -> { Triangle.x=int_of_float r.x; y=int_of_float r.y;
                                  width=int_of_float r.width; height=int_of_float r.height }
                  in
                  let depth_attachment = Option.map snd depth_copy in
                  let depth_state = match depth with None -> default_depth_state | Some d -> d.state in
                  let fast_rectangle =
                    depth=None && vertex_count=4
                    && geometry.indices=[|0;1;2;0;2;3|]
                    && let packed=Option.get packed in
                       let ax=Float.Array.unsafe_get packed 0 and ay=Float.Array.unsafe_get packed 1
                       and bx=Float.Array.unsafe_get packed 2 and by=Float.Array.unsafe_get packed 3
                       and cx=Float.Array.unsafe_get packed 4 and cy=Float.Array.unsafe_get packed 5
                       and dx=Float.Array.unsafe_get packed 6 and dy=Float.Array.unsafe_get packed 7 in
                       ay=by&&bx=cx&&cy=dy&&dx=ax
                       &&bx>ax&&cy>ay
                       &&List.for_all(fun value->Float.is_finite value&&value=floor value)
                           [ax;ay;cx;cy]
                       &&let x=max clip.x(int_of_float ax)
                         and y=max clip.y(int_of_float ay)
                         and right=min(clip.x+clip.width)(int_of_float cx)
                         and bottom=min(clip.y+clip.height)(int_of_float cy)in
                         let width=max 0(right-x)and height=max 0(bottom-y)in
                         if width=Surface.width working&&height=Surface.height working
                            &&x=0&&y=0
                            &&Int32.logand geometry.color 0xffl=0xffl
                            &&match!active_blend with Composite.Source_over|Copy|Replace->true|_->false
                         then(Surface.clear working geometry.color;true)
                         else false in
                  if not fast_rectangle then
                    for triangle = 0 to (Array.length geometry.indices / 3) - 1 do
                      let vertex corner = geometry.indices.((triangle * 3) + corner) in
                      let a = vertex 0 and b = vertex 1 and c = vertex 2 in
                      match depth with
                      |None->let packed=Option.get packed in Triangle.Private.draw_solid_xy ~color:working
                        ~blend:!active_blend ~cull:Triangle.Cull_none ~clip
                        ~packed:(Int32.to_int geometry.color)
                        (Float.Array.unsafe_get packed(a*2))(Float.Array.unsafe_get packed(a*2+1))
                        (Float.Array.unsafe_get packed(b*2))(Float.Array.unsafe_get packed(b*2+1))
                        (Float.Array.unsafe_get packed(c*2))(Float.Array.unsafe_get packed(c*2+1))
                      |Some _->Triangle.draw ~color:working ~depth:depth_attachment ~depth_state
                        ~blend:!active_blend ~cull:Triangle.Cull_none ~clip ~texture:None
                        transformed.(a) transformed.(b) transformed.(c)
                    done
              | Image image ->
                  let source = match Hashtbl.find resources image.resource_id with Image value -> value | _ -> assert false in
                  let convert (r : Render_ir.rect) =
                    { Image.x=int_of_float (Float.round r.x); y=int_of_float (Float.round r.y);
                      width=int_of_float (Float.round r.width); height=int_of_float (Float.round r.height) }
                  in
                  let transform=Stack.top transforms in
                  draw (fun () -> match Image.blit_affine_blend ~blend:!active_blend ~src:source ~src_rect:(convert image.source)
                    ~dst:working ~dst_rect:(convert image.destination) ~xx:transform.xx ~xy:transform.xy ~yx:transform.yx ~yy:transform.yy ~tx:transform.tx ~ty:transform.ty ~filter:Image.Bilinear with
                    | Ok () -> () | Error _ -> fail Surface_error)
              | Debug_text text ->
                  let x, y = point (Stack.top transforms) text.x text.y in
                  draw (fun () ->
                    match Debug_font.draw ~target:working ~blend:!active_blend
                      ~x ~y ~color:text.color text.text with
                    | Ok () -> ()
                    | Error Debug_font.Text_too_long -> fail Surface_error)
              | Glyphs glyphs ->
                  let atlas =
                    (match Hashtbl.find resources glyphs.resource_id with
                    | Glyph_atlas value -> value
                    | _ -> assert false)
                  in
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
                        draw (fun () ->
                          (match Image.alpha_mask_blend ~dst:working
                            ~dst_x:(int_of_float glyph.x) ~dst_y:(int_of_float glyph.y)
                            ~width:atlas.cell_width ~height:atlas.cell_height ~pitch:atlas.cell_width
                            mask ~blend:!active_blend ~color:glyphs.color with
                          | Ok () -> ()
                          | Error _ -> fail Surface_error)))
                    glyphs.glyphs)
            commands;
          match !failure with
          | Some error -> Error error
          | None -> Bytes.blit working_bytes 0 target_bytes 0 (Bytes.length target_bytes);(match depth,depth_copy with Some d,Some(_,a)->Bytes.blit(Depth_stencil.bytes a)0(Depth_stencil.bytes d.attachment)0(Bytes.length(Depth_stencil.bytes a))|_->());Ok ()
