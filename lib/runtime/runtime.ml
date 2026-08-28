open Tsdl
open Tsdl_ttf
type target=Target.t=Native|Headless
type t={target:target;sdl_environment:(string*string option)list;image_initialized:bool;ttf_initialized:bool;mutable stopped:bool}
let selected_target()=Target.get() let target_of_string=Target.of_string
let is_headless=Target.is_headless let is_displayless=Target.is_displayless
let target value=value.target
let sdl_environment_names=["SDL_VIDEODRIVER";"SDL_RENDER_DRIVER";"SDL_AUDIODRIVER"]
external unset_environment:string->unit="prismel_runtime_unsetenv"
let capture_sdl_environment target=if target=Native then[]else List.map(fun name->name,Sys.getenv_opt name)sdl_environment_names
let restore_environment values=List.iter(fun(name,value)->match value with Some x->Unix.putenv name x|None->unset_environment name)values
let start~width:_~height:_~title:_~resizable:_=match Target.selected()with Error message->Error("Prismel runtime: "^message)|Ok target->let sdl_environment=capture_sdl_environment target in Target.configure_sdl_environment target;ignore(Sdl.set_hint Sdl.Hint.render_scale_quality"1");if target=Native then ignore(Sdl.set_hint Sdl.Hint.render_driver"");match Sdl.init Sdl.Init.(video+audio+events)with Error(`Msg message)->restore_environment sdl_environment;Error("SDL initialization failed: "^message)|Ok()->let flags=Tsdl_image.Image.Init.(jpg+png)in let image_initialized=Tsdl_image.Image.Init.test(Tsdl_image.Image.init flags)flags in let ttf_initialized=match Ttf.init()with Ok()->true|Error(`Msg message)->Printf.eprintf"Prismel runtime warning: TTF disabled: %s\n%!"message;false in Ok{target;sdl_environment;image_initialized;ttf_initialized;stopped=false}
let stop value=if not value.stopped then(value.stopped<-true;if value.ttf_initialized then Ttf.quit();if value.image_initialized then Tsdl_image.Image.quit();Sdl.quit();restore_environment value.sdl_environment)
let present _ renderer~logical_width:_~logical_height:_=Sdl.render_present renderer;Ok()
module Private=struct let select_target=Target.select_with end
