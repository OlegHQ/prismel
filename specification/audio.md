# Audio

## Lifecycle

Prismel initializes SDL_mixer with the application and closes it before SDL
shutdown. The backend configures SDL's dummy audio driver under `HEADLESS`, so
loading, decoding, channel allocation, and playback calls execute in CI without
a physical audio device.

Audio initialization failure does not prevent a visual sketch from starting;
the application prints one warning. Explicit audio loads then return the
underlying initialization error.

All audio control and resource operations are initial-domain-only. SDL_mixer
callbacks and raw buffers are intentionally not exposed in the high-level API.

## Samples

`Audio.Sample` represents a decoded short sound:

- load WAV and SDL_mixer-supported sample files;
- synthesize sine, square, saw, or triangle tones;
- play with repeat count and normalized volume;
- pause, resume, query, or stop a returned channel;
- destroy explicitly, or borrow through `Assets`.

`loops` follows SDL_mixer semantics: zero plays once, a positive value repeats
that many additional times, and `-1` loops indefinitely.

## Music

`Audio.Music` represents a streamed track:

- load formats enabled by the host SDL_mixer build;
- play or stop with optional millisecond fades;
- pause, resume, query, and set normalized volume.

SDL_mixer owns one global music stream. Starting another music value replaces
the current stream according to SDL_mixer behavior.

## Ownership

Directly loaded or synthesized values are caller-owned and must be released in
`Sketch.run_state ~on_stop`. Samples/music loaded through `Assets` are borrowed
and released by `Sketch.run_assets`.

## Scope

This API covers playback and intentionally simple oscillators useful for quick
sketches. A future synthesis graph should be a separate pure signal API feeding
a carefully synchronized audio callback; it should not grow ad-hoc mutable
oscillator functions inside `Audio.Sample`.
