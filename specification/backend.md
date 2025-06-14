## Backend Integration Details (Tsdl, Tsdl_image, Tsdl_mixer, etc.)

Our framework is built atop the SDL2 library via OCaml bindings, taking advantage of SDL’s cross-platform capabilities for windowing, graphics, and audio. Here we summarize how we use these backend libraries and any important integration points:

- **Tsdl (SDL2):** Tsdl provides low-level functions to create windows, render graphics, and handle events in OCaml. We rely on Tsdl for:

  - Initializing subsystems: `Sdl.init` with flags (video, audio, events).
  - Creating the main window (`Sdl.create_window`) and setting its properties (size, title, fullscreen). Tsdl maps directly to SDL functions and constants, e.g., `Sdl.Window.resizable` flag corresponds to `SDL_WINDOW_RESIZABLE`.
  - Creating an SDL renderer (`Sdl.create_renderer`) which we use for all 2D drawing. We request hardware acceleration and vsync by default, as mentioned, which yields smooth rendering on most systems.
  - Event handling: Tsdl provides an event type and functions to poll events. For example, `Sdl.poll_event (Some event)` fills an `Sdl.Event.t` structure. We then use `Sdl.Event.get` to extract fields (type, key code, etc.) and translate them to our `Event.t`. Tsdl’s event constants and types align with SDL’s; e.g., a key down event is identified by `Sdl.Event.key_down` tag and you can get the scancode or key symbol from the event. We carefully map those to our Input.key variant. Notably, Tsdl delivers event data as `Sdl.Event.*` functions, and uses `Error (`Msg e)`for some operations if needed. We have to handle the case where certain events (like text input or controller events) exist but we haven't defined a corresponding variant; those we simply ignore or treat as`Event.Unknown\` if we had such.
  - Window functions: we use `Sdl.set_window_title`, `Sdl.set_window_fullscreen`, etc., from Tsdl when the user calls our Window module functions. Tsdl’s naming conventions made these available in `Sdl.Window` submodule. We follow those (e.g., `Sdl.set_window_title win "Title"`).
  - Clean up: `Sdl.destroy_renderer` and `Sdl.destroy_window` free the window and context, and `Sdl.quit` shuts down all SDL subsystems. Tsdl covers all that.

- **Tsdl_image (SDL2_image):** Tsdl_image is the OCaml binding for SDL_image, which loads image files of various formats. We utilize it for:

  - Loading surfaces from files: `Img.load "file.ext"` returns a surface (wrapped in OCaml as `Sdl.surface`). Tsdl_image’s `Img.load` will automatically detect format by extension or file content and use the appropriate decoder (PNG, JPEG, etc.). We check the result: if `Error (`Msg e)`, we propagate that e in our `Image.load\` result.
  - Initializing image library: We call `Img.init (Img.Init.png + Img.Init.jpg)` to ensure support for PNG and JPEG at least. Tsdl_image’s `Img.Init` flags correspond to SDL_image flags like `IMG_INIT_PNG`. If `Img.init` returns a subset of those flags (meaning some failed), we know a codec might not be available. We might still proceed, but image load of that format would error. We could log a warning if, say, PNG init failed.
  - There is `Img.quit` to deinitialize if needed (we call it on shutdown).
  - The binding closely mirrors SDL_image, so for save we would use `Img.save_png` or similar if present. The doc snippet suggests binding covers interface closely, so likely functions like `Img.save_png` or `Img.save` exist. We'll use those in Image.save if available.

- **Tsdl_mixer (SDL2_mixer):** Tsdl_mixer binds SDL_mixer for audio. We use it to:

  - Initialize audio: `Mix.open_audio frequency format channels chunk_size`. For example, `Mix.open_audio 44100 Mix.default_format 2 1024` to open at 44.1 kHz, signed 16-bit stereo, chunk of 1024 samples. Tsdl_mixer’s `Mix.default_format` might be the AUDIO_S16LSB which is typical. We check the result (should be Ok or unit). If `Error (`Msg e)\`, we fail (audio device problem).
  - Init codecs: `Mix.init (Mix.Init.mp3 + Mix.Init.ogg)` to enable those decoders. If not all bits returned, possibly some codec missing (we could warn the user if they try to load that format).
  - Load sounds:

    - `Mix.load_wav "file.wav"` returns a `Mix.chunk`. Tsdl_mixer likely has `Mixer.load_wav` binding.
    - `Mix.load_music "file.ogg"` returns a `Mix.music`. Bound as `Mixer.load_music`.
      These return `Error (`Msg e)\` on failure which we propagate in Sound.load result.

  - Play sounds:

    - `Mix.play_channel (-1) chunk loops` plays on first free channel. Tsdl_mixer’s `Mixer.play_channel` likely returns the channel number or -1 on failure. We'll call it and perhaps ignore the channel number except maybe store if we want to manage specifically. We could log if returns -1 (means no free channel).
    - `Mix.play_music music loops` to play music. Returns Ok or an error code maybe; SDL_mixer might not fail play unless something is wrong with the music pointer.

  - Control:

    - Volume: `Mix.volume_chunk chunk volume` sets volume for that chunk. `Mix.volume_music vol` sets music volume.
    - Halt: `Mix.halt_channel channel` stops channel, `Mix.halt_music` stops music.
    - Pause/Resume: `Mix.pause channel`, `Mix.resume channel`, `Mix.pause_music`, `Mix.resume_music`.
    - Query: `Mix.playing channel` returns whether channel is active, `Mix.playing_music` for music.
    - We use these to implement Sound.is_playing or internal checks for stop all (e.g., `Mix.halt_channel (-1)` stops all channels).

  - We also allocate channels: `Mix.allocate_channels n`. We'll call that after open_audio to ensure we have, say, 32 channels. (If user’s config or usage hints more channels, we could allow config for that, but 32 is fine default).
  - On shutdown: `Mix.close_audio` to close device, `Mix.quit` to deinit mixer (free codecs, etc.).
  - Tsdl_mixer functions usually return unit or result. We handle accordingly.

- **Tsdl_ttf (SDL2_ttf):** If we incorporate font rendering:

  - We call `Ttf.init ()` at start.
  - Use `Ttf.open_font file ptsize` to get a `Ttf.font`.
  - Use `Ttf.render_utf8_solid font text color` to get an `Sdl.surface` with rendered text.
  - Then like images, create a texture from that surface.
  - Manage caching if needed (like we might not want to re-render static text each frame, so user might keep an Image.t for some text).
  - At end, call `Ttf.quit ()`.
  - Tsdl_ttf’s API will match C API closely, just result-wrapped.
  - We’d integrate this in our Font and Graphics.text functions.

- **OCaml GC and finalizers:** Some integration details:

  - Tsdl uses Ctypes under the hood and allocates memory for e.g. Sdl.window, Sdl.renderer, etc. It likely sets up finalizers to free them if GC collects them, but we cannot rely on that for timely destruction (we call destroy explicitly).
  - We must ensure not to double free (if Tsdl finalizer also frees). Usually, Tsdl’s documentation says when you call `Sdl.destroy_window`, it nullifies its internal pointer and disables finalizer. So safe.
  - We should wrap any raw pointers (like mix chunk pointers) carefully. Tsdl_mixer might represent Mix.chunk as an abstract type with finalizer that calls Mix.free_chunk when GC collects. Actually, from the Tsdl_mixer snippet, it likely has similar structure (maybe not finalizing automatically since audio often persistent).
  - Regardless, we explicitly free things via our destroy to avoid waiting for GC.

- **Thread main requirement:** On some platforms (macOS/Cocoa), SDL requires events and window creation on main thread. Our design runs everything on main thread (OCaml programs by default single-threaded unless using threads). So that’s fine. If user uses domains/threads (OCaml 5), they must still ensure not to call SDL from other domains; we should mention the requirement that all SDL interactions should happen in the main domain. We do not inherently support multi-domain parallelism, as SDL isn't thread-safe for most calls.

- **Precision of timers:** We use `Sdl.get_performance_counter` and `Sdl.get_performance_frequency` behind `Time.now()`. If Tsdl provides a convenience for high-precision time, we use it. Otherwise, `Unix.gettimeofday` or `Sdl.get_ticks` (ms resolution) could be used. For smooth animation, performance counter is best (microsecond resolution). We likely use `Sdl.get_ticks` for simplicity (ms int) given moderate requirement, but since we wrote aiming at high quality, perhaps use performance counters:

  - Tsdl might not directly expose `SDL_GetPerformanceCounter` (though it might).
  - If not, we can use `Mtime_clock.now ()` from ocaml’s monotonic clock as alternative. But to avoid new dependency, maybe just `Unix.gettimeofday` (gives float seconds with microsecond resolution on many systems).
  - We'll specify we measure time in seconds as float using a high-precision source (e.g., performance counter if available, else fall back to tick). In results, we mention dt usage is fine either way because \~1ms resolution is enough for game stepping (60fps \~16ms frame).

- **Safety and error messages:** Tsdl functions often return `Error (`Msg e)`with e coming from SDL’s`SDL_GetError`string when something fails. We propagate these to the user in our error results. For example, if`Image.load\` fails due to an unsupported format, SDL_image might set error "Unsupported image format" which Tsdl_image passes to us. We include that in Error so user sees something like "SDL_Image error: Unsupported format".

  - We avoid exposing raw pointers or the need for user to call any Tsdl function directly. They can entirely use our higher-level API.

- **Resource Limits:** Under the hood, SDL might have limits (max texture size, as said, or limited channels for audio, etc.). We try to handle gracefully:

  - If `Sdl.create_texture_from_surface` fails, it could be because image too large or out of GPU memory. We propagate error. We might in future add image resizing fallback if too large (not doing now).
  - If `Mix.play_channel` returns -1 (no free channel), perhaps allocate more channels or warn user to allocate more via Sound.set_channel_count. We could auto-allocate one more channel when needed (not trivial to expand constantly). Simpler: we allocate a fixed high number up front.

- **Integration testing:**

  - Because our code is layered on Tsdl etc., if an issue arises it might come from either our logic or underlying library.
  - For instance, memory leak: if we forget to destroy textures, GPU memory leaks; Tsdl won't auto free textures unless finalizer runs (and if we keep reference in Image.t, finalizer won't run until GC collects Image).
  - Or if audio is choppy: maybe we chose a too small chunk size. Could adjust if needed.
  - We rely on Tsdl design decisions (like event polling scheme, and results carrying SDL_GetError message as `Msg`). That is convenient because we can take that message directly to user.

In summary, our framework stands on the shoulders of these libraries:

- **SDL2 (via Tsdl)** for core cross-platform tasks (window, input, 2D rendering).
- **SDL2_image (via Tsdl_image)** to easily load various image formats (so the user doesn’t worry about decoding PNG, etc.).
- **SDL2_mixer (via Tsdl_mixer)** to handle audio decoding and mixing for multiple sound channels, simplifying audio playback a lot.
- **SDL2_ttf (via Tsdl_ttf)** if we use it for fonts, to generate text surfaces for drawing.

Using these libraries means our small framework inherits a lot of capability:
cross-platform support (Windows, Mac, Linux, etc.), support for many media formats, and hardware acceleration, without us writing platform-specific code or implementing complex decoders ourselves. It does mean our performance and limitations are tied to SDL's. For example, the renderer is not as flexible as OpenGL for certain tasks (like custom shaders or 3D), but it’s robust for 2D and very much in line with openFrameworks’ default renderer (which also uses OpenGL under the hood, but in immediate mode style).

We ensure to keep the integration details hidden from the user behind our safer abstractions (e.g., user deals with `Image.t` not `Sdl.texture`, and with `Sound.t` not raw Mix_Chunk pointers), but we pass through any meaningful errors and handle resource management carefully as guided by SDL’s API. This approach lets the user focus on creative aspects while we handle the glue to the SDL world.
