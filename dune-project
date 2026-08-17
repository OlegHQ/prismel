(lang dune 3.17)

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
  dune-configurator
  ppxlib
  (odoc :with-doc)
  (utop :with-test)
  domainslib
  conf-sdl2
  conf-sdl2-image
  conf-sdl2-ttf
  conf-sdl2-mixer)
 (tags
  ("ocaml" "graphics" "framework" "creative-coding" "gamedev")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
