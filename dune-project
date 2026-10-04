(lang dune 3.17)

(using directory-targets 0.1)

(name rays)

(generate_opam_files true)

(source
 (github OlegHQ/rays))

(authors "Oleg Pustovit <oleg@nexo.sh>")

(maintainers "Oleg Pustovit <oleg@nexo.sh>")

(license MIT)

(package
 (name rays)
 (synopsis "A modern, functional graphics framework for OCaml")
 (description "A clean, type-safe API for creating interactive graphics applications, games, and generative art in OCaml")
 (depends
  (ocaml (>= 5.2))
  (dune (>= 3.21))
  digestif
  dune-configurator
  ppxlib
  (odoc :with-doc)
  domainslib
  yojson
  conf-sdl3
  conf-sdl3-image
  conf-sdl3-ttf
  conf-sdl3-mixer)
 (tags
  ("ocaml" "graphics" "framework" "creative-coding" "gamedev")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
