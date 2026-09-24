type extension =
  | Core
  | Image
  | Ttf
  | Mixer

type extension_spec =
  { extension : extension
  ; name : string
  ; package : string
  ; directory : string
  ; include_file : string
  ; header_directory : string
  ; symbol_prefix : string
  ; macro_prefixes : string list
  ; version_macros : string * string * string
  ; include_environment : string
  ; safe_functions : (string * string) list
  }

let core_safe_functions =
  [ "SDL_ClearError", "any-thread"
  ; "SDL_SetClipboardText", "main-thread"
  ; "SDL_GetClipboardText", "main-thread-owned-result"
  ; "SDL_HasClipboardText", "main-thread"
  ; "SDL_ConvertSurface", "owned-surface"
  ; "SDL_CreateProperties", "any-thread-owned-result"
  ; "SDL_CreateSurface", "any-thread"
  ; "SDL_CreateWindow", "main-thread"
  ; "SDL_DestroyWindow", "main-thread"
  ; "SDL_DestroySurface", "owned-surface"
  ; "SDL_DestroyProperties", "owned-properties"
  ; "SDL_GetError", "any-thread"
  ; "SDL_GetPerformanceCounter", "any-thread"
  ; "SDL_GetPerformanceFrequency", "any-thread"
  ; "SDL_GetDisplays", "main-thread-owned-result"
  ; "SDL_GetPrimaryDisplay", "main-thread"
  ; "SDL_GetDisplayName", "main-thread-borrowed-string"
  ; "SDL_GetDisplayBounds", "main-thread"
  ; "SDL_GetDisplayUsableBounds", "main-thread"
  ; "SDL_GetDisplayContentScale", "main-thread"
  ; "SDL_GetDisplayForWindow", "main-thread"
  ; "SDL_GetRevision", "any-thread"
  ; "SDL_GetVersion", "any-thread"
  ; "SDL_GetWindowFlags", "main-thread"
  ; "SDL_GetWindowID", "main-thread"
  ; "SDL_GetWindowPixelDensity", "main-thread"
  ; "SDL_GetWindowDisplayScale", "main-thread"
  ; "SDL_GetWindowPosition", "main-thread"
  ; "SDL_GetWindowTitle", "main-thread-borrowed-string"
  ; "SDL_GetWindowSize", "main-thread"
  ; "SDL_GetWindowSizeInPixels", "main-thread"
  ; "SDL_HideWindow", "main-thread"
  ; "SDL_SetWindowTitle", "main-thread"
  ; "SDL_SetWindowBordered", "main-thread"
  ; "SDL_SetWindowResizable", "main-thread"
  ; "SDL_SetWindowAlwaysOnTop", "main-thread"
  ; "SDL_SetWindowRelativeMouseMode", "main-thread"
  ; "SDL_GetWindowRelativeMouseMode", "main-thread"
  ; "SDL_CaptureMouse", "main-thread"
  ; "SDL_CreateSystemCursor", "main-thread-owned-result"
  ; "SDL_SetCursor", "main-thread"
  ; "SDL_DestroyCursor", "main-thread-owned-handle"
  ; "SDL_ShowCursor", "main-thread"
  ; "SDL_HideCursor", "main-thread"
  ; "SDL_CursorVisible", "main-thread"
  ; "SDL_GetCurrentDisplayMode", "main-thread-borrowed-result"
  ; "SDL_Init", "main-thread"
  ; "SDL_InitSubSystem", "main-thread"
  ; "SDL_IsMainThread", "any-thread"
  ; "SDL_IOFromConstMem", "lexical-buffer-borrow"
  ; "SDL_Metal_CreateView", "main-thread"
  ; "SDL_Metal_DestroyView", "main-thread"
  ; "SDL_Metal_GetLayer", "main-thread"
  ; "SDL_LockSurface", "owned-surface"
  ; "SDL_PollEvent", "main-thread"
  ; "SDL_Quit", "main-thread"
  ; "SDL_QuitSubSystem", "main-thread"
  ; "SDL_MaximizeWindow", "main-thread"
  ; "SDL_MinimizeWindow", "main-thread"
  ; "SDL_RestoreWindow", "main-thread"
  ; "SDL_SetWindowFullscreen", "main-thread"
  ; "SDL_SetWindowPosition", "main-thread"
  ; "SDL_SetWindowSize", "main-thread"
  ; "SDL_SetNumberProperty", "owned-properties"
  ; "SDL_ShowWindow", "main-thread"
  ; "SDL_StartTextInput", "main-thread"
  ; "SDL_StopTextInput", "main-thread"
  ; "SDL_TextInputActive", "main-thread"
  ; "SDL_SetTextInputArea", "main-thread"
  ; "SDL_GetTextInputArea", "main-thread"
  ; "SDL_UnlockSurface", "owned-surface"
  ; "SDL_SyncWindow", "main-thread-blocking"
  ; "SDL_WasInit", "initial-domain"
  ; "SDL_free", "matching-native-allocation"
  ; "SDL_WaitEventTimeout", "main-thread-blocking"
  ]

