type handoff=Scalar_snapshot|Sample_positions|Nullable_rasterization_graph|Layer_identity|Drawable_parent
type item={id:string;raw_symbols:string list;native_symbols:string list;safe_operation:string;handoff:handoff}
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let native raw="caml_prismel_metal_"^raw
let render_item id=
 let handoff,safe_operation=if contains id "SamplePositions"||contains id "samplePositions" then Sample_positions,"Metal.Render_pass_descriptor.sample_positions/set_sample_positions" else if contains id "rasterizationRateMap" then Nullable_rasterization_graph,"Metal.Render_pass_descriptor.rasterization_rate_map" else Scalar_snapshot,"Metal.Render_pass_descriptor.advanced scalar get/set" in
 let raw_symbols=["render_pass_advanced_get";"render_pass_advanced_set"]in{id;raw_symbols;native_symbols=List.map native raw_symbols;safe_operation;handoff}
let layer_item id=
 if contains id "CAMetalDrawable" then{id;raw_symbols=["drawable_native_layer"];native_symbols=[native"drawable_native_layer"];safe_operation="Metal.Drawable.layer";handoff=Drawable_parent}
 else if contains id "setWantsExtended" then{id;raw_symbols=["layer_set_extended_range"];native_symbols=[native"layer_set_extended_range"];safe_operation="Metal.Layer.set_extended_dynamic_range";handoff=Layer_identity}
 else{id;raw_symbols=["layer_native_snapshot"];native_symbols=[native"layer_native_snapshot"];safe_operation="Metal.Layer.native_snapshot";handoff=Layer_identity}
let property name=["method:-[MTLRenderPassDescriptor "^name^"]";"method:-[MTLRenderPassDescriptor set"^String.capitalize_ascii name^":]";"property:MTLRenderPassDescriptor:"^name]
let render_pass_ids=List.sort_uniq String.compare(List.concat_map property["imageblockSampleLength";"threadgroupMemoryLength";"tileWidth";"tileHeight";"visibilityResultType";"supportColorAttachmentMapping";"rasterizationRateMap"]@["method:-[MTLRenderPassDescriptor setSamplePositions:count:]";"method:-[MTLRenderPassDescriptor getSamplePositions:count:]"])
let layer_drawable_ids=List.sort_uniq String.compare(["device";"drawableSize";"pixelFormat";"framebufferOnly";"maximumDrawableCount";"allowsNextDrawableTimeout";"displaySyncEnabled";"presentsWithTransaction"]|>List.map(fun n->"method:-[CAMetalLayer "^n^"]")|>fun xs->xs@["method:-[CAMetalLayer wantsExtendedDynamicRangeContent]";"method:-[CAMetalLayer setWantsExtendedDynamicRangeContent:]";"property:CAMetalLayer:wantsExtendedDynamicRangeContent";"method:-[CAMetalDrawable layer]";"property:CAMetalDrawable:layer"])
let items=List.map render_item render_pass_ids@List.map layer_item layer_drawable_ids
let callable_ids=List.map(fun x->x.id)items|>List.sort_uniq String.compare
let blocked_ids=Binding_presentation_public_audit.missing_public|>List.filter(fun id->not(List.mem id callable_ids))
let validate()=if List.length render_pass_ids<>23||List.length layer_drawable_ids<>13||List.length callable_ids<>36||List.length blocked_ids<>46||List.exists(fun x->x.raw_symbols=[]||x.native_symbols=[]||x.safe_operation="")items then failwith"Presentation callable36 reachability drift"
let ()=validate()
