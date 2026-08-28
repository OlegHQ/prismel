open Tsdl
open Tsdl_ttf
type target=Target.t=Native|Headless
type web_mouse_button=Left|Middle|Right|X1|X2
type web_event=Pointer_moved of int*int|Pointer_pressed of web_mouse_button*int*int|Pointer_released of web_mouse_button*int*int|Pointer_cancelled of web_mouse_button|Wheel of int*int|Key_pressed of string|Key_released of string|Text_input of string|Text_editing of{text:string;start:int;length:int}|Resized of int*int|Focus_lost|File_dropped of string
type text_input_region={x:int;y:int;width:int;height:int;focused:bool}
type web_audio_command=Audio_master_volume of float|Audio_stop_all|Audio_sample_play of{asset:string;channel:int;loops:int;volume:float}|Audio_sample_volume of{asset:string;volume:float}|Audio_sample_stop of int|Audio_sample_pause of int|Audio_sample_resume of int|Audio_music_play of{asset:string;loops:int;fade_ms:int}|Audio_music_volume of float|Audio_music_pause|Audio_music_resume|Audio_music_stop of int|Audio_asset_remove of string
type t={target:target;sdl_environment:(string*string option)list;image_initialized:bool;ttf_initialized:bool;mutable stopped:bool}
let selected_target()=Target.get() let target_of_string=Target.of_string
let is_headless=Target.is_headless let is_web()=false let is_displayless=Target.is_displayless
let target value=value.target
let next_web_deadline~previous~now~frame_interval~traffic_interval=max(if previous<=0.||now-.previous>=frame_interval then now+.frame_interval else previous+.frame_interval)(now+.traffic_interval)
let fitted_web_drawable_size~max_pixels~logical_width~logical_height=if logical_width<=0||logical_height<=0 then invalid_arg"Runtime web dimensions must be positive";let pixels=Int64.mul(Int64.of_int logical_width)(Int64.of_int logical_height)in if pixels<=Int64.of_int max_pixels then logical_width,logical_height else let scale=sqrt(float_of_int max_pixels/.Int64.to_float pixels)in max 1(int_of_float(floor(float_of_int logical_width*.scale))),max 1(int_of_float(floor(float_of_int logical_height*.scale)))
let idle_frame_interval base duplicate_streak=base*.float_of_int(1 lsl min 2(max 0 duplicate_streak/2))
let sdl_environment_names=["SDL_VIDEODRIVER";"SDL_RENDER_DRIVER";"SDL_AUDIODRIVER"]
external unset_environment:string->unit="prismel_runtime_unsetenv"
let capture_sdl_environment target=if target=Native then[]else List.map(fun name->name,Sys.getenv_opt name)sdl_environment_names
let restore_environment values=List.iter(fun(name,value)->match value with Some x->Unix.putenv name x|None->unset_environment name)values
let start~width:_~height:_~title:_~resizable:_=match Target.selected()with Error message->Error("Prismel runtime: "^message)|Ok target->let sdl_environment=capture_sdl_environment target in Target.configure_sdl_environment target;ignore(Sdl.set_hint Sdl.Hint.render_scale_quality"1");if target=Native then ignore(Sdl.set_hint Sdl.Hint.render_driver"");match Sdl.init Sdl.Init.(video+audio+events)with Error(`Msg message)->restore_environment sdl_environment;Error("SDL initialization failed: "^message)|Ok()->let flags=Tsdl_image.Image.Init.(jpg+png)in let image_initialized=Tsdl_image.Image.Init.test(Tsdl_image.Image.init flags)flags in let ttf_initialized=match Ttf.init()with Ok()->true|Error(`Msg message)->Printf.eprintf"Prismel runtime warning: TTF disabled: %s\n%!"message;false in Ok{target;sdl_environment;image_initialized;ttf_initialized;stopped=false}
let stop value=if not value.stopped then(value.stopped<-true;if value.ttf_initialized then Ttf.quit();if value.image_initialized then Tsdl_image.Image.quit();Sdl.quit();restore_environment value.sdl_environment)
let web_url _=None let web_client_count _=0 let web_drawable_size _~logical_width~logical_height=logical_width,logical_height
let drain_web_events _=[] let register_web_file _?content_type:_ _=None let register_web_bytes _?content_type:_ _=None
let remove_web_asset _ _=() let send_web_audio _ _=() let download_web_frame _~filename:_=Error"The web target has been removed" let set_web_text_input_regions _ _=()
let present _ renderer~logical_width:_~logical_height:_=Sdl.render_present renderer;Ok()
module Private=struct let select_target=Target.select_with let next_web_deadline=next_web_deadline let fitted_web_drawable_size=fitted_web_drawable_size let idle_frame_interval=idle_frame_interval end