let layout_fields =
  [ "SDL_Event", []
  ; "SDL_CommonEvent", [ "type"; "timestamp" ]
  ; "SDL_DisplayEvent", [ "type"; "timestamp"; "displayID"; "data1"; "data2" ]
  ; "SDL_WindowEvent", [ "type"; "timestamp"; "windowID"; "data1"; "data2" ]
  ; "SDL_KeyboardDeviceEvent", [ "type"; "timestamp"; "which" ]
  ; ( "SDL_KeyboardEvent"
    , [ "type"; "timestamp"; "windowID"; "which"; "scancode"; "key"; "mod"
      ; "raw"; "down"; "repeat"
      ] )
  ; ( "SDL_TextEditingEvent"
    , [ "type"; "timestamp"; "windowID"; "text"; "start"; "length" ] )
  ; ( "SDL_TextEditingCandidatesEvent"
    , [ "type"; "timestamp"; "windowID"; "candidates"; "num_candidates"
      ; "selected_candidate"; "horizontal"
      ] )
  ; "SDL_TextInputEvent", [ "type"; "timestamp"; "windowID"; "text" ]
  ; "SDL_MouseDeviceEvent", [ "type"; "timestamp"; "which" ]
  ; ( "SDL_MouseMotionEvent"
    , [ "type"; "timestamp"; "windowID"; "which"; "state"; "x"; "y"; "xrel"
      ; "yrel"
      ] )
  ; ( "SDL_MouseButtonEvent"
    , [ "type"; "timestamp"; "windowID"; "which"; "button"; "down"; "clicks"
      ; "x"; "y"
      ] )
  ; ( "SDL_MouseWheelEvent"
    , [ "type"; "timestamp"; "windowID"; "which"; "x"; "y"; "direction"
      ; "mouse_x"; "mouse_y"; "integer_x"; "integer_y"
      ] )
  ; ( "SDL_TouchFingerEvent"
    , [ "type"; "timestamp"; "touchID"; "fingerID"; "x"; "y"; "dx"; "dy"
      ; "pressure"; "windowID"
      ] )
  ; "SDL_PinchFingerEvent", [ "type"; "timestamp"; "scale"; "windowID" ]
  ; "SDL_PenProximityEvent", [ "type"; "timestamp"; "windowID"; "which" ]
  ; ( "SDL_PenMotionEvent"
    , [ "type"; "timestamp"; "windowID"; "which"; "pen_state"; "x"; "y" ] )
  ; ( "SDL_PenTouchEvent"
    , [ "type"; "timestamp"; "windowID"; "which"; "pen_state"; "x"; "y"
      ; "eraser"; "down"
      ] )
  ; ( "SDL_PenButtonEvent"
    , [ "type"; "timestamp"; "windowID"; "which"; "pen_state"; "x"; "y"
      ; "button"; "down"
      ] )
  ; ( "SDL_PenAxisEvent"
    , [ "type"; "timestamp"; "windowID"; "which"; "pen_state"; "x"; "y"
      ; "axis"; "value"
      ] )
  ; "SDL_GamepadAxisEvent", [ "type"; "timestamp"; "which"; "axis"; "value" ]
  ; "SDL_GamepadButtonEvent", [ "type"; "timestamp"; "which"; "button"; "down" ]
  ; "SDL_GamepadDeviceEvent", [ "type"; "timestamp"; "which" ]
  ; ( "SDL_GamepadTouchpadEvent"
    , [ "type"; "timestamp"; "which"; "touchpad"; "finger"; "x"; "y"
      ; "pressure"
      ] )
  ; ( "SDL_GamepadSensorEvent"
    , [ "type"; "timestamp"; "which"; "sensor"; "data"; "sensor_timestamp" ] )
  ; ( "SDL_DropEvent"
    , [ "type"; "timestamp"; "windowID"; "x"; "y"; "source"; "data" ] )
  ; ( "SDL_ClipboardEvent"
    , [ "type"; "timestamp"; "owner"; "num_mime_types"; "mime_types" ] )
  ; "SDL_AudioDeviceEvent", [ "type"; "timestamp"; "which"; "recording" ]
  ; ( "SDL_SensorEvent"
    , [ "type"; "timestamp"; "which"; "data"; "sensor_timestamp" ] )
  ; "SDL_Surface", [ "format"; "w"; "h"; "pitch"; "pixels"; "refcount" ]
  ; "SDL_Rect", [ "x"; "y"; "w"; "h" ]
  ]

