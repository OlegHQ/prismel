// Model checks for the workspace study. Node standard library only:
// node specification/workspace/prototype/check.cjs
const M = require('./model.js'), {CASES} = require('./cases.js');
let fail = 0;
const t = (name, f) => { try { f(); console.log('ok  ', name); } catch (e) { fail++; console.log('FAIL', name, '·', e.message); } };
const bad = (src, re) => { try { M.compile(M.read(src)); } catch (e) { if (!re.test(e.message)) throw Error('wrong error: ' + e.message); return; } throw Error('accepted'); };
const val = src => { const p = M.compile(M.read(src)); return p.cache.get('g').d; };
const W = b => `(workspace w (graph g :context sop ${b}))`;
const V = b => `(workspace w (graph g :context value ${b}))`;
for (const c of CASES) t('case ' + c.key + ' checks, runs and round-trips', () => {
  const s = M.print(M.read(c.lisp)); M.compile(M.read(s));
  if (M.print(M.read(s)) !== s) throw Error('canonical print is not stable');
});
t('shadowing is an error', () => bad(W('(let* [a 1 b (for [a (range 3)] (sop/circle))] (sop/merge b))'), /shadows/));
t('fold body must match the accumulator', () => bad(W('(fold [g (sop/circle)] [i (range 3)] 1.0)'), /accumulator type/));
t('for iterates lists only', () => bad(W('(sop/merge (for [i 3] (sop/circle)))'), /iterates a list/));
t('iteration bound names the zone', () => bad(W('(sop/merge (for [i (range 5000)] (sop/circle)))'), /4,096/));
t('recursion is rejected, fold suggested', () => bad('(workspace w (defn f :context sop [(x : float)] (f x)) (graph g :context sop (f 1)))', /Use fold/));
t('both if branches are typed', () => bad(W('(if (< 1 2) (sop/circle) 3)'), /Both branches/));
t('values cannot leave through an unbound name', () => bad(W('(let* [a (for [i (range 2)] (sop/circle))] (sop/transform (sop/merge a) :rotate i))'), /not bound/));
t('sum', () => { if (val(V('(sum [k (range 4)] (* k 2))')) !== 12) throw Error(); });
t('sum of nothing is 0', () => { if (val(V('(sum [k (range 0)] 1.5)')) !== 0) throw Error(); });
t('fold', () => { if (val(V('(fold [a 1] [i (range 5)] (* a 2))')) !== 32) throw Error(); });
t('fold of nothing is its initial value', () => { if (val(V('(fold [a 7] [i (range 0)] (* a 2))')) !== 7) throw Error(); });
t('scan collects each step', () => { if (val(V('(let* [xs (scan [a 1] [i (range 3)] (+ a i))] (count xs))')) !== 3) throw Error(); });
t('product is row-major, last clause fastest', () => { const p = M.compile(M.read(V('(let* [z (for [x (range 2) y (range 3)] (+ (* x 10) y))] (count z))'))); const r = p.records.get('g/z')[0].v.d; if (r.join() !== '0,1,2,10,11,12') throw Error(r); });
t('later clauses read earlier names', () => { if (val(V('(let* [z (for [x (range 4) y (range x)] y)] (count z))')) !== 6) throw Error(); });
t('graph inputs and ref overrides', () => { const p = M.compile(M.read('(workspace w (graph a :context value [(n : int 2)] (* n 3)) (graph b :context value (+ (ref a) (ref a :n 5))))')); if (p.cache.get('b').d !== 21) throw Error(); });
t('unknown ref input', () => bad('(workspace w (graph a :context value [(n : int 2)] n) (graph b :context value (ref a :m 1)))', /no input :m/));
t('graph inputs need defaults', () => bad('(workspace w (graph a :context value [(n : int)] n))', /needs a default/));
t('rand is a pure hash', () => { const a = val(V('(value/rand 3 4 5)')), b = val(V('(value/rand 3 4 5)')); if (a !== b || a < 0 || a >= 1) throw Error(a); });
t('per-iteration records carry their index', () => { const p = M.compile(M.read(CASES[0].lisp)); const r = p.records.get('flower/ring/u'); if (r.length !== 12 || r[3].it.join() !== '3') throw Error(); });
t('loops tag what they make', () => { const p = M.compile(M.read(CASES[0].lisp)); if (!p.cache.get('flower').d.prims.some(q => q.tags['flower/ring'] === 5)) throw Error(); });
t('2.0 stays a float', () => { if (!M.print(M.read('(workspace w (graph g :context value 2.0))')).includes('2.0')) throw Error(); });
t('only the taken branch runs', () => { if (val(V('(if (< 1 2) 1 (count (range 9999)))')) !== 1) throw Error(); });

