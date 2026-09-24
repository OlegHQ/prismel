open Prismel

(* A deterministic, asymmetric spatial index. File tiles contain a second
   recursive field derived from their source-line profile. *)
type glyph = {gx:float; gy:float; gs:float; symbol:Source_index.symbol option;
  descendants:glyph array; mass:int}
type file = { path : string; lines : int; bytes : int; profile : int array;
  symbols:Source_index.symbol list option; glyph:glyph option }
type node = { x : float; y : float; size : float; count : int; lines : int;
  children : node array; file : file option; label : string }

let root_dir = ref "."
let smoke = ref false
let export = ref ""
let frames = ref 0
let tour = ref false
let domains = ref 1
let verify = ref false
let server = ref "ocamllsp"
let index_only = ref false
let benchmark = ref false
let reference_draws = ref false
let hover_bench = ref false
let rebuild_art = ref false
let initial_zoom = ref 1.
let () = Arg.parse ["--root", Arg.Set_string root_dir, "Repository to map";
  "--smoke", Arg.Set smoke, "Render a finite 120-frame native zoom/pan tour";
  "--frames", Arg.Set_int frames, "Finite native or export frame count";
  "--tour", Arg.Set tour, "Animate a repeatable zoom/pan tour";
  "--domains", Arg.Set_int domains, "Reusable worker pool domain count";
  "--verify", Arg.Set verify, "Check deterministic tree coverage without a window";
  "--lsp", Arg.Set_string server, "OCaml language-server executable";
  "--index-only", Arg.Set index_only, "Build/refresh the real LSP symbol index and exit";
  "--bench", Arg.Set benchmark, "Report finite native run wall time and GC allocation";
  "--reference-draws", Arg.Set reference_draws, "Benchmark the equivalent unbatched Scene producers";
  "--hover-bench", Arg.Set hover_bench, "Exercise changing hover over a fixed dense view";
  "--rebuild-art", Arg.Set rebuild_art, "Diagnostic baseline: rebuild artwork when hover changes";
  "--zoom", Arg.Set_float initial_zoom, "Initial zoom for reproducible dense-view checks";
  "--export", Arg.Set_string export, "Export native PNGs to this directory"]
  (fun s -> raise (Arg.Bad s)) "Code Quadtree"

let () = if !frames < 0 || !domains < 1 then invalid_arg "frames >= 0, domains >= 1"
let () = if not (Float.is_finite !initial_zoom) || !initial_zoom<0.65 || !initial_zoom>180. then
  invalid_arg "zoom must be finite and between 0.65 and 180"

let hash text =
  String.fold_left (fun h c -> ((h lxor Char.code c) * 16777619) land 0x3fffffff)
    216613626 text

let source_ext path = List.exists (Filename.check_suffix path)
  [".ml";".mli";".mll";".mly";".c";".h";".cpp";".hpp";".metal";".dune"]
let excluded = [".git";"_build";".DS_Store";"node_modules";"_opam";"vendor"]
let source_profile path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    let n = ref 0 and profile = Array.make 32 0 in
    (try while true do
      let line = input_line ic in
      let slot = !n mod 32 in
      profile.(slot) <- max profile.(slot) (min 120 (String.length line));
      incr n
    done with End_of_file -> ()); !n,profile)
let scan root =
  let rec walk rel acc =
    let dir = if rel = "" then root else Filename.concat root rel in
    Sys.readdir dir |> Array.to_list |> List.sort String.compare
    |> List.fold_left (fun acc name ->
      if List.mem name excluded || (String.length name > 0 && name.[0] = '.') then acc else
      let child = if rel = "" then name else rel ^ "/" ^ name in
      let full = Filename.concat root child in
      try if (Unix.lstat full).Unix.st_kind = Unix.S_LNK then acc
      else if Sys.is_directory full then walk child acc
      else if source_ext name then
        let bytes = (Unix.stat full).Unix.st_size in
        let lines,profile=source_profile full in
        {path=child; lines; bytes; profile;symbols=None;glyph=None} :: acc
      else acc with Sys_error _ | Unix.Unix_error _ -> acc) acc in
  walk "" [] |> List.sort (fun a b -> String.compare a.path b.path) |> Array.of_list

let common_label files lo hi =
  let a = files.(lo).path and b = files.(hi-1).path in
  let stop = ref 0 in
  while !stop < min (String.length a) (String.length b) && a.[!stop] = b.[!stop] do incr stop done;
  let prefix = String.sub a 0 !stop in
  try String.sub prefix 0 (1 + String.rindex prefix '/') with Not_found -> "source"

