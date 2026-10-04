(* What the SDL stubs bind. Nothing here names a version: versions live in
   packaging/sdl3.lock, struct layouts in lib/sdl3/abi.sexp. *)

type component =
  { key : string  (** the [packaging/sdl3.lock] entry *)
  ; directory : string
  ; stubs : string list  (** the C files whose reads and calls are the binding *)
  ; version_macro : string
  ; major_macro : string
  ; include_file : string
  ; signatures : (string * string * string) list
        (** [(function, typedef name, C function type)]: the calls whose
            signature and calling convention the stubs rely on *)
  }

let core =
  { key = "sdl3"
  ; directory = "lib/sdl3"
  ; stubs = [ "lib/sdl3/sdl3_stubs.c"; "lib/sdl3/sdl3_dialog.c" ]
  ; version_macro = "SDL_VERSION"
  ; major_macro = "SDL_MAJOR_VERSION"
  ; include_file = "SDL3/SDL.h"
  ; signatures = []
  }

let image =
  { key = "sdl3_image"
  ; directory = "lib/sdl3_image"
  ; stubs = [ "lib/sdl3_image/sdl3_image_stubs.c" ]
  ; version_macro = "SDL_IMAGE_VERSION"
  ; major_macro = "SDL_IMAGE_MAJOR_VERSION"
  ; include_file = "SDL3_image/SDL_image.h"
  ; signatures =
      [ "IMG_Version", "prismel_img_version_fn", "int (SDLCALL *)(void)"
      ; ( "IMG_Load_IO"
        , "prismel_img_load_io_fn"
        , "SDL_Surface * (SDLCALL *)(SDL_IOStream *, bool)" )
      ; ( "IMG_LoadTyped_IO"
        , "prismel_img_load_typed_io_fn"
        , "SDL_Surface * (SDLCALL *)(SDL_IOStream *, bool, const char *)" )
      ]
  }

let ttf =
  { key = "sdl3_ttf"
  ; directory = "lib/sdl3_ttf"
  ; stubs = [ "lib/sdl3_ttf/sdl3_ttf_stubs.c" ]
  ; version_macro = "SDL_TTF_VERSION"
  ; major_macro = "SDL_TTF_MAJOR_VERSION"
  ; include_file = "SDL3_ttf/SDL_ttf.h"
  ; signatures =
      [ "TTF_Version", "prismel_ttf_version_fn", "int (SDLCALL *)(void)"
      ; "TTF_Init", "prismel_ttf_init_fn", "bool (SDLCALL *)(void)"
      ; "TTF_Quit", "prismel_ttf_quit_fn", "void (SDLCALL *)(void)"
      ; ( "TTF_OpenFont"
        , "prismel_ttf_open_font_fn"
        , "TTF_Font * (SDLCALL *)(const char *, float)" )
      ; ( "TTF_CloseFont"
        , "prismel_ttf_close_font_fn"
        , "void (SDLCALL *)(TTF_Font *)" )
      ; ( "TTF_GetStringSize"
        , "prismel_ttf_size_fn"
        , "bool (SDLCALL *)(TTF_Font *, const char *, size_t, int *, int *)" )
      ; ( "TTF_RenderText_Blended"
        , "prismel_ttf_render_fn"
        , "SDL_Surface * (SDLCALL *)(TTF_Font *, const char *, size_t, \
           SDL_Color)" )
      ]
  }

let mixer =
  { key = "sdl3_mixer"
  ; directory = "lib/sdl3_mixer"
  ; stubs = [ "lib/sdl3_mixer/sdl3_mixer_stubs.c" ]
  ; version_macro = "SDL_MIXER_VERSION"
  ; major_macro = "SDL_MIXER_MAJOR_VERSION"
  ; include_file = "SDL3_mixer/SDL_mixer.h"
  ; signatures =
      [ "MIX_Version", "prismel_mix_version_fn", "int (SDLCALL *)(void)"
      ; "MIX_Init", "prismel_mix_init_fn", "bool (SDLCALL *)(void)"
      ; "MIX_Quit", "prismel_mix_quit_fn", "void (SDLCALL *)(void)"
      ; ( "MIX_CreateMixerDevice"
        , "prismel_mix_create_device_fn"
        , "MIX_Mixer * (SDLCALL *)(SDL_AudioDeviceID, const SDL_AudioSpec *)" )
      ; ( "MIX_CreateMixer"
        , "prismel_mix_create_fn"
        , "MIX_Mixer * (SDLCALL *)(const SDL_AudioSpec *)" )
      ; ( "MIX_LoadAudio"
        , "prismel_mix_load_fn"
        , "MIX_Audio * (SDLCALL *)(MIX_Mixer *, const char *, bool)" )
      ; ( "MIX_CreateTrack"
        , "prismel_mix_create_track_fn"
        , "MIX_Track * (SDLCALL *)(MIX_Mixer *)" )
      ; ( "MIX_PlayTrack"
        , "prismel_mix_play_track_fn"
        , "bool (SDLCALL *)(MIX_Track *, SDL_PropertiesID)" )
      ; ( "MIX_Generate"
        , "prismel_mix_generate_fn"
        , "int (SDLCALL *)(MIX_Mixer *, void *, int)" )
      ]
  }

let all = [ core; image; ttf; mixer ]

let component name =
  match List.find_opt (fun spec -> spec.key = name) all with
  | Some spec -> spec
  | None -> failwith ("unknown SDL3 component " ^ name)

(* The members of the [SDL_Event] union the stubs may read ([event->key.x]),
   with the struct each one is. *)
let event_members =
  [ "common", "SDL_CommonEvent"
  ; "display", "SDL_DisplayEvent"
  ; "window", "SDL_WindowEvent"
  ; "kdevice", "SDL_KeyboardDeviceEvent"
  ; "key", "SDL_KeyboardEvent"
  ; "edit", "SDL_TextEditingEvent"
  ; "edit_candidates", "SDL_TextEditingCandidatesEvent"
  ; "text", "SDL_TextInputEvent"
  ; "mdevice", "SDL_MouseDeviceEvent"
  ; "motion", "SDL_MouseMotionEvent"
  ; "button", "SDL_MouseButtonEvent"
  ; "wheel", "SDL_MouseWheelEvent"
  ; "gdevice", "SDL_GamepadDeviceEvent"
  ; "gaxis", "SDL_GamepadAxisEvent"
  ; "gbutton", "SDL_GamepadButtonEvent"
  ; "gtouchpad", "SDL_GamepadTouchpadEvent"
  ; "gsensor", "SDL_GamepadSensorEvent"
  ; "adevice", "SDL_AudioDeviceEvent"
  ; "sensor", "SDL_SensorEvent"
  ; "tfinger", "SDL_TouchFingerEvent"
  ; "pinch", "SDL_PinchFingerEvent"
  ; "pproximity", "SDL_PenProximityEvent"
  ; "ptouch", "SDL_PenTouchEvent"
  ; "pmotion", "SDL_PenMotionEvent"
  ; "pbutton", "SDL_PenButtonEvent"
  ; "paxis", "SDL_PenAxisEvent"
  ; "drop", "SDL_DropEvent"
  ; "clipboard", "SDL_ClipboardEvent"
  ]

(* Other structs read through a pointer variable ([surface->pitch]). *)
let pointer_structs = [ "surface", "SDL_Surface"; "mode", "SDL_DisplayMode" ]

(* Structs the stubs build and hand to SDL, with the fields they set. *)
let constructed_structs = [ "SDL_DialogFileFilter", [ "name"; "pattern" ] ]
