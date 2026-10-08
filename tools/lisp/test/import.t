Imports splice shared definitions and graphs; generated programs embed the original texts.

  $ mkdir -p s/one
  $ echo '(workspace library (defn twice :context value [(x : float)] (* x 2)) (graph shared :context value (twice 3)))' > s/one/lib.rays
  $ echo '(workspace one (graph g :context value (+ (ref shared) (twice 4)))) (import "lib.rays")' > s/one/sketch.rays
  $ rays-lisp check s/one/sketch.rays
  $ rays-lisp ml s/one/sketch.rays | grep '~imports:'
      ~imports:[("lib.rays", "(workspace library (defn twice :context value [(x : float)] (* x 2)) (graph shared :context value (twice 3)))\n")]
  $ rays-lisp dune s | grep '(deps '
    (deps sketch.rays "lib.rays" (glob_files *.png) (glob_files *.ttf))
  $ rays-lisp fmt s/one/sketch.rays | grep import
  (import "lib.rays")
  $ echo '(import "other.rays")' >> s/one/lib.rays
  $ rays-lisp check s/one/sketch.rays 2>&1 | grep E_IMPORT
  Error [E_IMPORT]: lib.rays: transitive imports are not supported.
  $ rm s/one/lib.rays
  $ rays-lisp check s/one/sketch.rays 2>&1 | grep E_IMPORT
  Error [E_IMPORT]: lib.rays: s/one/lib.rays: No such file or directory