let build (files:file array) =
  if Array.length files=0 then invalid_arg "build: empty repository";
  (* Prefix sums make each weighted cut logarithmic. Unequal, rotated quadrant
     budgets create multiple spatial scales, while every file appears once. *)
  let weights=Array.make (Array.length files+1) 0. in
  Array.iteri (fun i (file:file) -> weights.(i+1) <- weights.(i) +.
    1. +. sqrt (float file.lines)) files;
  let cut lo hi target =
    let a=ref lo and b=ref hi in
    while !a < !b do
      let mid=(!a + !b)/2 in
      if weights.(mid) < target then a:=mid+1 else b:=mid
    done; !a in
  let rec make x y size lo hi =
    let count = hi-lo in
    if count = 1 then
      {x;y;size;count;lines=files.(lo).lines;children=[||];file=Some files.(lo);
       label=files.(lo).path}
    else begin
      let seed=hash files.(lo).path lxor count in
      let ratios=[|0.07;0.15;0.29;0.49|] in
      let quadrants=min 4 count and cursor=ref lo and cumulative=ref 0. in
      let children = Array.init quadrants (fun i ->
        let q=(i + seed mod 4) mod 4 in
        let a= !cursor in
        cumulative:= !cumulative +. ratios.(i);
        let b=if i=quadrants-1 then hi else
          max (a+1) (min (hi-(quadrants-i-1))
            (cut a hi (weights.(lo) +. !cumulative *. (weights.(hi)-.weights.(lo))))) in
        cursor:=b;
        let dx = float (q mod 2) *. size *. 0.5
        and dy = float (q/2) *. size *. 0.5 in
        make (x+.dx) (y+.dy) (size*.0.5) a b) in
      let lines = Array.fold_left (fun n c -> n+c.lines) 0 children in
      {x;y;size;count;lines;children;file=None;label=common_label files lo hi}
    end in
  make 0. 0. 1. 0 (Array.length files)

let palette path =
  let starts prefix = String.starts_with ~prefix path in
  if starts "test/" then Color.rgb 179 181 171
  else if starts "sketches/" then Color.rgb 218 216 201
  else if starts "examples/" then Color.rgb 184 196 194
  else if starts "lib/metal" || starts "lib/ogpu" then Color.rgb 168 177 176
  else Color.rgb 227 227 214

let symbol_layout symbols =
  let ratios=[|0.10;0.18;0.29;0.43|] in
  let rec scope x y size symbols =
    let items=Array.of_list symbols in
    let weights=Array.make (Array.length items+1) 0. in
    Array.iteri (fun i s -> weights.(i+1)<-weights.(i)+.
      sqrt (float (max 1 (s.Source_index.last_line-s.first_line+1)))) items;
    pack items weights x y size 0 (Array.length items)
  and pack items weights x y size lo hi =
    let n=hi-lo in
    if n=0 then {gx=x;gy=y;gs=size;symbol=None;descendants=[||];mass=0}
    else if n=1 then begin
        let symbol=items.(lo) in
        let descendants=match symbol.Source_index.children with [] -> [||]
          |children -> [|scope (x+.size*.0.08) (y+.size*.0.08) (size*.0.84) children|] in
        {gx=x;gy=y;gs=size;symbol=Some symbol;descendants;
         mass=max 1 (symbol.last_line-symbol.first_line+1)}
    end else begin
        let cursor=ref lo and fraction=ref 0. in
        let seed=hash items.(lo).name in
        let children=Array.init (min 4 n) (fun i ->
          let first= !cursor in
          fraction:= !fraction +. ratios.(i);
          let last=if i=min 4 n-1 then hi else begin
            let limit=hi-(min 4 n-i-1) in
            let target=weights.(lo)+. !fraction*.(weights.(hi)-.weights.(lo)) in
            let a=ref (first+1) and b=ref limit in
            while !a< !b do let mid=(!a+ !b)/2 in
              if weights.(mid)<target then a:=mid+1 else b:=mid
            done; !a end in
          cursor:=last;
          let q=(i+seed mod 4) mod 4 in
          pack items weights (x+.float(q mod 2)*.size*.0.5) (y+.float(q/2)*.size*.0.5)
            (size*.0.5) first last) in
        {gx=x;gy=y;gs=size;symbol=None;descendants=children;
         mass=Array.fold_left (fun n c -> n+c.mass) 0 children}
    end in
  scope 0. 0. 1. symbols

let rec pick_glyph glyph x y =
  if x<glyph.gx || y<glyph.gy || x>=glyph.gx+.glyph.gs || y>=glyph.gy+.glyph.gs
  then None else
  let nested=Array.fold_left (fun found child -> match found with
    |Some _ -> found |None -> pick_glyph child x y) None glyph.descendants in
  match nested with Some _ -> nested |None -> Option.map (fun _->glyph) glyph.symbol

let pick_symbol glyph x y = Option.bind (pick_glyph glyph x y) (fun glyph->glyph.symbol)

