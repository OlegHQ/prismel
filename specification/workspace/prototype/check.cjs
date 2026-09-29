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
process.exit(fail ? 1 : 0);
