# Workspace case studies

**Proposal, 29 September 2026.** These are the reference programs for sketches
that use iteration, scopes, groups, functions, records, lists, branches and macros. Each isolates one construct. The
[study](prototype/index.html) opens every one of them: pick it from the case
menu or from its gallery card. The design they exercise is in
[iteration.md](iteration.md); the rules they rely on are in
[ambiguities.md](ambiguities.md).

This file is generated from `prototype/cases.js`, so the Lisp here is
exactly what the study checks. The OCaml wrapper uses the proposed
`[%workspace]` extension: today’s `[%flow]` accepts one `graph` plus
`defgraph`s and does not yet have loops or graph inputs. Studies without an
editor graph get the study’s default shell and scene when opened.

| Case | Construct | Iterations |
|---|---|---|
| [Bloom studio](#bloom-studio) | for · function · six contexts | ring for ×12 |
| [Sunflower](#sunflower) | for · sparklines · invariants | seeds_each for ×240 |
| [Tunnel](#tunnel) | fold · feedback | nested fold ×18 |
| [Fractal tree](#fractal-tree) | fold · doubling · scope | crown fold ×7 |
| [Square wave](#square-wave) | Σ in an expression · nested loops · t | y (inline) sum ×800, pts for ×160 |
| [Ten print](#ten-print) | nested for · if · rand | cells_each for ×64 |
| [Facade](#facade) | groups · named scope | windows for ×30 |
| [Variations](#variations) | graph inputs · loops in the editor | sheet (inline) for ×4 |
| [Garland](#garland) | λ functions · map · filter · reduce · sort-by | def:ring (inline) fn ×0, size fn ×14, big (inline) fn ×14, ordered (inline) fn ×8, bead fn ×8, leaf fn ×14 |
| [Kit of parts](#kit-of-parts) | records · values · destructuring · lists · cond · case · str | style fn ×5, tower fold ×5 |
| [Rosette](#rosette) | hygienic macros · expansion lens · notes · bypass | outer (inline) for ×12, inner (inline) for ×6 |

## Bloom studio

A for zone repeats one shared petal function. Per-petal variation comes from the index, a pure hash and a hue. The scene calls the same graph twice with different inputs.

**In the graph**

- `ring` is a for zone. Its rail has `i ∈ (range petals)` plus the captured `petals` and `seed`; its strip has 12 petal thumbnails.
- `u` and `wobble` show sparklines across the 12 iterations. `leaf` is a call to the shared `petal` function; double-click it to edit the definition.
- Clicking a petal in the viewport selects `ring` and probes that petal’s iteration.
- The scene calls `(ref flower :petals 7 :seed 2)`: the same graph with overridden inputs.

**An implementation must show**

- 12 tagged primitives plus the heart; tags `flower/ring` = 0‥11.
- `(ref flower :petals 7)` does not overwrite the records of the base evaluation.
- Editing `petal` changes both flowers; Make unique affects one.

```ocaml
open Prismel

module Bloom = [%workspace {|
(workspace bloom_studio

  (defn half :context value [(x : float)]
    (* x 0.5))

  (defmacro twice [x]
    (+ x x))

  (defn petal :context sop [(length : float 1.0) (width : float 0.3)]
    (sop/transform (sop/circle :radius 0.5 :segments 28)
                   :scale [width length 1]
                   :translate [0 (half length) 0]))

  (graph flower :context sop [(petals : int 12) (seed : int 7)]
    (let* [ring (for [i (range petals)]
                  (let* [u (/ i petals)
                         wobble (* 0.35 (value/rand seed i))
                         leaf (petal :length (+ 0.9 wobble) :width 0.26)
                         tint (sop/set_color leaf
                                             :color (value/hsv (+ 0.05 (* u 0.12)) 0.55 0.92))]
                    (sop/transform tint :rotate (* u 360))))
           bloom (sop/merge ring)
           heart (sop/circle :radius 0.16)
           result (sop/merge bloom (sop/set_color heart :color "#6b7650"))]
      result))

  (graph scene :context scene
    (let* [main (scene/object (ref flower) :color "#d69f61")
           accent (scene/object (ref flower :petals 7 :seed 2)
                                :color "#6fa6a1"
                                :at [2.3 -0.9 0]
                                :scale 0.5)
           composed (scene/merge main accent)]
      composed))

  (graph world :context world
    (world/layer (ref scene) :name "Bloom study"))

  (graph settings :context settings
    (let* [fps 60
           seed 42
           config (settings/config :fps fps :seed seed :exposure (twice 0.5))]
      config)))
|}]
(* generated:
   Bloom.Flower.inputs = { petals : int; seed : int }
   Bloom.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Bloom.program
```

## Sunflower

Phyllotaxis: each seed sits at a golden-angle turn and a square-root radius. The r and a nodes show all 240 values as a sparkline. The golden-angle conversion never changes and is flagged as hoistable.

**In the graph**

- 240 iterations; the `r` sparkline is a square-root curve and `a` is linear.
- `turn` does not depend on `i`: it carries the ↥ badge, and hoisting it leaves the result unchanged.

**An implementation must show**

- Hoisting is output-identical (byte-compare the geometry).
- The strip samples 240 cells down to what fits, and the probe maps back to the true index.

```ocaml
open Prismel

module Sunflower = [%workspace {|
(workspace sunflower

  (graph sunflower :context sop [(seeds : int 240) (spread : float 0.062)]
    (let* [seeds_each (for [i (range seeds)]
                        (let* [turn (/ (* 137.508 pi) 180)
                               r (* spread (sqrt i))
                               a (* i turn)
                               size (+ 0.012 (* 0.022 (/ i seeds)))]
                          (sop/circle :radius size
                                      :segments 8
                                      :center (value/polar r a))))
           head (sop/merge seeds_each)]
      head)))
|}]
(* generated:
   Sunflower.Sunflower.inputs = { seeds : int; spread : float }
   Sunflower.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Sunflower.program
```

## Tunnel

fold carries a value from one iteration to the next. Each step shrinks and turns everything so far, then adds the frame again. The strip shows the state after every step.

**In the graph**

- A fold zone: rail `shape ⟲ from frame`, a dashed feedback line, and strip cells showing the state after each step.
- Selecting the zone overlays the state at the probe in the viewport.

**An implementation must show**

- Zero steps return `frame`.
- The accumulator type is checked: a body returning a number is `E_ACC_TYPE`.

```ocaml
open Prismel

module Tunnel = [%workspace {|
(workspace tunnel

  (graph tunnel :context sop [(steps : int 18) (turn : float 5.0)]
    (let* [frame (sop/box :size [2 2 0])
           nested (fold [shape frame]
                        [i (range steps)]
                    (sop/merge frame (sop/transform shape :scale 0.88 :rotate turn)))]
      nested)))
|}]
(* generated:
   Tunnel.Tunnel.inputs = { steps : int; turn : float }
   Tunnel.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Tunnel.program
```

## Fractal tree

An iterated function system. Every step puts two scaled, rotated copies of the whole tree on top of the trunk, so step n holds 2ⁿ⁺¹−1 branches. A bounded fold replaces recursion, which the language forbids.

**In the graph**

- A fold whose body is a scope (`up`, `left`, `right`). Step n holds 2ⁿ⁺¹−1 branches.
- `up` is loop-invariant.

**An implementation must show**

- Growth is bounded by the primitive limit, with a diagnostic that names `crown`.
- Recursion `(defn tree … (tree …))` is rejected, and the message suggests fold.

```ocaml
open Prismel

module Tree = [%workspace {|
(workspace tree

  (graph tree :context sop [(depth : int 7) (spread : float 24.0) (shrink : float 0.7)]
    (let* [trunk (sop/line :length 1 :angle 90)
           crown (fold [tree trunk]
                       [level (range depth)]
                   (let* [up [0 1 0]
                          left (sop/transform tree
                                              :scale shrink
                                              :rotate spread
                                              :translate up)
                          right (sop/transform tree
                                               :scale shrink
                                               :rotate (- 0 spread)
                                               :translate up)]
                     (sop/merge trunk left right)))]
      crown)))
|}]
(* generated:
   Tree.Tree.inputs = { depth : int; spread : float; shrink : float }
   Tree.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Tree.program
```

## Square wave

A loop inside an expression. y is a Fourier sum folded into a Σ chip. Unfold it with ƒ and it becomes a sum zone inside the for zone. Time t moves the phase; press play in the viewport.

**In the graph**

- `y` holds a Σ chip inside the `pts` for zone. Unfolding it creates a sum zone nested in the for zone: 800 evaluations over 160 runs.
- With `t`, the viewport can play; the Σ probe follows the outer probe.

**An implementation must show**

- Nested probe semantics: the inner strip shows the 5 terms at the outer `j`.
- Fold (ƒ) on the sum zone restores the original chip text exactly.

```ocaml
open Prismel

module Wave = [%workspace {|
(workspace wave

  (graph wave :context sop [(harmonics : int 5) (samples : int 160)]
    (let* [pts (for [j (range samples)]
                 (let* [x (* (/ j samples) 6.2832)
                        y (* 0.7
                             (sum [k (range harmonics)]
                               (/ (sin (* (+ x t) (+ (* 2 k) 1))) (+ (* 2 k) 1))))]
                   [(- (/ x 3.1416) 1) y 0]))
           curve (sop/poly_path pts)]
      curve)))
|}]
(* generated:
   Wave.Wave.inputs = { harmonics : int; samples : int }
   Wave.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Wave.program
```

## Ten print

Two clauses in one for make a grid: x and y form a product, 64 iterations. A pure hash picks each diagonal. The if node counts how often each branch ran.

**In the graph**

- Two clauses make one zone of 64 iterations (x × y, y fastest).
- `coin` is a Bool sparkline; `angle` and `lift` show `then a · else b` branch counts.

**An implementation must show**

- Product order is row-major.
- `(value/rand seed x y)` is identical across runs and domain counts.

```ocaml
open Prismel

module Tiles = [%workspace {|
(workspace tiles

  (graph tiles :context sop [(cells : int 8) (seed : int 3)]
    (let* [size (/ 2.0 cells)
           cells_each (for [x (range cells)
                            y (range cells)]
                        (let* [coin (< (value/rand seed x y) 0.5)
                               angle (if coin 45 -45)
                               lift (if coin 0 size)
                               stroke (sop/line :length (* size 1.4142)
                                                :angle angle)
                               ink (sop/set_color stroke
                                                  :color (if coin "#285f77" "#b0680f"))]
                          (sop/transform ink
                                         :translate [(- (* x size) 1) (- (+ (* y size) lift) 1) 0])))
           pattern (sop/merge cells_each)]
      pattern)))
|}]
(* generated:
   Tiles.Tiles.inputs = { cells : int; seed : int }
   Tiles.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Tiles.program
```

## Facade

Geometry groups are names that flow with geometry. group_bounds and group_random create them; set_color and blast read them, and the editor draws a named link from creator to reader. Each window is grouped by its floor with a computed name, (str "floor_" f); the floor to hide is one bound name wired into blast. marked is a nested let* scope.

**In the graph**

- `windows` is a 6 × 5 product zone.
- `marked` is a named scope (dashed) around two group writers.
- Dotted `▦ attic` and `▦ lit` links run from writers to readers; a misspelled reader shows `?`.

**An implementation must show**

- `W_UNKNOWN_GROUP` for `:group "atic"`.
- Renaming `marked` keeps its inner names private.

```ocaml
open Prismel

module Facade = [%workspace {|
(workspace facade

  (graph facade :context sop [(floors : int 6) (bays : int 5) (hide : int 2)]
    (let* [wall (sop/box :size [2.2 3.3 0] :center [0 1.55 0])
           windows (for [f (range floors)
                         b (range bays)]
                     (sop/group_bounds (sop/box :size [0.24 0.3 0]
                                                :center [(- (* b 0.4) 0.8) (+ 0.4 (* f 0.48)) 0])
                                       :name (str "floor_" f)
                                       :min [-9 -9 -1]
                                       :max [9 9 1]))
           glass (sop/merge windows)
           marked (let* [top (sop/group_bounds glass
                                               :name "attic"
                                               :min [-2 2.5 -1]
                                               :max [2 4 1])
                         odd (sop/group_random top :name "lit" :ratio 0.35 :seed 4)]
                    odd)
           lit (sop/set_color marked :color "#f5cf4f" :group "lit")
           open (sop/blast lit :group "attic")
           gone (str "floor_" hide)
           closed (sop/blast open :group gone)
           result (sop/merge wall closed)]
      result)))
|}]
(* generated:
   Facade.Facade.inputs = { floors : int; bays : int; hide : int }
   Facade.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Facade.program
```

## Variations

Graphs take typed inputs, and (ref garden :seed s) calls one like a function. The editor graph itself loops: four viewports, one per seed. Panels made by a loop have no binding of their own, so their headers point back to the loop.

**In the graph**

- Graph inputs on `garden` and `scene`.
- The editor graph loops: four viewports from one for inside `ui/tile`. Their headers say *from a loop* and link to `sheet`.

**An implementation must show**

- Cached `(ref scene :seed s)` evaluations, one per distinct input value.
- Panel focus survives a count change from 4 to 6 (keyed by index).

```ocaml
open Prismel

module Variations = [%workspace {|
(workspace variations

  (graph garden :context sop [(seed : int 1) (count : int 40)]
    (let* [bed (sop/circle :radius 1 :segments 48)
           spots (sop/scatter bed :count count :seed seed)
           dot (sop/circle :radius 0.06 :segments 10)
           dots (sop/copy_to_points dot spots)
           result (sop/merge bed dots)]
      result))

  (graph scene :context scene [(seed : int 1)]
    (scene/object (ref garden :seed seed) :color "#3b7d4e"))

  (graph editor :context editor
    (let* [sheet (ui/tile (for [s (range 4)]
                            (ui/viewport (ref scene :seed (+ s 1)))))
           network (ui/graph)
           code (ui/lisp)
           left (ui/split-at "vertical" 0.58 network code)
           outline (ui/outline)
           right (ui/split-at "horizontal" 0.5 left sheet)
           panels (ui/split-at "horizontal" 0.13 outline right)
           shell (ui/workspace panels)]
      shell)))
|}]
(* generated:
   Variations.Garden.inputs = { seed : int; count : int }
   Variations.Scene.inputs = { seed : int }
   Variations.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Variations.program
```

## Garland

Functions are values. bead and leaf are local λ zones whose strips show every call they received. ring is a shared defn that takes a function as an input. filter, sort-by and reduce work on the list of sizes, and the viewport maps each bead back to the call that made it.

**In the graph**

- size, bead and leaf are λ zones. Each strip shows every call the function received; probing bead shows r and k for that call.
- sizes, big, ordered and total are map, filter, sort-by and reduce cards with a diamond f row; big reports how many sizes it kept.
- ring is a shared defn whose make input is a function; wreath passes leaf into it.
- Clicking a bead in the viewport selects bead and probes the call that drew it.

**An implementation must show**

- A function value that escapes (returned, stored in a list or record, passed through ref) is E_FN_ESCAPES.
- Calls are recorded per function with a call index, and viewport provenance lands on (function, call).

```ocaml
open Prismel

module Garland = [%workspace {|
(workspace garland

  (defn ring :context sop [(n : int 8) (radius : float 1.0) (make : fn)]
    (sop/merge (map (fn [i]
                      (sop/transform (make i)
                                     :rotate (* (/ i n) 360)
                                     :translate (value/polar radius (* (/ i n) 6.2832))))
                    (range n))))

  (graph garland :context sop [(count : int 14) (seed : int 5)]
    (let* [size (fn [i] (+ 0.05 (* 0.11 (value/rand seed i))))
           sizes (map size (range count))
           big (filter (fn [s] (> s 0.09)) sizes)
           ordered (sort-by (fn [s] (- 0 s)) big)
           total (reduce + 0 big)
           ; one bead per kept size, largest first
           bead (fn [r k]
                  (sop/transform (sop/circle :radius r :segments 18)
                                 :translate [(- (* k 0.26) 1.3) -1.7 0]))
           beads (map bead ordered (range (count ordered)))
           leaf (fn [i]
                  (sop/transform (sop/circle :radius 0.5 :segments 20)
                                 :scale [0.14 (+ 0.3 (* 0.02 i)) 1]))
           wreath (ring :n count :radius 0.95 :make leaf)
           heart (sop/circle :radius (* 0.25 total) :segments 32)
           result (sop/merge wreath (sop/merge beads) heart)]
      result)))
|}]
(* generated:
   Garland.Garland.inputs = { count : int; seed : int }
   Garland.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Garland.program
```

## Kit of parts

window returns several named values; its node spills one output per field. [left mid right] destructures a list literal you edit item by item. The tower is a fold whose accumulator is a record, so it carries a shape and a height at once. case and cond pick colours and parts; str builds a label.

**In the graph**

- window returns values, so big and small spill frame, pane and area as output rows; panes reads big.pane by wire.
- widths is a list card: scrub, reorder and extend items; [left mid right] splits it into three outputs.
- tower is a fold whose accumulator is a record, {:shape … :y …}, destructured with {:keys [shape y]} each step.
- style is a λ wrapping case; part is a cond with a required else; label builds text with str.

**An implementation must show**

- Destructuring a list that is too short names the pattern and the length.
- A record fits where a subset of its fields is expected.

```ocaml
open Prismel

module Kit = [%workspace {|
(workspace kit

  (defn window :context sop [(w : float 0.3) (h : float 0.4)]
    (let* [frame (sop/box :size [w h 0])
           pane (sop/box :size [(* w 0.8) (* h 0.8) 0])]
      (values :frame frame :pane pane :area (* w h))))

  (graph kit :context sop [(floors : int 5)]
    (let* [widths (list 0.3 0.45 0.3)
           [left mid right] widths
           big (window :w mid :h 0.5)
           small (window :w left)
           style (fn [f] (case (mod f 3) 0 "#b0680f" 1 "#285f77" :else "#6b50ae"))
           tower (fold [st {:shape (sop/box :size [0.01 0.01 0]) :y 0.0}]
                       [f (range floors)]
                   (let* [{:keys [shape y]} st
                          part (cond
                                 (= f 0) big.frame
                                 (= f (- floors 1)) small.pane
                                 :else small.frame)
                          unit (sop/set_color part :color (style f))
                          placed (sop/transform unit :translate [0 y 0])]
                     {:shape (sop/merge shape placed) :y (+ y 0.55)}))
           label (str "floors " floors " · area " big.area)
           panes (sop/transform big.pane :translate [0.75 0 0])]
      (sop/merge tower.shape panes))))
|}]
(* generated:
   Kit.Kit.inputs = { floors : int }
   Kit.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Kit.program
```

## Rosette

radial is a macro: a template with holes. Its first hole is a name the caller chooses (k), so the body can use the index. wobble introduces a fresh name (step#) that can never collide with yours. Press ⤵ on a call to step through its expansion. soft is bypassed with ^:bypass; notes are comments that survive every edit.

**In the graph**

- outer and inner are ◆ macro calls; k and j are binder holes shown as pills.
- ⤵ opens the expansion lens; its steps go from the call to the fully expanded for loop.
- soft carries ^:bypass (a B flag and striped title); notes sit on outer and soft.
- Make macro (M) on a selection offers its literals as holes.

**An implementation must show**

- wobble’s step# expands to a fresh name at every use, so two uses never collide.
- A template that names a caller’s variable directly is rejected as capture.

```ocaml
open Prismel

module Rosette = [%workspace {|
(workspace rosette

  (defmacro radial [i n body]
    `(sop/merge (for [~i (range ~n)]
                  (sop/transform ~body :rotate (* (/ ~i ~n) 360)))))

  (defmacro wobble [x amt seed]
    `(let* [step# (- (value/rand ~seed) 0.5)] (+ ~x (* ~amt step#))))

  (graph rosette :context sop [(petals : int 12)]
    (let* [
           ; the outer ring of petals
           outer (radial k
                         petals
                         (sop/transform (sop/circle :radius 0.5 :segments 24)
                                        :scale [0.2 (wobble 0.9 0.4 k) 1]
                                        :translate [0 0.9 0]))
           inner (radial j 6 (sop/circle :radius 0.12 :center [0 0.35 0]))
           ; switch the bypass off to smooth the inner ring
           soft ^:bypass (sop/subdivide inner :iterations 2)
           rose (sop/merge outer soft)]
      rose)))
|}]
(* generated:
   Rosette.Rosette.inputs = { petals : int }
   Rosette.program : Prismel_workspace.Program.t *)

let () = Prismel_editor.Workspace.run Rosette.program
```