// ---- helpers for the extended language
const eq = (a, b) => { const A = JSON.stringify(a), B = JSON.stringify(b); if (A !== B) throw Error(`got ${A}, want ${B}`); };
const prog = src => M.compile(M.read(src));
const bound = (src, name) => prog(src).records.get('g/' + name)[0].v; // first recorded value of a top-level binding of g
const is = (src, want) => eq(val(src), want);

// 1. function values
t('fn: let-bound function is called positionally', () => is(V('(let* [f (fn [a b] (+ a b))] (f 1 2))'), 3));
t('fn: annotated parameters coerce', () => eq(bound(V('(let* [f (fn [(a : float) b] (* a b)) r (f 1 2)] 1)'), 'r'), {t: 'float', d: 2}));
t('fn: closures capture the lexical environment', () => is(V('(let* [k 10 f (fn [x] (+ x k))] (f 1))'), 11));
t('fn: arity is checked', () => bad(V('(let* [f (fn [a b] a)] (f 1))'), /takes 2 arguments; got 1/));
t('fn: annotated type is checked statically', () => bad(V('(let* [f (fn [(a : float)] a)] (if false (f "x") 1))'), /expected float, got text/));
t('fn: a local function wins over an operator of the same name', () => is(V('(let* [min (fn [a b] (+ a b))] (min 1 2))'), 3));
t('fn: a function cannot see its own name', () => bad(V('(let* [f (fn [x] (f x))] (f 1))'), /Unknown operator|not bound/));
t('fn: calls are iteration frames with per-call records', () => {
  const p = prog(V('(let* [f (fn [a] (let* [s (* a 2)] (+ s 1))) x (f 5) y (sum [i (range 3)] (f i))] (+ x y))'));
  const z = p.zones.get('g/f');
  eq([z.kind, z.count, z.vars, z.bodyType], ['fn', 4, ['a'], 'int']);
  eq(z.items.map(r => [r.it, r.v.d]), [[[0], 11], [[0, 1], 1], [[1, 2], 3], [[2, 3], 5]]);
  eq(z.args.map(r => r.v.map(v => v.d)), [[5], [0], [1], [2]]);
  eq(p.records.get('g/f/:a').map(r => r.v.d), [5, 0, 1, 2]);
  eq(p.records.get('g/f/s')[3], {it: [2, 3], v: {t: 'int', d: 4}});
  eq([p.types.get('g/f/s'), p.types.get('g/f/@result'), p.types.get('g/f')], ['int', 'int', 'fn']);
});
t('fn: inline functions are recorded at path~fn', () => { const p = prog(V('(let* [xs (map (fn [x] (* x 2)) (list 1 2))] (count xs))')); eq(p.records.get('g/xs~fn/:x').map(r => r.v.d), [1, 2]); eq(p.zones.get('g/xs~fn').count, 2); });
t('fn: map is typed statically through the function body', () => { const p = prog(W('(let* [cs (map (fn [x] (sop/circle :radius x)) (list 1 2))] (sop/merge cs))')); eq([p.types.get('g/cs'), p.types.get('g/cs~fn/@result'), p.types.get('g/cs~fn/:x')], ['list:geometry', 'geometry', 'int']); });
t('fn: map over a let-bound fn tags shapes with the call index', () => { const p = prog(W('(let* [mk (fn [r] (sop/circle :radius r :segments 4)) cs (map mk (list 0.1 0.2 0.3))] (sop/merge cs))')); eq(p.cache.get('g').d.prims.map(q => q.tags['g/mk']), [0, 1, 2]); });
t('fn: escaping as a graph result is an error', () => bad(V('(let* [f (fn [x] x)] f)'), /cannot be stored or returned/));
t('fn: escaping into a list is an error', () => bad(V('(let* [f (fn [x] x) l (list f)] 1)'), /cannot be stored or returned/));
t('fn: escaping into a record is an error', () => bad(V('(let* [f (fn [x] x) r {:f f}] 1)'), /cannot be stored or returned/));
t('fn: escaping as a fold accumulator is an error', () => bad(V('(let* [f (fn [x] x)] (fold [a f] [i (range 2)] 1))'), /cannot be stored or returned/));
t('fn: escaping from a function body or HOF is an error', () => bad(V('(count (map (fn [x] (fn [y] y)) (list 1)))'), /cannot be stored or returned/));
t('fn: escaping through a ref input is an error', () => bad('(workspace w (graph a :context value [(n : int 2)] n) (graph g :context value (let* [f (fn [x] x)] (ref a :n f))))', /cannot be stored or returned/));
t('fn: escaping as a defn result is an error', () => bad('(workspace w (defn h :context value [(k : fn)] k) (graph g :context value 1))', /cannot be stored or returned/));
t('fn: graph inputs cannot be functions', () => bad('(workspace w (graph g :context value [(k : fn)] 1))', /cannot be stored or returned/));
t('fn: defn and operator names are function values', () => is('(workspace w (defn twice :context value [(x : float)] (* x 2)) (graph g :context value (+ (reduce + 0 (map twice (list 1 2 3))) (first (map sin (list 0))))))', 12));
t('fn: a macro is not a function value', () => bad('(workspace w (defmacro dbl [x] (+ x x)) (graph g :context value (count (map dbl (list 1)))))', /macro is not a function value/));
t('fn: user HOF with a fn-typed defn input', () => {
  const R = '(defn ring :context sop [(n : int 8) (make : fn)] (sop/merge (map make (range n))))';
  const p = prog(`(workspace w ${R} (defn dot :context sop [(i : int)] (sop/circle :radius (* 0.1 (+ i 1)) :segments 5)) (graph g :context sop (sop/merge (ring :n 3 :make dot) (let* [mk (fn [i] (sop/box))] (ring :n 2 :make mk)))))`);
  eq(p.cache.get('g').d.prims.length, 15); eq(p.zones.get('g~/mk').count, 2);
});
t('fn: defn inputs typed as lists and records', () => is('(workspace w (defn tot :context value [(xs : (list float)) (r : {:k float})] (* r.k (reduce + 0 xs))) (graph g :context value (tot (list 1 2) {:k 2 :extra 1})))', 6));
t('fn: defn recursion through a function value is rejected', () => bad('(workspace w (defn app :context value [(f : fn) (x : float)] (f f x)) (graph g :context value (app app 1)))', /Recursive call/));
t('hof: map zips up to three lists to the shortest', () => eq(bound(V('(let* [z (map (fn [a b c] (+ a (+ b c))) (list 1 2 3) (list 10 20) (list 100 200 300))] 1)'), 'z'), {t: 'list:int', d: [111, 222]}));
t('hof: filter', () => eq(bound(V('(let* [z (filter (fn [x] (> x 1)) (list 1 2 3))] 1)'), 'z').d, [2, 3]));
t('hof: filter predicate must return bool', () => bad(V('(count (filter (fn [x] "no") (list 1)))'), /predicate returns bool/));
t('hof: reduce checks the accumulator type', () => bad(V('(reduce (fn [a x] "s") 0 (list 1))'), /accumulator type/));
t('hof: sort-by is stable on a numeric key', () => eq(bound(V('(let* [z (sort-by (fn [p] (first p)) (list (list 2 0) (list 1 1) (list 2 2) (list 1 3)))] 1)'), 'z').d, [[1, 1], [1, 3], [2, 0], [2, 2]]));
t('hof: map of an empty list keeps its static type', () => eq(bound(W('(let* [z (map (fn [x] (sop/circle :radius x)) (list))] (sop/merge z))'), 'z'), {t: 'list:geometry', d: []}));