type model = { tree : node; files : int; total_lines : int; cx : float; cy : float;
  zoom : float; target_x : float; target_y : float; target_zoom : float;
  hover : node option; show_ui : bool; press : (float * float) option;
  dragged : bool; index : Source_index.report; show_cells:bool;
  scene_cache:((int*int*float*float*float*bool*bool*(float*float))*Scene.t) option;
  art_cache:((int*int*float*float*float*bool)*Scene.node) option;
  art_builds:int;
  preview_source:Symbol_preview.source option;
  art_ids:int64 array;overlay_ids:int64 array }

let sidebar f = if f.Frame.width >= 1100 then 302 else 0
let footer_top f = max 0 (f.Frame.height-132)
let art_bottom f = footer_top f-12
let in_art f (x,y) = x>=24. && x<float(f.Frame.width-sidebar f-22)
  && y>=74. && y<float(art_bottom f)
let world_size f = float (max 64 (min (f.Frame.width-sidebar f-88) (art_bottom f-84)))
let center f = float (f.Frame.width-sidebar f) *. 0.5, float (74+art_bottom f)*.0.5
let screen m f x y =
  let s = world_size f *. m.zoom in
  let ox,oy=center f in
  (ox +. (x-.m.cx)*.s, oy +. (y-.m.cy)*.s)
let world m f sx sy =
  let s = world_size f *. m.zoom in
  let ox,oy=center f in
  (m.cx +. (sx-.ox)/.s, m.cy +. (sy-.oy)/.s)
let rec pick node x y =
  if x < node.x || y < node.y || x >= node.x+.node.size || y >= node.y+.node.size
  then None else
  let found = Array.fold_left (fun hit child -> match hit with
    | Some _ -> hit | None -> pick child x y) None node.children in
  match found with Some _ -> found | None -> Some node

let init files index _ =
  if Array.length files = 0 then failwith "No source files found under --root";
  let tree = build files in
  {tree;files=Array.length files;total_lines=tree.lines;
   cx=0.5;cy=0.5;zoom= !initial_zoom;target_x=0.5;target_y=0.5;target_zoom= !initial_zoom;
    hover=None;show_ui=true;press=None;dragged=false;index;show_cells=false;scene_cache=None;
    art_cache=None;art_builds=0;preview_source=None;
    art_ids=Array.init 64 (fun _ -> Scene_command.Display_list.fresh_id ());
    overlay_ids=Array.init 64 (fun _ -> Scene_command.Display_list.fresh_id ())}

let clamp a b v = max a (min b v)
let update m (f:Frame.t) =
  let ox,oy=center f in
  let target_x = ref m.target_x and target_y = ref m.target_y
  and target_zoom = ref m.target_zoom and show_ui = ref m.show_ui
  and press = ref m.press and dragged = ref m.dragged in
  let show_cells=ref m.show_cells in
  List.iter (function
    | Event.KeyPressed Input.Escape -> Sketch.quit ()
    | Event.KeyPressed (Input.KeyChar 'h') | Event.KeyPressed Input.Tab -> show_ui := not !show_ui
    | Event.KeyPressed (Input.KeyChar 't') -> show_cells:=not !show_cells
    | Event.KeyPressed (Input.KeyChar 'r') | Event.KeyPressed Input.Space ->
        target_x := 0.5; target_y := 0.5; target_zoom := 1.
    | Event.KeyPressed (Input.KeyChar 's') ->
        ignore (Canvas.save_screen_png "_out/code-quadtree.png")
    | Event.MouseScrolled (_,dy) when dy <> 0. && in_art f f.mouse ->
        let mx,my = f.mouse in
        let wx,wy = world m f mx my in
        let next = clamp 0.65 180. (!target_zoom *. exp (-.dy *. 0.17)) in
        target_x := wx -. (mx -. ox)/.(world_size f *. next);
        target_y := wy -. (my -. oy)/.(world_size f *. next);
        target_zoom := next
    | Event.MousePressed (Input.LeftButton,pos) when in_art f pos ->
        press := Some pos; dragged := false
    | Event.MouseReleased (Input.LeftButton,(mx,my)) ->
        (match !press with
         | Some (px,py) when in_art f (mx,my) && not !dragged
             && abs_float(mx-.px)+.abs_float(my-.py)<8. ->
             let wx,wy = world m f mx my in
             (match pick m.tree wx wy with
              | Some n -> target_x := n.x+.n.size*.0.5;
                  target_y := n.y+.n.size*.0.5;
                  target_zoom := clamp 0.65 180. (min (m.zoom*.3.2) (0.7/.n.size))
              | None -> ())
         | _ -> ()); press := None; dragged := false
    | Event.MousePressed (Input.RightButton,_) -> target_zoom := max 1. (m.zoom/.2.8)
    | _ -> ()) f.events;
  if (Frame.mouse_down Input.MiddleButton f && in_art f f.mouse ||
      Frame.mouse_down Input.LeftButton f && Option.is_some !press)
     && f.mouse_delta <> (0.,0.) then begin
    let dx,dy = f.mouse_delta in
    if Frame.mouse_down Input.LeftButton f && abs_float dx +. abs_float dy > 2.
    then dragged := true;
    target_x := !target_x -. dx /. (world_size f *. m.zoom);
    target_y := !target_y -. dy /. (world_size f *. m.zoom)
  end;
  if !smoke || !tour then begin
    let duration=if !frames>0 then !frames else 120 in
    let phase=f.count * 4 / max 1 duration in
    let focus=if Array.length m.tree.children=0 then m.tree else
      m.tree.children.(Array.length m.tree.children-1) in
    let x=focus.x+.focus.size*.0.5 and y=focus.y+.focus.size*.0.5 in
    let tx,ty,z=match phase with
      |0 -> 0.5,0.5,1. |1 -> x,y,3.8
      |2 -> x+.0.07,y-.0.06,12. |_->0.5,0.5,1. in
    target_x:=tx;target_y:=ty;target_zoom:=z
  end;
  let smooth = 1. -. exp (-.min 0.1 f.dt *. 11.) in
  let ease current target = if abs_float (target-.current)<0.00001 then target
    else current+.(target-.current)*.smooth in
  let zoom = ease m.zoom !target_zoom in
  let cx = ease m.cx !target_x and cy = ease m.cy !target_y in
  let mx,my = f.mouse in
  let hover = if not (in_art f f.mouse) then None else pick m.tree
    (cx +. (mx-.ox)/.(world_size f*.zoom))
    (cy +. (my-.oy)/.(world_size f*.zoom)) in
  let preview_source=match hover with
    |Some {file=Some file;_}->Some (Symbol_preview.load ~root:!root_dir ~path:file.path m.preview_source)
    |_->m.preview_source in
  {m with cx;cy;zoom;target_x= !target_x;target_y= !target_y;preview_source;
    target_zoom= !target_zoom;show_ui= !show_ui;hover;
    press= !press;dragged= !dragged;show_cells= !show_cells}

