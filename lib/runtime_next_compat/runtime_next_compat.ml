module O = Runtime_next_orchestrator
type target = Native | Headless | Web
type t = { raw:O.t; mutable stopped:bool }
type facts = O.facts
type pacing = O.pacing
type web_mouse_button = O.mouse_button = Left | Middle | Right | X1 | X2
type web_event = O.web_event = Pointer_moved of int*int | Pointer_pressed of web_mouse_button*int*int
  | Pointer_released of web_mouse_button*int*int | Pointer_cancelled of web_mouse_button
  | Wheel of int*int | Key_pressed of string | Key_released of string
  | Text_input of string | Text_editing of {text:string;start:int;length:int}
  | Resized of int*int | Focus_lost | File_uploaded of {name:string;contents:bytes}
type text_input_region = O.text_input_region = {x:int;y:int;width:int;height:int;focused:bool}
type web_audio_command = O.audio_command = Audio_master_volume of float | Audio_stop_all
  | Audio_sample_play of {asset:string;channel:int;loops:int;volume:float}
  | Audio_sample_volume of {asset:string;volume:float} | Audio_sample_stop of int
  | Audio_sample_pause of int | Audio_sample_resume of int
  | Audio_music_play of {asset:string;loops:int;fade_ms:int} | Audio_music_volume of float
  | Audio_music_pause | Audio_music_resume | Audio_music_stop of int | Audio_asset_remove of string

let string_result = function Ok value -> Ok value | Error error -> Error (Ogpu.Error.to_string error)
let of_target = function O.Native -> Native | O.Headless -> Headless | O.Web -> Web
let target_of_string value = match O.target_of_string value with Ok value -> Ok(of_target value)|Error _ as e->e
let selected_target () = match O.selected () with Ok value->Ok(of_target value)|Error _ as e->e
let selected_is predicate = match O.selected () with Ok value->predicate value|Error _->false
let is_headless () = selected_is (fun value->value=O.Headless)
let is_web () = selected_is (fun value->value=O.Web)
let is_displayless () = selected_is (fun value->value<>O.Native)
let start ~width ~height ~title ~resizable =
  let selected = match O.selected () with Ok value->Ok value|Error message->Error message in
  match selected with Error _ as failure->failure | Ok target ->
    let web_configuration = if target=O.Web then Some { O.default_web_configuration with title;resizable } else None in
    match string_result (O.create {target;logical_width=width;logical_height=height;
      drawable_width=width;drawable_height=height;web_configuration}) with
    | Error _ as failure->failure | Ok raw->Ok{raw;stopped=false}
let stop value = if not value.stopped then (ignore(O.destroy value.raw);value.stopped<-true)
let target value = of_target(O.target value.raw)
let facts value=string_result(O.facts value.raw)
let pacing value=string_result(O.pacing value.raw)
let render value draws=string_result(O.render value.raw draws)
let capture value ~bytes_per_row=string_result(O.capture value.raw~bytes_per_row)
let resize value ~logical_width ~logical_height ~drawable_width ~drawable_height=
  string_result(O.resize value.raw~logical_width~logical_height~drawable_width~drawable_height)
let set_title value title=string_result(O.set_title value.raw title)
let set_position value ~x ~y=string_result(O.set_position value.raw~x~y)
let center value=string_result(O.center value.raw)
let set_bordered value flag=string_result(O.set_bordered value.raw flag)
let set_resizable value flag=string_result(O.set_resizable value.raw flag)
let set_always_on_top value flag=string_result(O.set_always_on_top value.raw flag)
let set_fullscreen value flag=string_result(O.set_fullscreen value.raw flag)
let show value=string_result(O.show value.raw)
let hide value=string_result(O.hide value.raw)
let minimize value=string_result(O.minimize value.raw)
let maximize value=string_result(O.maximize value.raw)
let restore value=string_result(O.restore value.raw)
let option = function Ok value->Some value|Error _->None
let web_url value=option(O.web_url value.raw)
let web_client_count value=match O.web_client_count value.raw with Ok value->value|Error _->0
let web_drawable_size value ~logical_width ~logical_height = match O.facts value.raw with
  | Ok facts when facts.logical_width>0&&facts.logical_height>0 ->
      max 1 (logical_width*facts.drawable_width/facts.logical_width),
      max 1 (logical_height*facts.drawable_height/facts.logical_height)
  | _->logical_width,logical_height
let drain_web_events value=match O.drain_web_events value.raw with Ok value->value|Error _->[]
let register_web_bytes value ?content_type bytes=option(O.register_web_bytes value.raw?content_type bytes)
let register_web_file value ?content_type path=try let channel=open_in_bin path in
  Fun.protect~finally:(fun()->close_in_noerr channel)(fun()->register_web_bytes value?content_type
    (Bytes.of_string(really_input_string channel(in_channel_length channel))))with Sys_error _->None
let remove_web_asset value asset=ignore(O.remove_web_asset value.raw asset)
let send_web_audio value command=ignore(O.send_web_audio value.raw command)
let download_web_frame value ~filename=string_result(O.download_web_frame value.raw~filename)
let set_web_text_input_regions value regions=ignore(O.set_text_input_regions value.raw regions)
let omitted_raw_api=["present";"Private.select_target";"Private.next_web_deadline";
  "Private.fitted_web_drawable_size";"Private.idle_frame_interval"]
type coverage = Mapped | Adapted of string | Raw_omission of string
let api_coverage = List.map(fun name->name,Mapped)[
  "start";"stop";"target";"target_of_string";"is_headless";"is_web";
  "is_displayless";"web_url";"web_client_count";"web_drawable_size";
  "register_web_file";"register_web_bytes";"remove_web_asset";"send_web_audio";
  "download_web_frame";"set_web_text_input_regions"] @ [
  "selected_target",Adapted"returns a result instead of hiding invalid configuration";
  "drain_web_events",Adapted"file drops carry copied bytes as File_uploaded";
  "present",Raw_omission"requires a raw Tsdl renderer";
  "Private.select_target",Raw_omission"private environment injection helper";
  "Private.next_web_deadline",Raw_omission"private legacy pacing algorithm";
  "Private.fitted_web_drawable_size",Raw_omission"private legacy scaling helper";
  "Private.idle_frame_interval",Raw_omission"private legacy pacing helper"]
let api_type_coverage=[
  "target",Mapped;"t",Mapped;
  "web_mouse_button",Adapted"target-neutral constructor identity";
  "web_event",Adapted"File_dropped path becomes copied File_uploaded payload";
  "text_input_region",Mapped;
  "web_audio_command",Adapted"target-neutral constructor identity"]