// 2. lists and destructuring
t('list: int and float promote to float', () => eq(bound(V('(let* [z (list 1 2.5)] 1)'), 'z'), {t: 'list:float', d: [1, 2.5]}));
t('list: elements share one type', () => bad(V('(count (list 1 "a"))'), /share one type/));
t('list: (list) is a list of any', () => eq(bound(V('(let* [z (list)] 1)'), 'z').t, 'list:any'));
t('list: first last rest nth concat reverse take drop', () => eq(bound(V('(let* [s (str (first (list 4 5)) (last (list 4 5)) (rest (list 1 2 3)) (nth (list 7 8) 1) (concat (list 1) (list) (list 2 3)) (reverse (list 1 2)) (take 2 (list 1 2 3)) (drop 2 (list 1 2 3)))] 1)'), 's').d, '45[2 3]8[1 2 3][2 1][1 2][3]'));
t('list: nth out of range names index and length', () => bad(V('(nth (list 1 2) 5)'), /index 5 .*length 2/));
t('list: first of an empty list is an error', () => bad(V('(first (list))'), /empty list/));
t('pattern: [a b] in let* records whole and parts', () => { const p = prog(V('(let* [[a b] (list 1 2)] (+ a b))')); eq(p.cache.get('g').d, 3); eq(p.records.get('g/[a b]')[0].v.d, [1, 2]); eq(p.records.get('g/b')[0].v.d, 2); });
t('pattern: [x y z] over a vec3 and {:keys} over a record', () => is(V('(let* [[x y z] [1 2 3] {:keys [a b]} {:a 10 :b 20}] (+ (* x a) (* z b)))'), 70));
t('pattern: too few elements is an error', () => bad(V('(let* [[a b c] (list 1 2)] a)'), /needs 3 elements; the list has 2/));
t('pattern: a missing record field is a static error', () => bad(V('(let* [{:keys [a c]} {:a 1}] a)'), /no field c/));
t('pattern: in zone clauses and fn parameters', () => { const p = prog(V('(let* [f (fn [[a b]] (* a b)) s (sum [[a b] (list (list 1 2) (list 3 4))] (+ (f (list a b)) 0))] s)')); eq(p.cache.get('g').d, 14); eq(p.records.get('g/s/:[a b]')[1].v.d, [3, 4]); eq(p.zones.get('g/s').vars, ['a', 'b']); eq(p.records.get('g/f/:[a b]').length, 2); });
t('pattern: zoneVars reports the pattern and its names', () => { const zv = M.zoneVars(M.read('(for [[a {:keys [b]}] xs i (range 2)] a)')); eq(zv.map(v => [M.print(v.name), v.names]), [['[a {:keys [b]}]', ['a', 'b']], ['i', ['i']]]); });
t('pattern: names must not be reserved words', () => { bad(V('(let* [map 1] map)'), /Invalid binding name map/); bad(V('(let* [[a list] (list 1 2)] a)'), /Invalid binding name list/); });