let art_key m (f:Frame.t) = (f.width,f.height,m.cx,m.cy,m.zoom,m.show_cells)

let view m (f:Frame.t) =
  let ink=Color.rgb 15 19 18 and paper=Color.rgb 225 216 192
  and muted=Color.rgb 129 137 118 and grid=Color.rgb 54 62 51
  and orange=Color.rgb 230 117 67 in
  let art_right=f.width-sidebar f-22 in
  let clip=(24,74,max 1 (art_right-24),max 1 (art_bottom f-74)) in
  let wrap node = let x,y,w,h=clip in Scene.clip ~at:(x,y) ~w ~h [node] in
  let drawing_art=ref true in
  let commands = ref [] in
  let packed=Packed_ink.create ~ids:m.art_ids ~version:(Int64.of_int f.count)
    ?clip:(if !reference_draws then None else Some clip) () in
  let flush () = Option.iter (fun node -> commands:=node::!commands) (Packed_ink.take packed) in
  let emit node = flush ();commands :=
    (if !drawing_art && not !reference_draws then wrap node else node) :: !commands in
  let rect x y w h ?fill ?stroke () =
    if w>0 && h>0 then if !reference_draws then
      emit (Scene.rect ~at:(x,y) ~w ~h ?fill ?stroke ()) else begin
      Option.iter (Packed_ink.rect packed x y w h) fill;
      Option.iter (Packed_ink.outline packed x y w h) stroke
    end in
  let rectf x y w h color =
    (* Keep the reference producer unbatched without reintroducing integer
       snapping in the comparison path. Both producers use the same floats. *)
    if !reference_draws then begin
      flush ();Packed_ink.rectf packed x y w h color;flush ()
    end else Packed_ink.rectf packed x y w h color in
  let line x y x2 y2 color =
    if !reference_draws then emit (Scene.line ~from_:(x,y) ~to_:(x2,y2) ~color ())
    else Packed_ink.line packed x y x2 y2 color in
  let linef x y x2 y2 color =
    if !reference_draws then begin
      flush ();Packed_ink.linef packed x y x2 y2 color;flush ()
    end else Packed_ink.linef packed x y x2 y2 color in
  let text x y size color value = emit (Scene.text ~at:(x,y) ~size ~color value) in
  let visible x y s = x+.s >= 24. && y+.s >= 74. &&
    x < float art_right && y < float (art_bottom f) in
  (* The nested branches below are actual LSP DocumentSymbol children.
     Halftone density encodes source span; no generated branches masquerade
     as functions or references. Spatial packing nodes have no symbol. *)
  let fade color opacity = Color.with_alpha color
    (int_of_float (float color.Color.a*.opacity)) in
  let rec strata (file:file) base_color origin_x origin_y extent opacity glyph =
    let color=fade base_color opacity in
    let x=origin_x+.glyph.gx*.extent and y=origin_y+.glyph.gy*.extent
    and s=glyph.gs*.extent in
    if color.Color.a>0 && visible x y s then begin
      if s<2. && Array.length glyph.descendants>0 then
        rectf (x+.s*.0.5-.0.5) (y+.s*.0.5-.0.5) 1. 1. color
      else if Array.length glyph.descendants>0 then begin
        let cx=x+.s*.0.5 and cy=y+.s*.0.5 in
        let detail=Mark_field.smooth 2. 4. s in
        if detail<1. then rectf (cx-.0.5) (cy-.0.5) 1. 1. (fade color (1.-.detail));
        if s>8. then Array.iter (fun child ->
          let tx=origin_x+.(child.gx+.child.gs*.0.5)*.extent
          and ty=origin_y+.(child.gy+.child.gs*.0.5)*.extent in
          let color=Color.with_alpha (Color.darken color 0.72)
            (int_of_float (float color.a*.Mark_field.smooth 8. 16. s)) in
          linef cx cy tx ty color) glyph.descendants;
        Array.iter (strata file base_color origin_x origin_y extent (opacity*.detail))
          glyph.descendants;
        if glyph.symbol<>None && s>8. then
          rectf (cx-.1.) (cy-.1.) 2. 2.
            (fade paper (opacity*.Mark_field.smooth 8. 16. s))
      end else begin
        let seed,kind,first=match glyph.symbol with
          |Some symbol -> hash symbol.name,symbol.kind,symbol.first_line
          |None -> hash file.path,0,0 in
        let density=Symbol_preview.density glyph.mass in
        if s<4. then begin
          let alpha=int_of_float (float color.Color.a *. (1.-.Mark_field.smooth 1. 4. s)) in
          rectf (x+.s*.0.5-.0.5) (y+.s*.0.5-.0.5) 1. 1. (Color.with_alpha color alpha)
        end;
        Mark_field.iter ~seed ~density ~x ~y ~size:s
          (fun _ cx cy dot opacity ->
            let height=if kind=12 then dot*.2. else dot in
            let color=Color.with_alpha color (int_of_float (float color.Color.a*.opacity)) in
            rectf (cx-.dot*.0.5) (cy-.height*.0.5) dot height color);
        if s>24. && kind=12 then begin
          let rows=min 12 (max 1 glyph.mass) in
          let alpha=int_of_float (float color.Color.a*.Mark_field.smooth 24. 40. s) in
          let color=Color.with_alpha (Color.darken color 0.3) alpha in
          for row=0 to rows-1 do
            let width=s*.float file.profile.((first+row) mod 32)/.120. in
            rectf x (y+.float row*.s/.float rows) (max 0.5 width) 0.75 color
          done
        end
      end
    end in
  let labels=ref 0 in
  let rec draw n depth opacity =
    let x,y = screen m f n.x n.y in
    let s = n.size *. world_size f *. m.zoom in
    if opacity<1./.255. || not (visible x y s) then ()
    else if s < 2. then begin
      rectf (x+.s*.0.5-.0.5) (y+.s*.0.5-.0.5) 1. 1. (fade (palette n.label) opacity)
    end else begin
      let ix=int_of_float x and iy=int_of_float y and side=max 1 (int_of_float s) in
      let c = fade (palette n.label) opacity in
      match n.file with
      |Some file ->
          let inset=s*.0.025 in
          (match file.glyph with
           |Some glyph ->
               let detail=Mark_field.smooth 2. 4. s in
               if detail<1. then rectf (x+.s*.0.5-.0.5) (y+.s*.0.5-.0.5)
                 1. 1. (fade c (1.-.detail));
               strata file (palette n.label) (x+.inset) (y+.inset)
                 (s-.2.*.inset) (opacity*.detail) glyph
           |None ->
               (* Non-OCaml files are unindexed, visibly hollow. *)
               rect (ix+1) (iy+1) (max 1 (side-2)) (max 1 (side-2))
                 ~stroke:(Color.darken c 0.65) ());
          if s>90. && m.show_cells then rect (ix+1) (iy+1) (side-3) (side-3)
            ~stroke:(Color.darken c 0.64) ();
          if s>180. && !labels<24 then begin
            incr labels;
            let label=Filename.basename file.path in
            let label=if String.length label>26 then String.sub label 0 23^"..." else label in
            rect (ix+6) (iy+6) (min (side-12) (String.length label*7+12)) 21 ~fill:ink ();
            text (ix+11) (iy+9) 11 paper label
          end
      |None ->
          let detail=Mark_field.smooth 2. 4. s in
          if detail<1. then rectf (x+.s*.0.5-.0.5) (y+.s*.0.5-.0.5)
            1. 1. (fade c (1.-.detail));
          if s>12. && m.show_cells then rect (ix+1) (iy+1) (side-2) (side-2)
            ~stroke:(if depth mod 2=0 then grid else Color.rgb 39 45 38) ();
          if not m.show_cells && s>10. then begin
            let cx=x+.s*.0.5 and cy=y+.s*.0.5 in
            Array.iter (fun child ->
              let tx,ty=screen m f (child.x+.child.size*.0.5) (child.y+.child.size*.0.5) in
              (* Orthogonal parent-child paths read as a recursively branching
                 network at every scale; they express containment, not calls. *)
              let color=if depth<2 then Color.rgb 40 48 44 else Color.rgb 63 71 63 in
              let color=Color.with_alpha color (int_of_float (255.*.Mark_field.smooth 10. 18. s)) in
              linef cx cy tx cy color;linef tx cy tx ty color) n.children
          end;
          Array.iter (fun child -> draw child (depth+1) (opacity*.detail)) n.children;
          if s>110. && m.show_cells then begin
            let len=min 15 (side/8) in
            line (ix+2) (iy+2) (ix+len) (iy+2) muted;
            line (ix+2) (iy+2) (ix+2) (iy+len) muted;
            rect (ix+side-5) (iy+side-5) 2 2 ~fill:orange ()
          end
    end in
  let art=match m.art_cache with
    |Some (key,art) when not !rebuild_art && key=art_key m f -> art
    |_->
        draw m.tree 0 1.;
        flush ();
        let art=Scene.group (List.rev !commands) in
        if !reference_draws then wrap art else art in
  commands:=[];
  drawing_art:=false;
  Packed_ink.set_clip packed None;
  (* Overlay publications must not reuse an identity retained by the artwork. *)
  Packed_ink.set_ids packed m.overlay_ids;
  let inspected=if not !hover_bench && (!smoke || !tour || !export<>"") then None else
    Option.bind m.hover (fun n -> Option.map (fun file ->
      let x,y=screen m f n.x n.y in
      let size=n.size*.world_size f*.m.zoom in
      let inset=size*.0.025 in
      let mx,my=f.mouse in
      let glyph=Option.bind file.glyph (fun glyph -> pick_glyph glyph
        ((mx-.x-.inset)/.(size-.2.*.inset))
        ((my-.y-.inset)/.(size-.2.*.inset))) in
      n,file,glyph) n.file) in
  (match inspected with
   |Some (n,_,glyph) ->
       let x,y=screen m f n.x n.y in
       let size=n.size*.world_size f*.m.zoom in
       let x,y,size=match glyph with None->x,y,size|Some glyph->
         x+.size*.0.025+.glyph.gx*.size*.0.95,
         y+.size*.0.025+.glyph.gy*.size*.0.95,glyph.gs*.size*.0.95 in
       let side=max 1 (int_of_float size) in
       emit (wrap (Scene.rect ~at:(int_of_float x,int_of_float y)
         ~w:side ~h:side ~stroke:orange ()))
   |_->());
  if m.show_ui then begin
    text 32 24 13 paper "PRISMEL     /     COMPUTATIONAL CARTOGRAPHY";
    text (f.width-205) 26 10 muted "PLATE 001     /     SOURCE";
    line 32 56 (f.width-32) 56 grid;
    let ox,oy=center f and extent=world_size f*.m.zoom in
    for i=0 to 16 do
      let wx=float i/.16. in
      let x=int_of_float (ox+.(wx-.m.cx)*.extent) in
      if x>32 && x<art_right then begin
        line x 64 x (if i mod 4=0 then 72 else 68) muted;
        if i mod 4=0 then text (x+4) 62 8 muted (Printf.sprintf "%02X" i)
      end
    done;
    ignore oy;
    if sidebar f>0 then begin
      let x=f.width-282 in
      line (x-22) 80 (x-22) (art_bottom f) grid;
      text x 84 10 orange "RECURSIVE FIELD / 01";
      text (x-3) 121 44 paper "SOURCE";
      text (x-3) 165 44 paper "STRATA";
      text x 239 12 muted "A repository, folded into space.";
      text x 260 12 muted "Files / modules / types / values.";
      text x 281 12 muted "Real symbols. Recursive space.";
      line x 323 (f.width-34) 323 grid;
      text x 345 35 paper (Printf.sprintf "%d" m.files);
      text x 392 10 muted "SOURCE FILES";
      text x 435 35 paper (Printf.sprintf "%d" m.index.symbol_count);
      text x 482 10 muted "LSP SYMBOLS / NESTED SCOPE";
      line x 518 (f.width-34) 518 grid;
      List.iteri (fun i (label,color) ->
        let y=541+i*20 in
        if y+12<art_bottom f-24 then begin
          rect x (y+3) 6 6 ~fill:color ();
          text (x+18) y 10 muted label
        end)
        ["CORE / BINDINGS",palette "lib/metal";
         "LIBRARIES",palette "lib/prismel";
         "TESTS",palette "test/";
         "SKETCHES",palette "sketches/";
         "EXAMPLES",palette "examples/"];
      if f.height>780 then
        text x (art_bottom f-16) 10 orange (Printf.sprintf "MAGNIFICATION     %05.2f X" m.zoom)
    end;
    let top=footer_top f and split=max 240 (f.width*43/100) in
    rect 24 top (f.width-48) (f.height-top) ~fill:ink ();
    line 32 top (f.width-32) top grid;
    let panel_text ~left ~right y size color value =
      emit (Scene.clip ~at:(left,top+1) ~w:(max 1 (right-left)) ~h:(max 1 (f.height-top-2))
        [Scene.text ~at:(left,y) ~size ~color
          (Symbol_preview.shorten (max 10 ((right-left)*2/max 1 size)) value)]) in
    let left y size color text=panel_text ~left:32 ~right:(split-20) y size color text
    and right y size color text=panel_text ~left:(split+20) ~right:(f.width-32) y size color text in
    line split (top+15) split (f.height-28) grid;
    (match inspected with
     |Some (_,file,glyph) ->
         let symbol=Option.bind glyph (fun glyph->glyph.symbol) in
         let first,last,name,kind,weight=match symbol with
           |Some symbol->symbol.first_line,symbol.last_line,symbol.name,
               Symbol_preview.kind symbol.kind,
               (if symbol.children<>[] then 0 else
                 Symbol_preview.density (symbol.last_line-symbol.first_line+1))
           |None->0,max 0 (file.lines-1),Filename.basename file.path,
               (if file.symbols=None then "UNINDEXED FILE" else "FILE"),0 in
         left (top+14) 11 orange file.path;
         left (top+36) 16 paper (kind^"  /  "^name);
         left (top+64) 11 muted (Printf.sprintf "LINES %d-%d  /  %d LINES%s"
           (first+1) (last+1) (last-first+1)
           (if weight=0 then (match symbol with Some _->"  /  NESTED SCOPE"
              |None->Printf.sprintf "  /  %d BYTES" file.bytes)
            else Printf.sprintf "  /  DOT WEIGHT %d/100" weight));
         right (top+14) 10 orange "SOURCE PREVIEW";
         (match m.preview_source with
          |Some source when source.path=file.path ->
              (match source.error with
               |Some message->right (top+38) 12 muted message
               |None->
                   let rows=Symbol_preview.excerpt source ~first ~last in
                   if rows=[||] then right (top+38) 12 muted "No source lines at this range"
                   else Array.iteri (fun i (number,line)->
                     right (top+36+i*20) 12 paper (Printf.sprintf "%5d   %s" number line)) rows)
          |_->right (top+38) 12 muted "Source unavailable")
     |None ->
         left (top+14) 10 orange "SYMBOL INSPECTOR";
         left (top+36) 16 paper "Hover a mark to inspect its symbol";
         left (top+64) 11 muted (Printf.sprintf "%d FILES  /  %d SYMBOLS  /  %d LINES"
           m.files m.index.symbol_count m.total_lines);
         right (top+14) 10 orange "READING THE FIELD";
         right (top+36) 12 paper "Leaf dots = source span; branches = nested scopes.";
         right (top+56) 12 muted "Zoom reveals detail. Density is not a complexity score.";
         right (top+76) 11 muted "SCROLL zoom   DRAG pan   CLICK dive   R reset   T cells   H hide");
    left (top+94) 10 muted "LEAF DENSITY FOLLOWS SOURCE SPAN"
  end;
  flush ();
  art,Scene.clear ink :: art :: List.rev !commands