let abi_constants =
  [ "SDL_INIT_AUDIO"
  ; "SDL_INIT_VIDEO"
  ; "SDL_INIT_JOYSTICK"
  ; "SDL_INIT_HAPTIC"
  ; "SDL_INIT_GAMEPAD"
  ; "SDL_INIT_EVENTS"
  ; "SDL_INIT_SENSOR"
  ; "SDL_INIT_CAMERA"
  ; "SDL_WINDOW_FULLSCREEN"
  ; "SDL_WINDOW_HIDDEN"
  ; "SDL_WINDOW_RESIZABLE"
  ; "SDL_WINDOW_HIGH_PIXEL_DENSITY"
  ; "SDL_WINDOW_METAL"
  ; "SDL_PIXELFORMAT_RGBA32"
  ; "SDL_EVENT_QUIT"
  ; "SDL_EVENT_TERMINATING"
  ; "SDL_EVENT_LOW_MEMORY"
  ; "SDL_EVENT_WILL_ENTER_BACKGROUND"
  ; "SDL_EVENT_DID_ENTER_BACKGROUND"
  ; "SDL_EVENT_WILL_ENTER_FOREGROUND"
  ; "SDL_EVENT_DID_ENTER_FOREGROUND"
  ; "SDL_EVENT_LOCALE_CHANGED"
  ; "SDL_EVENT_SYSTEM_THEME_CHANGED"
  ; "SDL_EVENT_DISPLAY_ORIENTATION"
  ; "SDL_EVENT_DISPLAY_ADDED"
  ; "SDL_EVENT_DISPLAY_REMOVED"
  ; "SDL_EVENT_DISPLAY_MOVED"
  ; "SDL_EVENT_DISPLAY_DESKTOP_MODE_CHANGED"
  ; "SDL_EVENT_DISPLAY_CURRENT_MODE_CHANGED"
  ; "SDL_EVENT_DISPLAY_CONTENT_SCALE_CHANGED"
  ; "SDL_EVENT_DISPLAY_USABLE_BOUNDS_CHANGED"
  ; "SDL_EVENT_WINDOW_SHOWN"
  ; "SDL_EVENT_WINDOW_HIDDEN"
  ; "SDL_EVENT_WINDOW_EXPOSED"
  ; "SDL_EVENT_WINDOW_MOVED"
  ; "SDL_EVENT_WINDOW_RESIZED"
  ; "SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED"
  ; "SDL_EVENT_WINDOW_METAL_VIEW_RESIZED"
  ; "SDL_EVENT_WINDOW_MINIMIZED"
  ; "SDL_EVENT_WINDOW_MAXIMIZED"
  ; "SDL_EVENT_WINDOW_RESTORED"
  ; "SDL_EVENT_WINDOW_MOUSE_ENTER"
  ; "SDL_EVENT_WINDOW_MOUSE_LEAVE"
  ; "SDL_EVENT_WINDOW_FOCUS_GAINED"
  ; "SDL_EVENT_WINDOW_FOCUS_LOST"
  ; "SDL_EVENT_WINDOW_CLOSE_REQUESTED"
  ; "SDL_EVENT_WINDOW_HIT_TEST"
  ; "SDL_EVENT_WINDOW_ICCPROF_CHANGED"
  ; "SDL_EVENT_WINDOW_DISPLAY_CHANGED"
  ; "SDL_EVENT_WINDOW_DISPLAY_SCALE_CHANGED"
  ; "SDL_EVENT_WINDOW_SAFE_AREA_CHANGED"
  ; "SDL_EVENT_WINDOW_OCCLUDED"
  ; "SDL_EVENT_WINDOW_ENTER_FULLSCREEN"
  ; "SDL_EVENT_WINDOW_LEAVE_FULLSCREEN"
  ; "SDL_EVENT_WINDOW_DESTROYED"
  ; "SDL_EVENT_WINDOW_HDR_STATE_CHANGED"
  ; "SDL_EVENT_KEY_DOWN"
  ; "SDL_EVENT_KEY_UP"
  ; "SDL_EVENT_TEXT_EDITING"
  ; "SDL_EVENT_TEXT_INPUT"
  ; "SDL_EVENT_KEYMAP_CHANGED"
  ; "SDL_EVENT_KEYBOARD_ADDED"
  ; "SDL_EVENT_KEYBOARD_REMOVED"
  ; "SDL_EVENT_TEXT_EDITING_CANDIDATES"
  ; "SDL_EVENT_SCREEN_KEYBOARD_SHOWN"
  ; "SDL_EVENT_SCREEN_KEYBOARD_HIDDEN"
  ; "SDL_EVENT_MOUSE_MOTION"
  ; "SDL_EVENT_MOUSE_BUTTON_DOWN"
  ; "SDL_EVENT_MOUSE_BUTTON_UP"
  ; "SDL_EVENT_MOUSE_WHEEL"
  ; "SDL_EVENT_MOUSE_ADDED"
  ; "SDL_EVENT_MOUSE_REMOVED"
  ; "SDL_MOUSEWHEEL_NORMAL"
  ; "SDL_MOUSEWHEEL_FLIPPED"
  ; "SDL_EVENT_FINGER_DOWN"
  ; "SDL_EVENT_FINGER_UP"
  ; "SDL_EVENT_FINGER_MOTION"
  ; "SDL_EVENT_FINGER_CANCELED"
  ; "SDL_EVENT_PINCH_BEGIN"
  ; "SDL_EVENT_PINCH_UPDATE"
  ; "SDL_EVENT_PINCH_END"
  ; "SDL_EVENT_PEN_PROXIMITY_IN"
  ; "SDL_EVENT_PEN_PROXIMITY_OUT"
  ; "SDL_EVENT_PEN_MOTION"
  ; "SDL_EVENT_PEN_DOWN"
  ; "SDL_EVENT_PEN_UP"
  ; "SDL_EVENT_PEN_BUTTON_DOWN"
  ; "SDL_EVENT_PEN_BUTTON_UP"
  ; "SDL_EVENT_PEN_AXIS"
  ; "SDL_EVENT_GAMEPAD_AXIS_MOTION"
  ; "SDL_EVENT_GAMEPAD_BUTTON_DOWN"
  ; "SDL_EVENT_GAMEPAD_BUTTON_UP"
  ; "SDL_EVENT_GAMEPAD_ADDED"
  ; "SDL_EVENT_GAMEPAD_REMOVED"
  ; "SDL_EVENT_GAMEPAD_REMAPPED"
  ; "SDL_EVENT_GAMEPAD_TOUCHPAD_DOWN"
  ; "SDL_EVENT_GAMEPAD_TOUCHPAD_MOTION"
  ; "SDL_EVENT_GAMEPAD_TOUCHPAD_UP"
  ; "SDL_EVENT_GAMEPAD_SENSOR_UPDATE"
  ; "SDL_EVENT_GAMEPAD_UPDATE_COMPLETE"
  ; "SDL_EVENT_GAMEPAD_STEAM_HANDLE_UPDATED"
  ; "SDL_EVENT_DROP_FILE"
  ; "SDL_EVENT_DROP_TEXT"
  ; "SDL_EVENT_DROP_BEGIN"
  ; "SDL_EVENT_DROP_COMPLETE"
  ; "SDL_EVENT_DROP_POSITION"
  ; "SDL_EVENT_CLIPBOARD_UPDATE"
  ; "SDL_EVENT_AUDIO_DEVICE_ADDED"
  ; "SDL_EVENT_AUDIO_DEVICE_REMOVED"
  ; "SDL_EVENT_AUDIO_DEVICE_FORMAT_CHANGED"
  ; "SDL_EVENT_SENSOR_UPDATE"
  ]