// 3. records
t('record: literal, dotted access and chains', () => { const p = prog(V('(let* [r {:a 1 :b {:c [1 2 3]}}] (+ r.a r.b.c.y))')); eq(p.cache.get('g').d, 3); eq(p.types.get('g/r'), 'rec{a:int,b:rec{c:vec3}}'); });
t('record: get and assoc', () => is(V('(let* [r {:a 1} s (assoc r :a 5 :c 2)] (+ (get s :a) s.c))'), 7));
t('record: assoc keeps the field type', () => bad(V('(let* [r {:a 1} s (assoc r :a "x")] 1)'), /assoc :a is int; got text/));
t('record: unknown field', () => bad(V('(let* [r {:a 1}] r.b)'), /no field b. Fields: a/));
t('record: values is a record literal', () => eq(bound(V('(let* [r (values :a 1 :b 2.5)] 1)'), 'r'), {t: 'rec{a:int,b:float}', d: {a: 1, b: 2.5}}));
t('record: a record accumulator carries several values', () => is(V('(let* [s (fold [{:keys [a b]} {:a 0 :b 1}] [i (range 10)] {:a b :b (+ a b)})] s.a)'), 55));
t('record: fits is structural and field order does not matter', () => { eq([M.fits('rec{a:int,b:vec3}', 'rec{b:vec3}'), M.fits('rec{b:vec3}', 'rec{a:int,b:vec3}'), M.fits('list:rec{pos:vec3,size:int}', 'list:rec{size:float}')], [true, false, true]); });
t('record: type strings nest', () => { const s = 'list:rec{pos:vec3,kids:list:rec{n:int}}'; eq(M.formatType(M.parseType(s)), s); eq(M.recFields('rec{a:list:rec{x:float},b:int}'), [['a', 'list:rec{x:float}'], ['b', 'int']]); });
t('record: reader makes flagged arrays', () => { const r = M.read('{:a 1 :b [1 2 3]}'); eq([M.isMap(r), r.length, r[3].vector === true], [true, 4, true]); eq(M.print(M.clone(r)), '{:a 1 :b [1 2 3]}'); });

