let attr : Flow.Op.t = {
  name = "sop/attr"; ctx = Flow.Context.sop;
  signature = {pos = ["geometry", Flow.Ty.geometry; "attribute", Flow.Ty.Text];
    opt = []; rest = None; kw = []};
  out = (fun _ -> Flow.Ty.Array Flow.Ty.Vec3); any_num = false; choices = [];
  shape = Flow.Op.Struct {splice = false}; live = false; category = "Attributes";
  arithmetic = None;
  check = (fun args -> match List.assoc "attribute" args with
    | Flow.Value.Text name when String.trim name <> "" -> ()
    | _ -> Flow.Value.fail "E_ATTR_NAME" "A point attribute needs a nonblank name.");
  body = (fun ~live:_ ~node:_ args -> Flow.Value.Struct ("sop/attr", Flow.Ty.Array Flow.Ty.Vec3, args));
}
let with_attr : Flow.Op.t = {
  attr with name = "sop/with_attr";
  signature = {attr.signature with pos = attr.signature.pos @ ["values", Flow.Ty.Array Flow.Ty.Vec3]};
  out = (fun _ -> Flow.Ty.geometry); shape = Flow.Op.Scalar;
  body = (fun ~live:_ ~node args -> node "sop/with_attr" args);
}
let all = Flow_ir.Operators.all @ [attr; with_attr]