let verify_tree () =
  let fixture=Array.init 1024 (fun i ->
    {path=Printf.sprintf "fixture/%04d.ml" i;lines=1+(i*i mod 4000);
     bytes=i*17;profile=Array.init 32 (fun j -> (i+j) mod 121);symbols=None;glyph=None}) in
  let check files =
    let tree=build files and seen=Hashtbl.create (Array.length files) in
    let minimum=ref max_int and maximum=ref 0 in
    let rec visit depth n =
      match n.file with
      |Some file ->
          if Hashtbl.mem seen file.path then failwith "duplicate file";
          Hashtbl.add seen file.path ();
          minimum:=min !minimum depth;maximum:=max !maximum depth;
          (match pick tree (n.x+.n.size*.0.5) (n.y+.n.size*.0.5) with
           |Some hit when hit.file=Some file -> () |_->failwith "pick mismatch")
      |None ->
          if Array.fold_left (fun total c -> total+c.count) 0 n.children<>n.count then
            failwith "branch cardinality";
          Array.iter (fun c ->
            if c.size<>n.size*.0.5 || c.x<n.x || c.y<n.y ||
               c.x+.c.size>n.x+.n.size || c.y+.c.size>n.y+.n.size then
              failwith "child outside parent";
            visit (depth+1) c) n.children in
    visit 0 tree;
    if Hashtbl.length seen<>Array.length files || tree<>build files then
      failwith "coverage/determinism";
    !minimum,!maximum in
  for count=1 to 9 do ignore (check (Array.sub fixture 0 count)) done;
  let lo,hi=check fixture in
  if hi-lo<3 then failwith "adaptive tree collapsed to uniform depth";
  let nested=List.init 1024 (fun i ->
    {Source_index.name=Printf.sprintf "symbol_%d" i;kind=12;first_line=i;last_line=i+3;
     children=if i mod 31=0 then [{Source_index.name="nested";kind=13;
       first_line=i+1;last_line=i+1;children=[]}] else []}) in
  let symbols=symbol_layout nested in
  let found=ref 0 in
  let rec inspect glyph =
    Option.iter (fun symbol ->
      incr found;
      if glyph.descendants=[||] &&
         pick_symbol symbols (glyph.gx+.glyph.gs*.0.5) (glyph.gy+.glyph.gs*.0.5)<>Some symbol then
        failwith "nested symbol picking") glyph.symbol;
    Array.iter inspect glyph.descendants in
  inspect symbols;
  if !found<>Source_index.count nested then failwith "symbol layout lost/duplicated scopes";
  Printf.printf "source strata: 1024 files exactly once, deterministic, leaf depths %d..%d\n%!" lo hi