// 4. cond, case, str
t('cond picks the first true arm', () => is(V('(cond (< 2 1) 1 (> 2 1) 2 :else 3)'), 2));
t('cond is lazy at run time', () => is(V('(cond true 1 :else (count (range 9999)))'), 1));
t('cond needs :else', () => bad(V('(cond (< 2 1) 1)'), /final :else/));
t('cond arms must agree', () => bad(V('(cond true 1 :else "a")'), /one type/));
t('case matches literals', () => { is(V('(case 2 1 10 2 20 :else 0)'), 20); is(V('(case 9 1 10 :else 0)'), 0); });
t('case needs :else and literal tests', () => { bad(V('(case 1 1 2)'), /final :else/); bad(V('(let* [k 1] (case 1 k 2 :else 0))'), /literal/); });
t('str formats values', () => eq(bound(V('(let* [s (str "a" 1 2.5 true [1 2 3] 1.23456 (list 1 2) {:a 1} (/ 1 3))] 1)'), 's').d, 'a12.5true[1 2 3]1.2346[1 2]{:a 1}0.3333'));
t('str computes group names', () => eq(val(W('(sop/blast (sop/group_bounds (sop/box) :name (str "floor_" 2)) :group (str "floor_" 2))')).prims.length, 0));

// 5. macros
const RADIAL = '(defmacro radial [i n body] `(sop/merge (for [~i (range ~n)] (sop/transform ~body :rotate (* (/ ~i ~n) 360)))))';
const SWAP = '(defmacro add1 [a] `(let* [t# ~a] (+ t# 1)))';
t('macro: caller symbols may bind; expansion runs at path~for', () => { const p = prog(`(workspace w ${RADIAL} (graph g :context sop (let* [ring (radial k 12 (sop/circle :radius (+ 0.1 (* k 0.01))))] ring)))`); eq(p.cache.get('g').d.prims.length, 12); eq(p.zones.get('g/ring~for').count, 12); eq(p.records.get('g/ring~for/:k').length, 12); });
t('macro: expand is deterministic and fresh names are distinct', () => { const ws = M.read(`(workspace w ${SWAP} (graph g :context value 1))`), c = M.read('(+ (add1 1) (add1 (add1 2)))'); const a = M.print(M.expand(ws, c)); eq(a, M.print(M.expand(ws, c))); eq(a, '(+ (let* [t__1 1] (+ t__1 1)) (let* [t__2 (let* [t__3 2] (+ t__3 1))] (+ t__2 1)))'); });
t('macro: expandOnce steps leftmost-outermost', () => { const ws = M.read(`(workspace w ${SWAP} ${RADIAL} (graph g :context value 1))`), st = {n: 0}; let x = M.read('(radial k 2 (add1 1))'); const s1 = M.expandOnce(ws, x, st); eq(M.print(s1), '(sop/merge (for [k (range 2)] (sop/transform (add1 1) :rotate (* (/ k 2) 360))))'); const s2 = M.expandOnce(ws, s1, st); eq(M.expandOnce(ws, s2, st) === s2, true); eq(M.print(s2), M.print(M.expand(ws, x))); });
t('macro: rest parameters splice', () => is(`(workspace w (defmacro all [& xs] \`(+ 0 (+ ~@xs))) (graph g :context value (all 1 2)))`, 3));
t('macro: free template names would capture', () => bad('(workspace w (defmacro m [x] `(+ ~x y)) (graph g :context value (let* [y 1] (m 2))))', /would capture a name from the call site/));
t('macro: template bindings must be fresh', () => bad('(workspace w (defmacro m [x] `(let* [tmp ~x] tmp)) (graph g :context value (m 2)))', /would capture/));
t('macro: only parameters are unquoted', () => bad('(workspace w (defmacro m [x] `(+ ~x ~(+ 1 2))) (graph g :context value (m 2)))', /macros unquote only their parameters/));
t('macro: expansion depth is limited', () => bad('(workspace w (defmacro m [x] `(m ~x)) (graph g :context value (m 2)))', /32 nested expansions/));
t('macro: expansion size is limited', () => bad(`(workspace w (defmacro d [x] \`(+ ~x ~x)) (graph g :context value ${'(d '.repeat(12)}1${')'.repeat(12)}))`, /5,000 forms/));
t('macro: arity is checked', () => bad(`(workspace w ${RADIAL} (graph g :context sop (radial k 2)))`, /expects 3 arguments; got 2/));
t('macro: legacy value templates still work', () => is('(workspace w (defmacro twice [x] (+ x x)) (graph g :context value (twice 3)))', 6));

