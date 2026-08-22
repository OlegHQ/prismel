open Tsdl

let format_rgba32 =
  if Sys.big_endian then Sdl.Pixel.format_rgba8888
  else Sdl.Pixel.format_abgr8888
