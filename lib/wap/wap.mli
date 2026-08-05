(** Lean browser presentation transport for Prismel runtimes. *)

type mouse_button = Left | Middle | Right | X1 | X2

type event =
  | Pointer_moved of int * int
  | Pointer_pressed of mouse_button * int * int
  | Pointer_released of mouse_button * int * int
  | Pointer_cancelled of mouse_button
  | Wheel of int * int
  | Key_pressed of string
  | Key_released of string
  | Text_input of string
  | Text_editing of { text : string; start : int; length : int }
  | Resized of int * int
  | Focus_lost
  | File_uploaded of { name : string; contents : bytes }

type pixel_buffer =
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

type text_input_region = {
  x : int;
  y : int;
  width : int;
  height : int;
  focused : bool;
}

type audio_command =
  | Audio_master_volume of float
  | Audio_stop_all
  | Audio_sample_play of {
      asset : string; channel : int; loops : int; volume : float;
    }
  | Audio_sample_volume of { asset : string; volume : float }
  | Audio_sample_stop of int
  | Audio_sample_pause of int
  | Audio_sample_resume of int
  | Audio_music_play of { asset : string; loops : int; fade_ms : int }
  | Audio_music_volume of float
  | Audio_music_pause
  | Audio_music_resume
  | Audio_music_stop of int
  | Audio_asset_remove of string

type config = {
  interface : string;
  port : int;
  title : string;
  resizable : bool;
  max_events : int;
  max_clients : int;
  max_connections : int;
  max_message_bytes : int;
  max_queued_event_bytes : int;
  max_frame_pool_bytes : int;
  compress_frames : bool;
}

val default_config : config
type t

type stats = {
  frames_submitted : int;
  frames_published : int;
  frames_suppressed : int;
  source_bytes_submitted : int64;
  payload_bytes_published : int64;
  frames_sent : int;
  payload_bytes_sent : int64;
}

val start : ?config:config -> unit -> (t, string) result
(** Start an HTTP/WebSocket server. The default interface is [0.0.0.0]. *)

val stop : t -> unit
val interface : t -> string
val port : t -> int
val url : t -> string
val client_count : t -> int
val stats : t -> stats
(** Return a consistent snapshot of frame compression, suppression, and
    per-client delivery counters. WebSocket framing bytes are not included. *)

val acquire_frame : t -> length:int -> pixel_buffer
(** Borrow an exclusively owned frame buffer. It must be passed exactly once
    to [publish_frame]. *)

val discard_frame : t -> pixel_buffer -> unit
(** Return an acquired buffer without publishing it. *)

val publish_frame :
  t ->
  drawable_width:int ->
  drawable_height:int ->
  logical_width:int ->
  logical_height:int ->
  pixel_buffer ->
  unit
(** Publish a complete RGBA8 frame. Exact duplicates are suppressed and, when
    enabled, compressible full frames and dirty rectangles use the lossless QOI
    codec. Each client receives at most one unacknowledged frame and skips stale
    frames, so queued frame memory remains bounded. Ownership of the buffer
    transfers back to the server. *)

val drain_events : t -> event list

val broadcast_text : t -> string -> unit
(** Queue a small ordered control message for every connected browser. The
    command ring is bounded; lagging clients resume at the oldest retained
    command. *)

val set_text_input_regions : t -> text_input_region list -> unit
(** Replace browser text-entry hit regions. Wap owns the wire encoding and
    suppresses unchanged region messages. *)

(* Ask each currently connected browser to encode its presented canvas as a
    PNG and download it. The filename is reduced to a portable basename. *)
val download_frame : t -> filename:string -> (unit, string) result

val broadcast_audio : t -> audio_command -> unit
(** Encode and broadcast one browser-audio operation. Wap owns the browser
    protocol; callers provide only typed audio facts. *)

val register_file : t -> ?content_type:string -> string -> string option
val register_bytes : t -> ?content_type:string -> bytes -> string option
val remove_asset : t -> string -> unit
(** Register token-protected browser assets. Returned identifiers are opaque;
    registered byte strings are copied into immutable transport ownership. *)

module Private : sig
  val websocket_accept : string -> string
  val decode_event : bytes -> event option
  val decode_events : bytes -> event list
end
