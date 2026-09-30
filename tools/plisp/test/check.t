One fixture per diagnostic class: the exact File line.

  $ cat > parse.plisp <<'X'
  > (workspace w
  >   (graph g :context sop (sop/box
  > X
  $ prismel-plisp check parse.plisp
  File "parse.plisp", line 2, characters 24-25:
  Error [E_UNCLOSED]: This '(' is never closed
  [1]
  $ cat > noform.plisp <<'X'
  > (foo)
  > X
  $ prismel-plisp check noform.plisp
  File "noform.plisp", line 1, characters 0-0:
  Error [E_WORKSPACE]: Expected a (workspace ...) form.
  [1]
  $ cat > kind.plisp <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (sop/bx)))
  > X
  $ prismel-plisp check kind.plisp
  File "kind.plisp", line 3, characters 4-12:
  Error [E_UNKNOWN_KIND]: Unknown operator “sop/bx”. Did you mean box?
  [1]
  $ cat > param.plisp <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (sop/box :nosuch 1)))
  > X
  $ prismel-plisp check param.plisp
  File "param.plisp", line 3, characters 13-20:
  Error [E_UNKNOWN_PARAM]: box has no parameter :nosuch.
  [1]
  $ cat > shadow.plisp <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (let* [a 1 a 2] (sop/box))))
  > X
  $ prismel-plisp check shadow.plisp
  File "shadow.plisp", line 3, characters 15-16:
  Error [E_DUPLICATE]: a is bound twice in one let*.
  [1]
  $ cat > bound.plisp <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (for [i (range 99999)] (sop/box))))
  > X
  $ prismel-plisp check bound.plisp
  File "bound.plisp", line 3, characters 12-25:
  Error [E_ITER_BOUND]: range 0‥99999 exceeds 4,096 iterations.
  File "bound.plisp", line 3, characters 4-37:
  Error [E_TYPE]: g must return geometry, but its result is list of geometry.
  [1]
  $ cat > macro.plisp <<'X'
  > (workspace w
  >   (defmacro twice [x] (+ x x))
  >   (graph g :context sop
  >     (sop/box :size (twice))))
  > X
  $ prismel-plisp check macro.plisp
  File "macro.plisp", line 4, characters 19-26:
  Error [E_MACRO_ARITY]: twice expects 1 argument; got 0.
  [1]

Warnings are errors unless the workspace says otherwise; two files, one exit code.

  $ cat > warn.plisp <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (sop/blast (sop/box) :group "nobody")))
  > X
  $ prismel-plisp check warn.plisp
  File "warn.plisp", line 3, characters 25-31:
  Warning [W_UNKNOWN_GROUP]: Group "nobody" is not made by any node upstream of blast.
  [1]
  $ (echo '^:allow-warnings'; cat warn.plisp) > allowed.plisp
  $ prismel-plisp check allowed.plisp; echo $?
  File "allowed.plisp", line 4, characters 25-31:
  Warning [W_UNKNOWN_GROUP]: Group "nobody" is not made by any node upstream of blast.
  0
  $ cat > good.plisp <<'X'
  > (workspace w
  >   (graph g :context sop
  >     (sop/box)))
  > X
  $ prismel-plisp check good.plisp kind.plisp good.plisp; echo $?
  File "kind.plisp", line 3, characters 4-12:
  Error [E_UNKNOWN_KIND]: Unknown operator “sop/bx”. Did you mean box?
  1

fmt prints the canonical text.

  $ prismel-plisp fmt good.plisp
  (workspace w
  
    (graph g :context sop
      (sop/box)))