// 6. comments and metadata
const NOTED = `; lead
(workspace w
  ; a helper
  (defn f :context value [(x : float)] (* x 2))
  (graph g :context value
    (let* [; first
           a 1
           ; the pattern
           [b c] (list 1 2)
           q (f a)]
      ; result note
      (+ a (+ b (* c q)))))
  ; tail
  )`;
t('notes attach to the next element by name', () => { const x = M.read(NOTED), v = x[3][4][1]; eq([M.getNote(x, 'f'), M.getNote(x, '$lead'), M.getNote(v, 'a'), M.getNote(v, '[b c]'), M.getNote(x[3][4], 2), M.getNote(x, '$end')], ['a helper', 'lead', 'first', 'the pattern', 'result note', 'tail']); });
t('notes survive clone and print stably', () => { const x = M.clone(M.read(NOTED)), s = M.print(x); if (!s.includes('  ; a helper\n  (defn f') || !s.includes('; the pattern\n           [b c]')) throw Error(s); eq(M.print(M.read(s)), s); is(s, 6); });
t('setNote edits and removes notes', () => { const x = M.read(V('(let* [a 1 b 2] b)')), v = x[2][4][1]; M.setNote(v, 'b', 'two\nlines'); const s = M.print(x); if (!s.includes('; two\n') || !s.includes('; lines\n')) throw Error(s); M.setNote(v, 'b', null); eq(M.print(x).includes(';'), false); });
t('bypass passes the first input through', () => { const p = prog(W('(let* [a (sop/circle :segments 5) b ^:bypass (sop/transform a :translate [5 0 0])] b)')); eq(p.cache.get('g').d.prims[0].pts[0][0], 0.5); });
t('bypass prints and clones', () => { const x = M.read(W('(let* [a (sop/circle) b ^:bypass (sop/subdivide a)] b)')); eq(M.clone(x)[2][4][1][3].meta, ['bypass']); if (!M.print(x).includes('b ^:bypass (sop/subdivide a)')) throw Error(M.print(x)); });
t("bypass needs a fitting input", () => { bad(W('(sop/points ^:bypass (sop/point_list (sop/circle)))'), /can't bypass sop\/point_list/); bad(W('^:bypass (sop/circle :radius 2)'), /can't bypass/); });
t('unknown metadata lists ^:bypass', () => bad(W('^:mute (sop/circle)'), /only metadata is \^:bypass/));