let image =
  { extension = Image
  ; name = "image"
  ; package = "sdl3-image"
  ; directory = "sdl3_image"
  ; include_file = "SDL3_image/SDL_image.h"
  ; header_directory = "SDL3_image"
  ; symbol_prefix = "IMG_"
  ; macro_prefixes = [ "IMG_"; "SDL_IMAGE_" ]
  ; version_macros =
      ( "SDL_IMAGE_MAJOR_VERSION"
      , "SDL_IMAGE_MINOR_VERSION"
      , "SDL_IMAGE_MICRO_VERSION" )
  ; include_environment = "PRISMEL_SDL3_IMAGE_INCLUDE_DIR"
  ; safe_functions =
      [ "IMG_Version", "any-thread"
      ; "IMG_Load_IO", "owned-result-closes-io"
      ; "IMG_LoadTyped_IO", "owned-result-closes-io"
      ]
  }

let ttf =
  { extension = Ttf
  ; name = "ttf"
  ; package = "sdl3-ttf"
  ; directory = "sdl3_ttf"
  ; include_file = "SDL3_ttf/SDL_ttf.h"
  ; header_directory = "SDL3_ttf"
  ; symbol_prefix = "TTF_"
  ; macro_prefixes = [ "TTF_"; "SDL_TTF_" ]
  ; version_macros =
      ( "SDL_TTF_MAJOR_VERSION"
      , "SDL_TTF_MINOR_VERSION"
      , "SDL_TTF_MICRO_VERSION" )
  ; include_environment = "PRISMEL_SDL3_TTF_INCLUDE_DIR"
  ; safe_functions =
      [ "TTF_Version", "any-thread"
      ; "TTF_Init", "initial-domain"
      ; "TTF_Quit", "initial-domain"
      ; "TTF_WasInit", "any-thread"
      ; "TTF_OpenFont", "initial-domain-owned-result"
      ; "TTF_CloseFont", "font-owner-thread"
      ; "TTF_SetFontSize", "font-owner-thread"
      ; "TTF_SetFontSizeDPI", "font-owner-thread"
      ; "TTF_GetFontDPI", "font-owner-thread"
      ; "TTF_SetFontStyle", "font-owner-thread"
      ; "TTF_GetFontStyle", "font-owner-thread"
      ; "TTF_SetFontOutline", "font-owner-thread"
      ; "TTF_GetFontOutline", "font-owner-thread"
      ; "TTF_SetFontHinting", "font-owner-thread"
      ; "TTF_GetFontHinting", "font-owner-thread"
      ; "TTF_SetFontKerning", "font-owner-thread"
      ; "TTF_GetFontKerning", "font-owner-thread"
      ; "TTF_GetFontHeight", "font-owner-thread"
      ; "TTF_GetFontAscent", "font-owner-thread"
      ; "TTF_GetFontDescent", "font-owner-thread"
      ; "TTF_GetFontLineSkip", "font-owner-thread"
      ; "TTF_GetFontFamilyName", "font-owner-thread-borrowed-string"
      ; "TTF_GetFontStyleName", "font-owner-thread-borrowed-string"
      ; "TTF_FontHasGlyph", "font-owner-thread"
      ; "TTF_GetGlyphMetrics", "font-owner-thread"
      ; "TTF_GetStringSize", "font-owner-thread"
      ; "TTF_GetStringSizeWrapped", "font-owner-thread"
      ; "TTF_RenderText_Blended", "font-owner-thread-owned-result"
      ; "TTF_RenderText_Blended_Wrapped", "font-owner-thread-owned-result"
      ]
  }

