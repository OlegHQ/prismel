(lang dune 3.17)

(name prismel)

(generate_opam_files true)

(source
 (github nexo-tech/prismel))

(authors "Oleg Pustovit <oleg@nexo.sh>")

(maintainers "Oleg Pustovit <oleg@nexo.sh>")

(license LICENSE)

(documentation https://nexo.sh/prismel)

(package
 (name prismel)
 (synopsis "A modern, functional graphics framework for OCaml")
 (description "A clean, type-safe API for creating interactive graphics applications, games, and generative art in OCaml")
 (depends ocaml)
 (tags
  ("ocaml" "graphics" "framework" "creative-coding" "gamedev")))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
