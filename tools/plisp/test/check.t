One fixture per diagnostic class: the exact File line.

  $ cat > parse.rays <<'X'
  > (workspace w
  >   (graph g :context sop (sop/box
  > X
  $ rays-plisp check parse.rays
  File "parse.rays", line 2, characters 24-25:
  Error [E_UNCLOSED]: This '(' is never closed
  [1]
  $ cat > noform.rays <<'X'
  > (foo)
  > X
  $ rays-plisp check noform.rays
  File "noform.rays", line 1, characters 0-0:
  Error [E_WORKSPACE]: Expected a (workspace ...) form.
  [1]
  $ cat > kind.rays <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (sop/bx)))
  > X
  $ rays-plisp check kind.rays
  File "kind.rays", line 3, characters 4-12:
  Error [E_UNKNOWN_KIND]: Unknown operator “sop/bx”. Did you mean box?
  [1]
  $ cat > param.rays <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (sop/box :nosuch 1)))
  > X
  $ rays-plisp check param.rays
  File "param.rays", line 3, characters 13-20:
  Error [E_UNKNOWN_PARAM]: box has no parameter :nosuch.
  [1]
  $ cat > shadow.rays <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (let* [a 1 a 2] (sop/box))))
  > X
  $ rays-plisp check shadow.rays
  File "shadow.rays", line 3, characters 15-16:
  Error [E_DUPLICATE]: a is bound twice in one let*.
  [1]
  $ cat > bound.rays <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (for [i (range 99999)] (sop/box))))
  > X
  $ rays-plisp check bound.rays
  File "bound.rays", line 3, characters 12-25:
  Error [E_ITER_BOUND]: range 0‥99999 exceeds 4,096 iterations.
  File "bound.rays", line 3, characters 4-37:
  Error [E_TYPE]: g must return geometry, but its result is list of geometry.
  [1]
  $ cat > macro.rays <<'X'
  > (workspace w
  >   (defmacro twice [x] (+ x x))
  >   (graph g :context sop
  >     (sop/box :size (twice))))
  > X
  $ rays-plisp check macro.rays
  File "macro.rays", line 4, characters 19-26:
  Error [E_MACRO_ARITY]: twice expects 1 argument; got 0.
  [1]

Warnings are errors unless the workspace says otherwise; two files, one exit code.

  $ cat > warn.rays <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (sop/blast (sop/box) :group "nobody")))
  > X
  $ rays-plisp check warn.rays
  File "warn.rays", line 3, characters 25-31:
  Warning [W_UNKNOWN_GROUP]: Group "nobody" is not made by any node upstream of blast.
  [1]
  $ (echo '^:allow-warnings'; cat warn.rays) > allowed.rays
  $ rays-plisp check allowed.rays; echo $?
  File "allowed.rays", line 4, characters 25-31:
  Warning [W_UNKNOWN_GROUP]: Group "nobody" is not made by any node upstream of blast.
  0
  $ cat > good.rays <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (sop/box)))
  > X
  $ rays-plisp check good.rays kind.rays good.rays; echo $?
  File "kind.rays", line 3, characters 4-12:
  Error [E_UNKNOWN_KIND]: Unknown operator “sop/bx”. Did you mean box?
  1

fmt prints the canonical text.

  $ rays-plisp fmt good.rays
  (workspace w
  
    (graph g :context sop
      (sop/box)))