// 7. freeSymbols and reserved names
const fs = s => [...M.freeSymbols(M.read(s))].sort();
t('freeSymbols understands fn, patterns, records and quoting', () => {
  eq(fs('(fn [a [b c] (d : float)] (+ a b c d e))'), ['e']);
  eq(fs('(let* [[a b] xs {:keys [c]} r] (+ a b c y))'), ['r', 'xs', 'y']);
  eq(fs('(for [{:keys [p]} ps] (sop/circle :center p.pos :radius {:k q}))'), ['ps', 'q']);
  eq(fs('(let* [f (fn [x] x)] (f (g y)))'), ['g', 'y']);
  eq(fs('(cond a 1 :else (case b 1 c :else 0))'), ['a', 'b', 'c']);
  eq(fs('(quasiquote (+ x (unquote y)))'), ['y']);
  eq(fs('(defmacro m [x] `(+ ~x z))'), []);
});
t('SPECIAL and RESERVED name the new forms', () => { for (const k of ['fn', 'cond', 'case', 'list', 'values', 'quote', 'quasiquote', 'unquote', 'get', 'assoc', 'str', 'map', 'filter', 'reduce', 'sort-by', 'concat']) if (!M.SPECIAL.has(k) || !M.RESERVED.has(k)) throw Error(k); });

// round trip: every new construct, comments and metadata
const ALL = `(workspace kitchen
  ; macros
  ${RADIAL}
  (defmacro all [& xs] \`(sop/merge ~@xs))
  ${SWAP}
  (defmacro twice [x] (+ x x))
  (defn ring :context sop [(n : int 8) (make : fn) (opts : {:scale float :tags (list text)} {:scale 1.0 :tags (list "a")})]
    (sop/transform (sop/merge (map make (range n))) :scale opts.scale))
  (graph g :context sop [(seed : int 3)]
    (let* [; a local function
           petal (fn [(i : int) [w h]]
                   (sop/transform (sop/box :size [w h 0]) :rotate (* i 30)))
           sizes (map (fn [k] (list (+ 0.1 (* k 0.01)) 0.5)) (range 12))
           petals (map petal (range 12) sizes)
           {:keys [a b]} {:a 1 :b (twice 2)}
           [x y z] [a b 3]
           kind (cond (< a 1) "small"
                      (< a 5) "medium"
                      :else "large")
           steps (case seed 1 4 2 8 :else 12)
           order (sort-by (fn [p] (- 0 (nth p 0))) sizes)
           kept (filter (fn [p] (> (first p) 0.12)) (concat (take 3 sizes) (drop 9 sizes) (reverse (rest sizes))))
           total (reduce + 0 (map (fn [p] (last p)) kept))
           name (str "floor_" (add1 steps) "_" kind)
           state (fold [{:keys [n acc]} (values :n 0 :acc 1.0)]
                       [i (range steps)]
                   (assoc {:n (+ n 1) :acc (* acc 0.9)} :acc (get {:acc (* acc 0.9)} :acc)))
           ring2 (radial k 6 (sop/circle :radius (+ 0.1 (* k 0.01))))
           faded ^:bypass (sop/subdivide ring2 :iterations 2)
           shapes (all (sop/merge petals) faded (ring :n 3 :make petal2) (sop/group_bounds (sop/box) :name name))
           ; unused but checked
           spare (count (list))]
      ; the result
      (sop/transform shapes :rotate (* state.acc (* x (+ y (+ z total)))))))
  ; trailing
  )`.replace('(ring :n 3 :make petal2)', '(ring :n 3 :make (fn [i] (sop/circle :radius 0.05)))');
t('round trip: print(read(print(x))) is stable for every new construct', () => {
  const x = M.read(ALL), s = M.print(x);
  eq(M.print(M.read(s)), s);
  eq(M.print(M.clone(M.read(s))), s);
  for (const k of ['; a local function', '^:bypass (sop/subdivide', '`(sop/merge ~@xs)', 't# ~a', '{:keys [a b]}', '(fn [(i : int) [w h]]', '(cond (< a 1) "small"', '; trailing']) if (!s.includes(k)) throw Error('missing ' + k + '\n' + s);
  const p = M.compile(M.read(s)); if (!p.cache.get('g').d.prims.length) throw Error('empty');
  eq(p.types.get('g/state'), 'rec{n:int,acc:float}'); eq(p.records.get('g/[x y z]')[0].v.d, [1, 4, 3]);
});
process.exit(fail ? 1 : 0);
