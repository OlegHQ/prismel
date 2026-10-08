type parameters = {width : int; height : int; frequency : float; seed : int}
let defaults = {width=256; height=256; frequency=0.02; seed=0}
let schema = Parameter.schema ~name:"image/noise" ~default:defaults [
  Parameter.field ~name:"width" ~kind:(Parameter.integer ~hard_min:1 ~min:1 ~max:2048 ())
    ~default:defaults.width ~get:(fun p -> p.width) ~set:(fun width p -> {p with width}) ();
  Parameter.field ~name:"height" ~kind:(Parameter.integer ~hard_min:1 ~min:1 ~max:2048 ())
    ~default:defaults.height ~get:(fun p -> p.height) ~set:(fun height p -> {p with height}) ();
  Parameter.field ~name:"frequency" ~kind:(Parameter.floating ~hard_min:0. ~min:0. ~max:1. ())
    ~default:defaults.frequency ~get:(fun p -> p.frequency) ~set:(fun frequency p -> {p with frequency}) ();
  Parameter.field ~name:"seed" ~kind:(Parameter.integer ~min:0 ~max:9999 ())
    ~default:defaults.seed ~get:(fun p -> p.seed) ~set:(fun seed p -> {p with seed}) ()]
exception Cancelled
let rec build ~label ~inputs:_ parameters =
  Node.Private.make ~label ~operation:"image/noise" ~version:1
    ~parameters:(Parameter.key schema parameters) ~cook_mode:Node.Generator
    ~dependencies:Context.Dependencies.static ~inputs:[||]
    (fun ~node_id:_ context _ ->
      let cancel () = Error (Diagnostic.error ~code:"E_CANCELLED" "Image cook was cancelled.") in
      let {width; height; frequency; seed} = parameters in
      if Context.cancelled context then cancel ()
      else if width <= 0 || height <= 0 || width > Sys.max_floatarray_length / 4 / height then
        Error (Diagnostic.error ~code:"E_IMAGE" "Image dimensions exceed native storage bounds.")
      else try
        let rgba = Array.make (width * height * 4) 0. in
        let noise = Rays_math.Noise.create seed in
        Rays_math.Parallel.for_ ~chunk_size:(Context.grain context) ~start:0 ~finish:(width * height-1)
          (fun pixel ->
            if pixel mod width = 0 && Context.cancelled context then raise_notrace Cancelled;
            let value = Rays_math.Noise.sample3 noise
              ~x:(float (pixel mod width) *. frequency) ~y:(float (pixel / width) *. frequency) ~z:0. in
            let offset = pixel * 4 in
            rgba.(offset) <- value; rgba.(offset+1) <- value; rgba.(offset+2) <- value; rgba.(offset+3) <- 1.);
        if Context.cancelled context then cancel () else
        Result.map (fun image -> Node.Private.{payload=Payload.Image image; diagnostics=[]; instances=None})
          (Image.Private.of_owned_rgba ~width ~height rgba)
      with Cancelled -> cancel ())
  |> Node.parameterize ~schema ~values:parameters ~rebuild:build
let noise ?(width=defaults.width) ?(height=defaults.height) ?(frequency=defaults.frequency)
    ?(seed=defaults.seed) () = build ~label:"Image Noise" ~inputs:[] {width; height; frequency; seed}
let noise_factory = Edit_graph.factory ~operation:"image/noise" ~key:"noise"
  ~label:"Noise" ~category:["Image"] ~arity:0
  ~fields:(Parameter.view schema defaults) (fun _ -> noise ())
