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
    (sop/transform (sop/uv_sphere :radius [(half length) 0.04 width]
                                  :center [(half length) 0 0]
                                  :segments 14 :rings 6)
                   :rotate [0 0 0.35]))
  (graph flower :context sop [(petals : int 12) (seed : int 7)]
    (let* [ring (for [i (range petals)]
                  (let* [u (/ i petals)
                         wobble (* 0.35 (value/rand seed i))
                         leaf (petal :length (+ 0.9 wobble) :width 0.22)
                         tint (sop/set_color leaf :color (value/hsv (+ 0.05 (* u 0.12)) 0.55 0.92))]
                    (sop/transform tint :rotate [0 (* u 6.2832) 0])))
           bloom (sop/merge ring)
           heart (sop/uv_sphere :radius [0.22 0.12 0.22] :center [0 0.05 0])
           result (sop/merge bloom (sop/set_color heart :color "#6b7650"))]
      result))
  (graph scene :context scene
    (let* [main (scene/object (ref flower) :color "#d69f61")
           accent (scene/object (ref flower :petals 7 :seed 2) :color "#6fa6a1" :at [2.2 0 -1.2] :scale 0.55)
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
                               lift (- 0.3 (* 0.3 (* r r)))
                               size (+ 0.012 (* 0.022 (/ i seeds)))]
                          (sop/uv_sphere :radius size :center (value/polar r a lift) :segments 6 :rings 4)))
           head (sop/merge seeds_each)]
      head)))`},
{key: 'tunnel', title:'Gyroscope', tag: 'fold · feedback', focus:['rings', 'rings/nested'],
 teaches:'fold carries a value from one iteration to the next. Each step shrinks and turns everything so far, then adds the ring again, so 18 steps nest 19 rings. The iteration selector steps through the state after each step.',
 lisp: `(workspace rings
  (graph rings :context sop [(steps : int 18) (turn : float 0.18)]
    (let* [frame (sop/torus :major_radius 1 :minor_radius 0.03 :rows 5 :columns 40)
           nested (fold [shape frame]
                        [i (range steps)]
                    (sop/merge frame (sop/transform shape :uniform_scale 0.87 :rotate [turn (* 0.5 turn) 0])))]
      nested)))`},
{key: 'tree', title: 'Fractal tree', tag: 'fold · doubling · scope', focus: ['tree', 'tree/crown'],
 teaches:'An iterated function system in 3D. Every step puts three scaled, tilted copies of the whole tree on top of the trunk, turned a third of a circle apart, so step n holds (3ⁿ⁺¹−1)/2 branches. A bounded fold replaces recursion, which the language forbids.',
 lisp: `(workspace tree
  (graph tree :context sop [(depth : int 5) (spread : float 0.6) (shrink : float 0.62)]
    (let* [trunk (sop/polywire (sop/line :length 1) :radius 0.05 :sides 5)
           crown (fold [tree trunk]
                       [level (range depth)]
                   (let* [up [0 1 0]
                          tilted (sop/transform tree :uniform_scale shrink :rotate [0 0 spread])
                          a (sop/transform tilted :translate up)
                          b (sop/transform tilted :rotate [0 2.094 0] :translate up)
                          c (sop/transform tilted :rotate [0 4.189 0] :translate up)]
                     (sop/merge trunk a b c)))]
      crown)))`},
{key: 'wave', title: 'Square wave', tag: 'Σ in an expression · nested loops · t', focus:['wave', 'wave/strands/pts/y'],
 teaches:'Loops three deep. y is a Fourier sum folded into a Σ chip inside a for over samples, inside a for over rows; each row is a tube offset in phase. Unfold the Σ with ƒ and it becomes a sum zone. Time t moves the phase; press play in the viewport.',
 lisp: `(workspace wave
  (graph wave :context sop [(harmonics : int 5) (samples : int 90) (rows : int 6)]
    (let* [strands (for [row (range rows)]
                     (let* [pts (for [j (range samples)]
                                  (let* [x (* (/ j samples) 6.2832)
                                         y (* 0.5 (sum [k (range harmonics)]
                                                    (/ (sin (* (+ x (+ t (* row 0.4))) (+ (* 2 k) 1))) (+ (* 2 k) 1))))]
                                    [(- (/ x 3.1416) 1) y (- (* row 0.3) 0.75)]))]
                       (sop/polywire (sop/poly_path pts) :radius 0.015 :sides 4)))
           sheet (sop/merge strands)]
      sheet)))`},
{key: 'orrery', title: 'Orrery', tag: 't · live and cached · recook', focus:['orrery', 'orrery/moons_each'],
 teaches:'Time t is a live input. A node that depends on it carries a ◷ t mark and recooks every frame while the viewport plays; everything else, like the displaced plinth, cooks once and stays cached. Loop counts cannot depend on t (E_TIME_COUNT), so the unrolled network keeps its shape and only parameters change. Press play, scrub t, or drag a moon count while it runs.',
 lisp: `(workspace orrery
  (graph orrery :context sop [(rings : int 3) (moons : int 8) (seed : int 5)]
    (let* [; no t here: cooked once and cached while playing
           base (sop/noise_displace (sop/tube :top_radius 1.3 :bottom_radius 1.5 :height 0.12 :columns 40)
                                    :amplitude 0.05 :frequency 3 :seed seed)
           plinth (sop/set_color base :color "#6b7650")
           ; t enters here, and everything downstream of it is live
           spin (* t 0.8)
           pulse (+ 0.28 (* 0.03 (sin (* t 3))))
           sun (sop/uv_sphere :radius pulse :center [0 0.9 0] :segments 16 :rings 10)
           glow (sop/set_color sun :color (value/hsv (+ 0.08 (* 0.03 (sin t))) 0.7 0.95))
           moons_each (for [r (range rings) m (range moons)]
                        (let* [radius (+ 0.6 (* r 0.35))
                               size (+ 0.05 (* 0.025 (value/rand seed r m)))
                               a (+ (* (/ m moons) 6.2832) (/ spin (+ r 1)))
                               bob (* 0.1 (sin (+ (* t 2) (+ m r))))
                               moon (sop/uv_sphere :radius size :center (value/polar radius a (+ 0.9 bob))
                                                   :segments 8 :rings 5)]
                          (sop/set_color moon :color (if (> bob 0) "#d69f61" "#6fa6a1"))))
           orbit (sop/merge moons_each)
           system (sop/merge plinth glow orbit)]
      system)))`},
{key: 'tiles', title: 'Ten print', tag: 'nested for · if · rand', focus:['tiles', 'tiles/cells_each/coin'],
 teaches:"Two clauses in one for make a grid: x and z form a product, 64 iterations. A pure hash picks each wall's diagonal, so the walls form a maze. The if nodes count how often each branch ran.",
 lisp: `(workspace tiles
  (graph tiles :context sop [(cells : int 8) (seed : int 3)]
    (let* [size (/ 2.0 cells)
           cells_each (for [x (range cells) z (range cells)]
                        (let* [coin (< (value/rand seed x z) 0.5)
                               angle (if coin 0.7854 -0.7854)
                               wall (sop/box :size [(* size 1.4142) 0.3 0.05] :rotation [0 angle 0])
                               ink (sop/set_color wall :color (if coin "#285f77" "#b0680f"))]
                          (sop/transform ink :translate [(- (* (+ x 0.5) size) 1) 0.15 (- (* (+ z 0.5) size) 1)])))
           maze (sop/merge cells_each)]
      maze)))`},
{key: 'facade', title: 'Facade', tag: 'groups · named scope', focus: ['facade', 'facade/marked'],
 teaches: 'Geometry groups are names that flow with geometry. group_bounds and group_random create them; set_color and blast read them, and the editor draws a named link from creator to reader. Each window is grouped by its floor with a computed name, (str "floor_" f); the floor to hide is one bound name wired into blast. marked is a nested let* scope.',
 lisp: `(workspace facade
  (graph facade :context sop [(floors : int 6) (bays : int 5) (hide : int 2)]
    (let* [wall (sop/box :size [2.2 3.3 0.6] :center [0 1.65 0])
           windows (for [f (range floors) b (range bays)]
                     (sop/group_bounds (sop/box :size [0.24 0.3 0.06]
                                                :center [(- (* b 0.4) 0.8) (+ 0.4 (* f 0.48)) 0.31])
                                       :name (str "floor_" f) :size [99 99 99]))
           glass (sop/merge windows)
           marked (let* [top (sop/group_bounds glass :name "attic" :center [0 3 0] :size [4 1 4])
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
           dot (sop/uv_sphere :radius 0.06 :segments 8 :rings 4)
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
 lisp: `(workspace garland
  ; ring is a higher-order function: it takes the shape maker as an input.
  (defn ring :context sop [(n : int 8) (radius : float 1.0) (make : fn)]
    (sop/merge (map (fn [i]
                      (let* [a (* (/ i n) 6.2832)]
                        (sop/transform (make i) :rotate [0 (- 0 a) 0] :translate (value/polar radius a))))
                    (range n))))
  (graph garland :context sop [(count : int 14) (seed : int 5)]
    (let* [size (fn [i] (+ 0.05 (* 0.11 (value/rand seed i))))
           sizes (map size (range count))
           big (filter (fn [s] (> s 0.09)) sizes)
           ordered (sort-by (fn [s] (- 0 s)) big)
           total (reduce + 0 big)
           ; one bead per kept size, largest first
           bead (fn [r k] (sop/uv_sphere :radius r :center [(- (* k 0.28) 1.1) r 1.6] :segments 12 :rings 6))
           beads (map bead ordered (range (count ordered)))
           leaf (fn [i] (sop/uv_sphere :radius [0.3 0.05 (+ 0.08 (* 0.004 i))] :segments 10 :rings 5))
           wreath (ring :n count :radius 0.95 :make leaf)
           heart (sop/uv_sphere :radius (* 0.25 total) :center [0 0.1 0])
           result (sop/merge wreath (sop/merge beads) heart)]
      result)))`},
{key:'kit',title:'Kit of parts',tag:'records · values · destructuring · lists · cond · case · str',focus:['kit','kit/tower'],
 teaches:'window returns several named values; its node spills one output per field. [left mid right] destructures a list literal you edit item by item. The tower is a fold whose accumulator is a record, so it carries a shape and a height at once. case and cond pick colours and parts; str builds a label.',
 lisp: `(workspace kit
  ; window returns several values: a record with named fields.
  (defn window :context sop [(w : float 0.3) (h : float 0.4)]
    (let* [frame (sop/box :size [w h 0.3])
           pane (sop/box :size [(* w 0.8) (* h 0.8) 0.34])]
      (values :frame frame :pane pane :area (* w h))))
  (graph kit :context sop [(floors : int 5)]
    (let* [widths (list 0.3 0.45 0.3)
           [left mid right] widths
           big (window :w mid :h 0.5)
           small (window :w left)
           style (fn [f] (case (mod f 3) 0 "#b0680f" 1 "#285f77" :else "#6b50ae"))
           tower (fold [st {:shape (sop/box :size [0.01 0.01 0.01]) :y 0.0}]
                       [f (range floors)]
                   (let* [{:keys [shape y]} st
                          part (cond (= f 0) big.frame
                                     (= f (- floors 1)) small.pane
                                     :else small.frame)
                          unit (sop/set_color part :color (style f))
                          placed (sop/transform unit :translate [0 y 0] :rotate [0 (* f 0.3) 0])]
                     {:shape (sop/merge shape placed) :y (+ y 0.55)}))
           label (str "floors " floors " · area " big.area)
           panes (sop/transform big.pane :translate [0.75 0 0])]
      (sop/merge tower.shape panes))))`},
{key:'rosette',title:'Rosette',tag:'hygienic macros · expansion lens · notes · bypass',focus:['rosette','rosette/outer'],
 teaches:'radial is a macro: a template with holes. Its first hole is a name the caller chooses (k), so the body can use the index. wobble introduces a fresh name (step#) that can never collide with yours. Press ⤵ on a call to step through its expansion. soft is bypassed with ^:bypass; notes are comments that survive every edit.',
 lisp: `(workspace rosette
  ; radial repeats a shape n times around the vertical axis.
  ; The caller names the index, so the body can read it.
  (defmacro radial [i n body]
    \`(sop/merge (for [~i (range ~n)]
                  (sop/transform ~body :rotate [0 (* (/ ~i ~n) 6.2832) 0]))))
  ; wobble adds a pure random offset; step# is fresh at every use.
  (defmacro wobble [x amt seed]
    \`(let* [step# (- (value/rand ~seed) 0.5)]
       (+ ~x (* ~amt step#))))
  (graph rosette :context sop [(petals : int 12)]
    (let* [; the outer ring of petals
           outer (radial k petals
                   (sop/uv_sphere :radius [0.45 0.04 0.12] :center [0.5 0 0]
                                  :rotation [0 0 (wobble 0.35 0.4 k)] :segments 12 :rings 6))
           inner (radial j 6 (sop/uv_sphere :radius 0.1 :center [0.25 0.12 0] :segments 8 :rings 4))
           ; switch the bypass off to smooth the inner ring
           soft ^:bypass (sop/subdivide inner :iterations 1)
           rose (sop/merge outer soft)]
      rose)))`}
];
const API = {CASES, EDITOR};
if (typeof module !== 'undefined') module.exports = API; else root.Cases = API;
})(typeof window !== 'undefined' ? window : globalThis);
