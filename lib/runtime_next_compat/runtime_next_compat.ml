module O=Runtime_next_orchestrator
type target=Native
type t={raw:O.t;mutable stopped:bool}
type facts=O.facts
type pacing=O.pacing
let string_result=function Ok value->Ok value|Error error->Error(Ogpu.Error.to_string error)
let target_of_string value=match O.target_of_string value with Ok O.Native->Ok Native|Error _ as error->error
let selected_target()=match O.selected()with Ok O.Native->Ok Native|Error _ as error->error
let is_headless()=false let is_web()=false let is_displayless()=false
let start~width~height~title:_~resizable:_=match O.selected()with Error message->Error message|Ok target->
  Result.map(fun raw->{raw;stopped=false})(string_result(O.create{target;logical_width=width;logical_height=height;drawable_width=width;drawable_height=height}))
let stop value=if not value.stopped then(ignore(O.destroy value.raw);value.stopped<-true)
let target _=Native
let facts value=string_result(O.facts value.raw) let pacing value=string_result(O.pacing value.raw)
let render value draws=string_result(O.render value.raw draws) let capture value~bytes_per_row=string_result(O.capture value.raw~bytes_per_row)
let resize value~logical_width~logical_height~drawable_width~drawable_height=string_result(O.resize value.raw~logical_width~logical_height~drawable_width~drawable_height)
let set_title value title=string_result(O.set_title value.raw title) let set_position value~x~y=string_result(O.set_position value.raw~x~y)
let center value=string_result(O.center value.raw) let set_bordered value x=string_result(O.set_bordered value.raw x)
let set_resizable value x=string_result(O.set_resizable value.raw x) let set_always_on_top value x=string_result(O.set_always_on_top value.raw x)
let set_fullscreen value x=string_result(O.set_fullscreen value.raw x) let show value=string_result(O.show value.raw)
let hide value=string_result(O.hide value.raw) let minimize value=string_result(O.minimize value.raw)
let maximize value=string_result(O.maximize value.raw) let restore value=string_result(O.restore value.raw)
let omitted_raw_api=["present";"Private.select_target"]
type coverage=Mapped|Adapted of string|Raw_omission of string
let api_coverage=List.map(fun name->name,Mapped)["start";"stop";"target";"target_of_string";"selected_target";"facts";"pacing";"render";"capture";"resize";"set_title";"set_position";"center";"set_bordered";"set_resizable";"set_always_on_top";"set_fullscreen";"show";"hide";"minimize";"maximize";"restore"]
let api_type_coverage=["target",Mapped;"t",Mapped]