let () =
  if !verify then verify_tree () else
  let files=scan !root_dir in
  if Array.length files=0 then failwith "No source files under --root";
  let symbols,index=Source_index.load ~server:!server ~root:!root_dir
    (Array.map (fun file -> file.path) files) in
  let files=Array.mapi (fun i file -> {file with symbols=symbols.(i);
    glyph=Option.map symbol_layout symbols.(i)}) files in
  if !index_only then () else
  let init=init files index in
  let prepare m (f:Frame.t) =
    let f=if !hover_bench then {f with Frame.mouse=
      (float(f.width/2+(f.count*17 mod 320)-160),
       float(f.height/2+(f.count*11 mod 240)-120))} else f in
    let m=update m f in
    let mouse=if !hover_bench || not (!smoke || !tour || !export<>"")
      then f.Frame.mouse else (0.,0.) in
    let key=(f.width,f.height,m.cx,m.cy,m.zoom,m.show_ui,m.show_cells,mouse) in
    match m.scene_cache with
    |Some (previous,_) when previous=key -> m
    |_->
        let art,scene=view m f in
        let reused=not !rebuild_art && (match m.art_cache with
          Some (key,_) -> key=art_key m f |None -> false) in
        {m with scene_cache=Some (key,scene);art_cache=Some (art_key m f,art);
          art_builds=m.art_builds+(if reused then 0 else 1)} in
  let prepared_view m f = match m.scene_cache with
    |Some (_,scene) -> scene |None -> snd (view m f) in
  let config={Sketch.default_config with width=1440;height=1000;
    title="Prismel / Source Strata";domains=Some !domains;
    clock=(if !smoke || !tour || !benchmark || !frames>0 || !export<>""
      then Sketch.Fixed (1./.60.) else Sketch.Realtime)} in
  let native_frames=if !frames>0 then Some !frames
    else if !smoke || !benchmark then Some 120 else None in
  let started=Unix.gettimeofday () and allocated=Gc.allocated_bytes ()
  and gc=Gc.quick_stat () in
  if !export <> "" then
    ignore (Sketch.export_state ~config ~directory:!export ~prefix:"source-atlas"
      ~frames:(max 1 !frames) ~init ~update:prepare ~view:prepared_view ())
  else begin
    let final=Sketch.run_state ~config ?max_frames:native_frames ~init
      ~update:prepare ~view:prepared_view () in
    if !benchmark then begin
      let after=Gc.quick_stat () in
      Printf.printf "native run (includes window startup/teardown): frames=%d domains=%d art_builds=%d wall=%.3fs allocated=%.0fB promoted=%.0fB major=%.0fB heap_peak=%dB\n%!"
        (Option.value native_frames ~default:0) !domains final.art_builds (Unix.gettimeofday ()-.started)
        (Gc.allocated_bytes ()-.allocated)
        ((after.promoted_words-.gc.promoted_words)*.8.)
        ((after.major_words-.gc.major_words)*.8.) (after.top_heap_words*8)
    end
  end
