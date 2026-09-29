/* Case studies: reference workspaces for sketches. Each is plain Lisp the study checks and runs. */
(function (root) {
'use strict';
const EDITOR = `(graph editor :context editor
    (let* [outline (ui/outline)
           network (ui/graph)
           preview (ui/viewport (ref scene))
           inspector (ui/inspector)
           code (ui/lisp)
           lower (ui/split-at "vertical" 0.46 inspector code)
           side (ui/split-at "vertical" 0.4 preview lower)
           main (ui/split-at "horizontal" 0.66 network side)
           panels (ui/split-at "horizontal" 0.13 outline main)
           shell (ui/workspace panels)]
      shell))`;
const CASES = [
{key: 'bloom', title: 'Bloom studio', tag: 'for · function · six contexts', focus: ['flower', 'flower/ring'],
 teaches: 'A for zone repeats one shared petal function. Per-petal variation comes from the index, a pure hash and a hue. The scene calls the same graph twice with different inputs.',
 lisp: `(workspace bloom_studio
  ; A petal is one shared function. The flower repeats it with for.
  (defn half :context value [(x : float)] (* x 0.5))
  (defmacro twice [x] (+ x x))
  (defn petal :context sop [(length : float 1.0) (width : float 0.3)]
    (sop/transform (sop/circle :radius 0.5 :segments 28)
                   :scale [width length 1]
                   :translate [0 (half length) 0]))
  (graph flower :context sop [(petals : int 12) (seed : int 7)]
    (let* [ring (for [i (range petals)]
                  (let* [u (/ i petals)
                         wobble (* 0.35 (value/rand seed i))
                         leaf (petal :length (+ 0.9 wobble) :width 0.26)
                         tint (sop/set_color leaf :color (value/hsv (+ 0.05 (* u 0.12)) 0.55 0.92))]
                    (sop/transform tint :rotate (* u 360))))
           bloom (sop/merge ring)
           heart (sop/circle :radius 0.16)
           result (sop/merge bloom (sop/set_color heart :color "#6b7650"))]
      result))
  (graph scene :context scene
    (let* [main (scene/object (ref flower) :color "#d69f61")
           accent (scene/object (ref flower :petals 7 :seed 2) :color "#6fa6a1" :at [2.3 -0.9 0] :scale 0.5)
           composed (scene/merge main accent)]
      composed))
  (graph world :context world
    (world/layer (ref scene) :name "Bloom study"))
  (graph settings :context settings
    (let* [fps 60
           seed 42
           config (settings/config :fps fps :seed seed :exposure (twice 0.5))]
      config))
  ${EDITOR})`},
{key: 'sunflower', title: 'Sunflower', tag: 'for · sparklines · invariants', focus: ['sunflower', 'sunflower/seeds_each/r'],
 teaches: 'Phyllotaxis: each seed sits at a golden-angle turn and a square-root radius. The r and a nodes show all 240 values as a sparkline. The golden-angle conversion never changes and is flagged as hoistable.',
 lisp: `(workspace sunflower
  (graph sunflower :context sop [(seeds : int 240) (spread : float 0.062)]
    (let* [seeds_each (for [i (range seeds)]
                        (let* [turn (/ (* 137.508 pi) 180)
                               r (* spread (sqrt i))
                               a (* i turn)
                               size (+ 0.012 (* 0.022 (/ i seeds)))]
                          (sop/circle :radius size :segments 8 :center (value/polar r a))))
           head (sop/merge seeds_each)]
      head)))`},
{key: 'tunnel', title: 'Tunnel', tag: 'fold · feedback', focus: ['tunnel', 'tunnel/nested'],
 teaches: 'fold carries a value from one iteration to the next. Each step shrinks and turns everything so far, then adds the frame again. The strip shows the state after every step.',
 lisp: `(workspace tunnel
  (graph tunnel :context sop [(steps : int 18) (turn : float 5.0)]
    (let* [frame (sop/box :size [2 2 0])
           nested (fold [shape frame]
                        [i (range steps)]
                    (sop/merge frame (sop/transform shape :scale 0.88 :rotate turn)))]
      nested)))`},
{key: 'tree', title: 'Fractal tree', tag: 'fold · doubling · scope', focus: ['tree', 'tree/crown'],
 teaches: 'An iterated function system. Every step puts two scaled, rotated copies of the whole tree on top of the trunk, so step n holds 2ⁿ⁺¹−1 branches. A bounded fold replaces recursion, which the language forbids.',
 lisp: `(workspace tree
  (graph tree :context sop [(depth : int 7) (spread : float 24.0) (shrink : float 0.7)]
    (let* [trunk (sop/line :length 1 :angle 90)
           crown (fold [tree trunk]
                       [level (range depth)]
                   (let* [up [0 1 0]
                          left (sop/transform tree :scale shrink :rotate spread :translate up)
                          right (sop/transform tree :scale shrink :rotate (- 0 spread) :translate up)]
                     (sop/merge trunk left right)))]
      crown)))`},
{key: 'wave', title: 'Square wave', tag: 'Σ in an expression · nested loops · t', focus: ['wave', 'wave/pts/y'],
 teaches: 'A loop inside an expression. y is a Fourier sum folded into a Σ chip. Unfold it with ƒ and it becomes a sum zone inside the for zone. Time t moves the phase; press play in the viewport.',
 lisp: `(workspace wave
  (graph wave :context sop [(harmonics : int 5) (samples : int 160)]
    (let* [pts (for [j (range samples)]
                 (let* [x (* (/ j samples) 6.2832)
                        y (* 0.7 (sum [k (range harmonics)]
                                   (/ (sin (* (+ x t) (+ (* 2 k) 1))) (+ (* 2 k) 1))))]
                   [(- (/ x 3.1416) 1) y 0]))
           curve (sop/poly_path pts)]
      curve)))`},
{key: 'tiles', title: 'Ten print', tag: 'nested for · if · rand', focus: ['tiles', 'tiles/cells_each/coin'],
 teaches: 'Two clauses in one for make a grid: x and y form a product, 64 iterations. A pure hash picks each diagonal. The if node counts how often each branch ran.',
 lisp: `(workspace tiles
  (graph tiles :context sop [(cells : int 8) (seed : int 3)]
    (let* [size (/ 2.0 cells)
           cells_each (for [x (range cells) y (range cells)]
                        (let* [coin (< (value/rand seed x y) 0.5)
                               angle (if coin 45 -45)
                               lift (if coin 0 size)
                               stroke (sop/line :length (* size 1.4142) :angle angle)
                               ink (sop/set_color stroke :color (if coin "#285f77" "#b0680f"))]
                          (sop/transform ink :translate [(- (* x size) 1) (- (+ (* y size) lift) 1) 0])))
           pattern (sop/merge cells_each)]
      pattern)))`},
{key: 'facade', title: 'Facade', tag: 'groups · named scope', focus: ['facade', 'facade/marked'],
 teaches: 'Geometry groups are names that flow with geometry. group_bounds and group_random create them; set_color and blast read them, and the editor draws a named link from creator to reader. Each window is grouped by its floor with a computed name, (str "floor_" f); the floor to hide is one bound name wired into blast. marked is a nested let* scope.',
 lisp: `(workspace facade
  (graph facade :context sop [(floors : int 6) (bays : int 5) (hide : int 2)]
    (let* [wall (sop/box :size [2.2 3.3 0] :center [0 1.55 0])
           windows (for [f (range floors) b (range bays)]
                     (sop/group_bounds (sop/box :size [0.24 0.3 0]
                                                :center [(- (* b 0.4) 0.8) (+ 0.4 (* f 0.48)) 0])
                                       :name (str "floor_" f) :min [-9 -9 -1] :max [9 9 1]))
           glass (sop/merge windows)
           marked (let* [top (sop/group_bounds glass :name "attic" :min [-2 2.5 -1] :max [2 4 1])
                         odd (sop/group_random top :name "lit" :ratio 0.35 :seed 4)]
                    odd)
           lit (sop/set_color marked :color "#f5cf4f" :group "lit")
           open (sop/blast lit :group "attic")
           gone (str "floor_" hide)
           closed (sop/blast open :group gone)
           result (sop/merge wall closed)]
      result)))`},
{key: 'variations', title: 'Variations', tag: 'graph inputs · loops in the editor', focus: ['editor', 'editor/sheet'],
 teaches: 'Graphs take typed inputs, and (ref garden :seed s) calls one like a function. The editor graph itself loops: four viewports, one per seed. Panels made by a loop have no binding of their own, so their headers point back to the loop.',
 lisp: `(workspace variations
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
      shell)))`},
{key:'garland',title:'Garland',tag:'λ functions · map · filter · reduce · sort-by',focus:['garland','garland/bead'],
 teaches:'Functions are values. bead and leaf are local λ zones whose strips show every call they received. ring is a shared defn that takes a function as an input. filter, sort-by and reduce work on the list of sizes, and the viewport maps each bead back to the call that made it.',
 lisp:`(workspace garland
  ; ring is a higher-order function: it takes the shape maker as an input.
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
           bead (fn [r k] (sop/transform (sop/circle :radius r :segments 18)
                                         :translate [(- (* k 0.26) 1.3) -1.7 0]))
           beads (map bead ordered (range (count ordered)))
           leaf (fn [i] (sop/transform (sop/circle :radius 0.5 :segments 20) :scale [0.14 (+ 0.3 (* 0.02 i)) 1]))
           wreath (ring :n count :radius 0.95 :make leaf)
           heart (sop/circle :radius (* 0.25 total) :segments 32)
           result (sop/merge wreath (sop/merge beads) heart)]
      result)))`},
{key:'kit',title:'Kit of parts',tag:'records · values · destructuring · lists · cond · case · str',focus:['kit','kit/tower'],
 teaches:'window returns several named values; its node spills one output per field. [left mid right] destructures a list literal you edit item by item. The tower is a fold whose accumulator is a record, so it carries a shape and a height at once. case and cond pick colours and parts; str builds a label.',
 lisp:`(workspace kit
  ; window returns several values: a record with named fields.
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
                          part (cond (= f 0) big.frame
                                     (= f (- floors 1)) small.pane
                                     :else small.frame)
                          unit (sop/set_color part :color (style f))
                          placed (sop/transform unit :translate [0 y 0])]
                     {:shape (sop/merge shape placed) :y (+ y 0.55)}))
           label (str "floors " floors " · area " big.area)
           panes (sop/transform big.pane :translate [0.75 0 0])]
      (sop/merge tower.shape panes))))`},
{key:'rosette',title:'Rosette',tag:'hygienic macros · expansion lens · notes · bypass',focus:['rosette','rosette/outer'],
 teaches:'radial is a macro: a template with holes. Its first hole is a name the caller chooses (k), so the body can use the index. wobble introduces a fresh name (step#) that can never collide with yours. Press ⤵ on a call to step through its expansion. soft is bypassed with ^:bypass; notes are comments that survive every edit.',
 lisp:`(workspace rosette
  ; radial repeats a shape n times around the origin.
  ; The caller names the index, so the body can read it.
  (defmacro radial [i n body]
    \`(sop/merge (for [~i (range ~n)]
                  (sop/transform ~body :rotate (* (/ ~i ~n) 360)))))
  ; wobble adds a pure random offset; step# is fresh at every use.
  (defmacro wobble [x amt seed]
    \`(let* [step# (- (value/rand ~seed) 0.5)]
       (+ ~x (* ~amt step#))))
  (graph rosette :context sop [(petals : int 12)]
    (let* [; the outer ring of petals
           outer (radial k petals
                   (sop/transform (sop/circle :radius 0.5 :segments 24)
                                  :scale [0.2 (wobble 0.9 0.4 k) 1]
                                  :translate [0 0.9 0]))
           inner (radial j 6 (sop/circle :radius 0.12 :center [0 0.35 0]))
           ; switch the bypass off to smooth the inner ring
           soft ^:bypass (sop/subdivide inner :iterations 2)
           rose (sop/merge outer soft)]
      rose)))`}
];
const API = {CASES, EDITOR};
if (typeof module !== 'undefined') module.exports = API; else root.Cases = API;
})(typeof window !== 'undefined' ? window : globalThis);
