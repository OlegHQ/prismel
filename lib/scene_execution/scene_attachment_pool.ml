type kind = Color | Depth | Stencil
type entry = { kind:kind; samples:int; texture:Ogpu.Backend.texture }
type t = {
  device:Ogpu.Backend.device;
  sample_counts:int list;
  mutable configuration:Ogpu.Surface.configuration;
  mutable entries:entry list;
  mutable dead:bool;
}

let error message = Error (Ogpu.Error.make "Scene_attachment_pool" Ogpu.Error.Invalid_argument message)

let create ~device ~configuration ~sample_counts =
  if sample_counts=[] || List.exists ((>=) 0) sample_counts ||
     List.length (List.sort_uniq Int.compare sample_counts) <> List.length sample_counts
  then invalid_arg "Scene_attachment_pool.create: sample counts must be unique and positive";
  { device; sample_counts; configuration; entries=[]; dead=false }

let descriptor configuration kind samples : Ogpu.Types.texture_descriptor =
  let prefix = match kind with Color -> "color" | Depth -> "depth" | Stencil -> "stencil" in
  { label=Some (Printf.sprintf "scene-execution-%s-%d" prefix samples);
    width=configuration.Ogpu.Surface.physical_width;
    height=configuration.physical_height;
    depth=1; mip_levels=1; sample_count=samples;
    usage=[Ogpu.Types.Render_attachment] }

let allocate value configuration kind samples =
  let descriptor = descriptor configuration kind samples in
  match kind with
  | Color -> Ogpu.Backend.create_texture value.device descriptor
  | Depth -> Ogpu.Backend.create_depth_texture value.device descriptor
  | Stencil -> Ogpu.Backend.create_stencil_texture value.device descriptor

let acquire value kind ~samples =
  if value.dead then error "pool is destroyed"
  else if not (List.mem samples value.sample_counts) then error "unsupported sample count"
  else match List.find_opt (fun entry -> entry.kind=kind && entry.samples=samples) value.entries with
    | Some entry -> Ok entry.texture
    | None -> Result.map (fun texture ->
        value.entries <- {kind;samples;texture} :: value.entries; texture)
        (allocate value value.configuration kind samples)

let destroy_entries entries =
  List.iter (fun entry -> ignore (Ogpu.Backend.destroy_texture entry.texture)) entries

let resize value configuration =
  if value.dead then error "pool is destroyed"
  else
    let rec build made = function
      | [] -> Ok (List.rev made)
      | entry::rest ->
          match allocate value configuration entry.kind entry.samples with
          | Ok texture -> build ({entry with texture}::made) rest
          | Error failure -> destroy_entries made; Error failure
    in
    match build [] value.entries with
    | Error _ as failure -> failure
    | Ok replacements ->
        let old = value.entries in
        value.entries <- replacements;
        value.configuration <- configuration;
        destroy_entries old;
        Ok ()

let destroy value =
  if not value.dead then begin
    value.dead <- true;
    destroy_entries value.entries;
    value.entries <- []
  end

let allocated value =
  List.rev_map (fun entry -> entry.kind,entry.samples,Ogpu.Backend.texture_id entry.texture) value.entries
