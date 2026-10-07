let noise = Rays_math.Noise.create 0
let noise3 : Flow.Op.t = {
  name = "noise3"; ctx = Flow.Context.value;
  signature = {pos = ["position", Flow.Ty.Vec3]; opt = []; rest = None; kw = []};
  out = (fun _ -> Flow.Ty.Float); any_num = false; choices = [];
  shape = Flow.Op.Scalar; live = false; category = "Noise"; arithmetic = None;
  check = (fun _ -> ());
  body = (fun ~live:_ ~node:_ args -> match List.assoc "position" args with
    | Flow.Value.Vec3 (x, y, z) ->
        ignore (Flow.Value.fin "noise3 position" x);
        ignore (Flow.Value.fin "noise3 position" y);
        ignore (Flow.Value.fin "noise3 position" z);
        Flow.Value.Float (Flow.Value.fin "noise3"
          (Rays_math.Noise.sample3 noise ~x ~y ~z))
    | _ -> Flow.Value.fail "E_TYPE" "noise3 takes a vec3 position.");
}
let all = [noise3]
