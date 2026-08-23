(** Strict parsing of macOS introduction versions from Apple availability
    macro invocations in SDK header text. *)

type version =
  { major : int
  ; minor : int
  ; patch : int
  }

type error =
  { offset : int
  ; message : string
  }

type site_error =
  { site_index : int
  ; error : error
  }

(** Lexicographic comparison by major, minor, then patch component. *)
val compare : version -> version -> int

val equal : version -> version -> bool

(** Canonical spelling. A zero patch component is omitted. *)
val canonical : version -> string

(** Parse one declaration/header site.

    Supported forms are [API_AVAILABLE(..., macos(introduced), ...)],
    [API_DEPRECATED(..., macos(introduced, deprecated), ...)], and
    [API_DEPRECATED_WITH_REPLACEMENT(...,
    macos(introduced, deprecated), ...)]. Whitespace around macro tokens and
    separators is accepted. Versions require a major and minor component and
    may have one patch component.

    [Ok None] means that the site contains no macOS availability clause. A
    malformed macOS clause, a duplicate clause, a malformed supported macro,
    or [API_UNAVAILABLE(macos)] is an [Error], never [Ok None]. *)
val parse_site : string -> (version option, error) result

(** Maximum introduction version, ignoring absent sites. *)
val maximum : version option list -> version option

(** Parse all inherited/declaration sites and return their maximum effective
    macOS introduction. Errors identify the zero-based input site. *)
val combine_sites : string list -> (version option, site_error) result

(** Run deterministic parser, rejection, canonicalization, and ordering
    fixtures. This is also run when the module is initialized. *)
val validate : unit -> unit
