/* Case studies: reference workspaces for sketches. Each is plain Lisp the study checks and runs. */
(function (root) {
'use strict';
// Each case's program is the canonical text in ../cases/<key>.lisp (single source, shared with the OCaml tests).
// Under node it is read from disk; build.cjs injects CASE_SOURCES for the browser page.
const load = key => (typeof require === 'function' ? require('fs').readFileSync(require('path').join(__dirname, '..', 'cases', key + '.lisp'), 'utf8') : root.CASE_SOURCES[key]).replace(/\n$/, '');
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
 lisp: load('bloom')},
{key: 'sunflower', title: 'Sunflower', tag: 'for · sparklines · invariants', focus: ['sunflower', 'sunflower/seeds_each/r'],
 teaches: 'Phyllotaxis: each seed sits at a golden-angle turn and a square-root radius. The r and a nodes show all 240 values as a sparkline. The golden-angle conversion never changes and is flagged as hoistable.',
 lisp: load('sunflower')},
{key: 'tunnel', title:'Gyroscope', tag: 'fold · feedback', focus:['rings', 'rings/nested'],
 teaches:'fold carries a value from one iteration to the next. Each step shrinks and turns everything so far, then adds the ring again, so 18 steps nest 19 rings. The iteration selector steps through the state after each step.',
 lisp: load('tunnel')},
{key: 'tree', title: 'Fractal tree', tag: 'fold · doubling · scope', focus: ['tree', 'tree/crown'],
 teaches:'An iterated function system in 3D. Every step puts three scaled, tilted copies of the whole tree on top of the trunk, turned a third of a circle apart, so step n holds (3ⁿ⁺¹−1)/2 branches. A bounded fold replaces recursion, which the language forbids.',
 lisp: load('tree')},
{key: 'wave', title: 'Square wave', tag: 'Σ in an expression · nested loops · t', focus:['wave', 'wave/strands/pts/y'],
 teaches:'Loops three deep. y is a Fourier sum folded into a Σ chip inside a for over samples, inside a for over rows; each row is a tube offset in phase. Unfold the Σ with ƒ and it becomes a sum zone. Time t moves the phase; press play in the viewport.',
 lisp: load('wave')},
{key: 'orrery', title: 'Orrery', tag: 't · live and cached · recook', focus:['orrery', 'orrery/moons_each'],
 teaches:'Time t is a live input. A node that depends on it carries a ◷ t mark and recooks every frame while the viewport plays; everything else, like the displaced plinth, cooks once and stays cached. Loop counts cannot depend on t (E_TIME_COUNT), so the unrolled network keeps its shape and only parameters change. Press play, scrub t, or drag a moon count while it runs.',
 lisp: load('orrery')},
{key: 'tiles', title: 'Ten print', tag: 'nested for · if · rand', focus:['tiles', 'tiles/cells_each/coin'],
 teaches:"Two clauses in one for make a grid: x and z form a product, 64 iterations. A pure hash picks each wall's diagonal, so the walls form a maze. The if nodes count how often each branch ran.",
 lisp: load('tiles')},
{key: 'facade', title: 'Facade', tag: 'groups · named scope', focus: ['facade', 'facade/marked'],
 teaches: 'Geometry groups are names that flow with geometry. group_bounds and group_random create them; set_color and blast read them, and the editor draws a named link from creator to reader. Each window is grouped by its floor with a computed name, (str "floor_" f); the floor to hide is one bound name wired into blast. marked is a nested let* scope.',
 lisp: load('facade')},
{key: 'variations', title: 'Variations', tag: 'graph inputs · loops in the editor', focus: ['editor', 'editor/sheet'],
 teaches: 'Graphs take typed inputs, and (ref garden :seed s) calls one like a function. The editor graph itself loops: four viewports, one per seed. Panels made by a loop have no binding of their own, so their headers point back to the loop.',
 lisp: load('variations')},
{key:'garland',title:'Garland',tag:'λ functions · map · filter · reduce · sort-by',focus:['garland','garland/bead'],
 teaches:'Functions are values. bead and leaf are local λ zones whose strips show every call they received. ring is a shared defn that takes a function as an input. filter, sort-by and reduce work on the list of sizes, and the viewport maps each bead back to the call that made it.',
 lisp: load('garland')},
{key:'kit',title:'Kit of parts',tag:'records · values · destructuring · lists · cond · case · str',focus:['kit','kit/tower'],
 teaches:'window returns several named values; its node spills one output per field. [left mid right] destructures a list literal you edit item by item. The tower is a fold whose accumulator is a record, so it carries a shape and a height at once. case and cond pick colours and parts; str builds a label.',
 lisp: load('kit')},
{key:'rosette',title:'Rosette',tag:'hygienic macros · expansion lens · notes · bypass',focus:['rosette','rosette/outer'],
 teaches:'radial is a macro: a template with holes. Its first hole is a name the caller chooses (k), so the body can use the index. wobble introduces a fresh name (step#) that can never collide with yours. Press ⤵ on a call to step through its expansion. soft is bypassed with ^:bypass; notes are comments that survive every edit.',
 lisp: load('rosette')}
];
const API = {CASES, EDITOR};
if (typeof module !== 'undefined') module.exports = API; else root.Cases = API;
})(typeof window !== 'undefined' ? window : globalThis);