let mixer =
  { extension = Mixer
  ; name = "mixer"
  ; package = "sdl3-mixer"
  ; directory = "sdl3_mixer"
  ; include_file = "SDL3_mixer/SDL_mixer.h"
  ; header_directory = "SDL3_mixer"
  ; symbol_prefix = "MIX_"
  ; macro_prefixes = [ "MIX_"; "SDL_MIXER_" ]
  ; version_macros =
      ( "SDL_MIXER_MAJOR_VERSION"
      , "SDL_MIXER_MINOR_VERSION"
      , "SDL_MIXER_MICRO_VERSION" )
  ; include_environment = "PRISMEL_SDL3_MIXER_INCLUDE_DIR"
  ; safe_functions =
      [ "MIX_Version", "any-thread"
      ; "MIX_Init", "initial-domain"
      ; "MIX_Quit", "initial-domain"
      ; "MIX_CreateMixerDevice", "main-thread-owned-result"
      ; "MIX_CreateMixer", "owned-result"
      ; "MIX_DestroyMixer", "owner-thread"
      ; "MIX_GetMixerFormat", "mixer-owner-thread"
      ; "MIX_SetMixerGain", "mixer-owner-thread"
      ; "MIX_GetMixerGain", "mixer-owner-thread"
      ; "MIX_StopAllTracks", "mixer-owner-thread"
      ; "MIX_Generate", "memory-mixer-owner-thread"
      ; "MIX_LoadAudio", "mixer-owner-thread-owned-result"
      ; "MIX_LoadAudio_IO", "mixer-owner-thread-owned-result-closes-io"
      ; "MIX_CreateSineWaveAudio", "mixer-owner-thread-owned-result"
      ; "MIX_GetAudioDuration", "audio-owner-thread"
      ; "MIX_DestroyAudio", "audio-owner-thread"
      ; "MIX_CreateTrack", "mixer-owner-thread-owned-result"
      ; "MIX_DestroyTrack", "track-owner-thread"
      ; "MIX_SetTrackAudio", "track-owner-thread"
      ; "MIX_SetTrackGain", "track-owner-thread"
      ; "MIX_GetTrackGain", "track-owner-thread"
      ; "MIX_SetTrackLoops", "track-owner-thread"
      ; "MIX_GetTrackLoops", "track-owner-thread"
      ; "MIX_PlayTrack", "track-owner-thread"
      ; "MIX_StopTrack", "track-owner-thread"
      ; "MIX_PauseTrack", "track-owner-thread"
      ; "MIX_ResumeTrack", "track-owner-thread"
      ; "MIX_TrackPlaying", "track-owner-thread"
      ; "MIX_TrackPaused", "track-owner-thread"
      ; "MIX_TrackMSToFrames", "track-owner-thread"
      ]
  }

let extension = function
  | "image" -> image
  | "ttf" -> ttf
  | "mixer" -> mixer
  | name -> Generator_support.fail "unknown SDL3 extension %S" name
