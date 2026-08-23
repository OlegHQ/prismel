(lang dune 3.17)

(using directory-targets 0.1)

(name prismel)

(generate_opam_files true)

(source
 (github nexo-tech/prismel))

(authors "Oleg Pustovit <oleg@nexo.sh>")

(maintainers "Oleg Pustovit <oleg@nexo.sh>")

(license MIT)

(documentation https://nexo.sh/prismel)

(package
 (name prismel)
 (synopsis "A modern, functional graphics framework for OCaml")
 (description "A clean, type-safe API for creating interactive graphics applications, games, and generative art in OCaml")
 (depends
  (ocaml (>= 5.2))
  (dune (>= 3.17))
  tsdl
  tsdl-image
  tsdl-ttf
  tsdl-mixer
  ctypes
  ctypes-foreign
  digestif
  dune-configurator
  ppxlib
  (odoc :with-doc)
  (utop :with-test)
  domainslib
  yojson
  conf-sdl2
  conf-sdl2-image
  conf-sdl2-ttf
  conf-sdl2-mixer
  conf-sdl3
  conf-sdl3-image
  conf-sdl3-ttf
  conf-sdl3-mixer)
 (tags
  ("ocaml" "graphics" "framework" "creative-coding" "gamedev")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
