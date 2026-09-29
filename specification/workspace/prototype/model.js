/* Design artifact only: a small checked Lisp interpreter for the workspace study.
   Not product code, not a renderer. Geometry is a 2D illustration kernel. */
(function (root) {
'use strict';
const isL = Array.isArray;
const vec = xs => Object.assign(xs, {vector: true});
const str = value => ({text: value});
const isStr = x => !!x && typeof x === 'object' && !isL(x) && 'text' in x;
const isKw = x => typeof x === 'string' && x[0] === ':' && x.length > 1;
function clone(x) { return isL(x) ? (x.vector ? vec(x.map(clone)) : x.map(clone)) : isStr(x) ? {...x} : x; }

/* ---------------- reader ---------------- */
function read(source) {
  if (source.length > 120000) throw Error('Document exceeds the study limit of 120,000 characters.');
  const tokens = []; let i = 0, line = 1;
  while (i < source.length) {
    const c = source[i];
    if (c === '\n') { line++; i++; continue; }
    if (/\s/.test(c)) { i++; continue; }
    if (c === ';') { while (i < source.length && source[i] !== '\n') i++; continue; }
    const start = i;
    if ('()[]'.includes(c)) { tokens.push({v: c, start, line}); i++; continue; }
    if (c === '"') {
      i++; let escaped = false;
      while (i < source.length) { const d = source[i++]; if (d === '"' && !escaped) break; escaped = d === '\\' && !escaped; }
      try { tokens.push({v: str(JSON.parse(source.slice(start, i))), start, line}); }
      catch { throw Error(`Line ${line}: invalid string.`); }
      continue;
    }
    while (i < source.length && !/[\s()[\];"]/.test(source[i])) i++;
    const raw = source.slice(start, i);
    tokens.push({v: /^-?(?:\d+\.?\d*|\.\d+)$/.test(raw) ? Number(raw) : raw, start, line, raw});
  }
  let at = 0;
  function take(depth) {
    if (depth > 120) throw Error('Nesting exceeds 120 levels.');
    const token = tokens[at++]; if (!token) throw Error('Unexpected end of source.');
    const x = token.v;
    if (x === '(' || x === '[') {
      const out = [], close = x === '(' ? ')' : ']';
      while (tokens[at]?.v !== close) {
        if (!tokens[at]) throw Error(`Line ${token.line}: this "${x}" is never closed.`);
        if (tokens[at].v === ')' || tokens[at].v === ']') throw Error(`Line ${tokens[at].line}: expected "${close}" to close the "${x}" on line ${token.line}, found "${tokens[at].v}".`);
        out.push(take(depth + 1));
      }
      at++; return x === '[' ? vec(out) : out;
    }
    if (x === ')' || x === ']') throw Error(`Line ${token.line}: unexpected "${x}".`);
    if (typeof x === 'number' && token.raw.includes('.') && Number.isInteger(x)) return {float: x}; // 2.0 stays a float
    return x;
  }
  const result = take(0); if (at !== tokens.length) throw Error('Expected one workspace form.');
  return result;
}
const isNum = x => typeof x === 'number' || (x && typeof x === 'object' && 'float' in x);
const numOf = x => typeof x === 'number' ? x : x.float;
const numIsInt = x => typeof x === 'number' && Number.isInteger(x);
const mkNum = (v, asFloat) => asFloat && Number.isInteger(v) ? {float: v} : v;

/* ---------------- printer ---------------- */
function fmtNum(x) { const v = numOf(x); if (typeof x === 'object') return Number.isInteger(v) ? v.toFixed(1) : String(+v.toFixed(6)); return String(Number.isInteger(v) ? v : +v.toFixed(6)); }
function atom(x) { if (isNum(x)) return fmtNum(x); if (isStr(x)) return JSON.stringify(x.text); return String(x); }
const M1 = '\u0001', M2 = '\u0002';
const vis = s => s.replace(/[\u0001\u0002]/g, '').length;
function isMark(mark, x, parent, i) { return mark && ((mark.obj !== undefined && mark.obj === x && isL(x)) || (mark.parent && mark.parent === parent && mark.idx === i)); }
function flat(x, mark, parent, i) {
  const m = isMark(mark, x, parent, i);
  let s;
  if (!isL(x)) s = atom(x);
  else if (x.vector) s = '[' + x.map((y, j) => flat(y, mark, x, j)).join(' ') + ']';
  else s = '(' + x.map((y, j) => flat(y, mark, x, j)).join(' ') + ')';
  return m ? M1 + s + M2 : s;
}
const WIDTH = 84;
const BIND_FORMS = new Set(['let*', 'for', 'sum']);
function pp(x, ind = 0, mark, parent, i) {
  const f = flat(x, mark, parent, i);
  if (!isL(x) || x.vector) return f;
  const m = isMark(mark, x, parent, i), wrap = s => m ? M1 + s + M2 : s;
  const head = x[0], sp = n => ' '.repeat(n);
  if (head === 'workspace') return wrap(`(workspace ${x[1]}` + x.slice(2).map((y, j) => '\n\n' + sp(ind + 2) + pp(y, ind + 2, mark, x, j + 2)).join('') + ')');
  if ((vis(f) + ind <= WIDTH || (vis(f) <= 44 && !BIND_FORMS.has(head) && head !== 'fold' && head !== 'scan')) && !['graph', 'defn', 'defmacro'].includes(head) && !(head === 'let*' && x[1]?.length > 2)) return f;
  const bvec = (v, col) => { // aligned binding vector
    const rows = []; for (let k = 0; k < v.length; k += 2) {
      const name = flat(v[k], mark, v, k), pad = col + 1 + vis(name) + 1;
      rows.push(name + ' ' + pp(v[k + 1], pad, mark, v, k + 1));
    }
    const s = '[' + rows.join('\n' + sp(col + 1)) + ']';
    return isMark(mark, v, x, x.indexOf(v)) ? M1 + s + M2 : s;
  };
  if (BIND_FORMS.has(head)) {
    const col = ind + head.length + 2;
    return wrap(`(${head} ` + bvec(x[1], col) + '\n' + sp(ind + 2) + pp(x[2], ind + 2, mark, x, 2) + ')');
  }
  if (head === 'fold' || head === 'scan') {
    const col = ind + head.length + 2;
    return wrap(`(${head} ` + bvec(x[1], col) + '\n' + sp(col) + bvec(x[2], col) + '\n' + sp(ind + 2) + pp(x[3], ind + 2, mark, x, 3) + ')');
  }
  if (head === 'if') return wrap(`(if ${pp(x[1], ind + 4, mark, x, 1)}\n${sp(ind + 4)}${pp(x[2], ind + 4, mark, x, 2)}\n${sp(ind + 4)}${pp(x[3], ind + 4, mark, x, 3)})`);
  if (head === 'graph' || head === 'defn') {
    const hasP = x[4]?.vector && x.length === 6;
    const hdr = `(${head} ${x[1]} ${x[2]} ${x[3]}` + (hasP ? ' ' + flat(x[4], mark, x, 4) : '');
    return wrap(hdr + '\n' + sp(ind + 2) + pp(x[x.length - 1], ind + 2, mark, x, x.length - 1) + ')');
  }
  if (head === 'defmacro') return wrap(`(defmacro ${x[1]} ${flat(x[2])}\n${sp(ind + 2)}${pp(x[3], ind + 2, mark, x, 3)})`);
  // call: first positional on the head line, keyword pairs aligned below
  const units = []; for (let k = 1; k < x.length; k++) { if (isKw(x[k]) && k + 1 < x.length) { units.push([k, k + 1]); k++; } else units.push([k]); }
  let col = ind + 1 + String(head).length + 1; if (col > ind + 18) col = ind + 4;
  const u = us => us.length === 2 ? x[us[0]] + ' ' + pp(x[us[1]], col + x[us[0]].length + 1, mark, x, us[1]) : pp(x[us[0]], col, mark, x, us[0]);
  if (!units.length) return f;
  const first = u(units[0]).replace(/\n/g, '\n');
  return wrap('(' + head + ' ' + (col === ind + 4 && units.length > 1 && vis(first) > 30 ? '\n' + sp(col) : '') + units.map(u).join('\n' + sp(col)) + ')');
}
const print = (x, mark) => pp(x, 0, mark).replace(/[\u0001\u0002]/g, '');
const printMarked = (x, mark) => pp(x, 0, mark);

/* ---------------- types and values ---------------- */
const val = (t, d) => ({t, d});
const listOf = t => 'list:' + t;
const elemOf = t => t && t.startsWith('list:') ? t.slice(5) : null;
const NUM = new Set(['int', 'float']);
function fits(have, want) {
  if (!have || !want || have === 'any' || want === 'any') return true;
  if (have === want) return true;
  if (NUM.has(have) && (NUM.has(want) || want === 'bool')) return true;
  if (have === 'bool' && NUM.has(want)) return true;
  if (want === 'color') return have === 'text' || have === 'vec3';
  if (want === 'vec3' && NUM.has(have)) return true;
  if (elemOf(want) && elemOf(have)) return fits(elemOf(have), elemOf(want));
  return false;
}
function coerce(v, want) {
  if (v.d === undefined) return v;
  if (want === 'int' && v.t === 'float') return val('int', Math.round(v.d));
  if (want === 'float' && v.t === 'int') return val('float', v.d);
  if (want === 'bool' && NUM.has(v.t)) return val('bool', v.d !== 0);
  if (NUM.has(want) && v.t === 'bool') return val(want, v.d ? 1 : 0);
  if (want === 'vec3' && NUM.has(v.t)) return val('vec3', [v.d, v.d, v.d]);
  return v;
}

/* ---------------- 2D illustration kernel ---------------- */
let uidN = 0;
const prim = (pts, closed, extra) => ({pts, closed, color: null, groups: [], tags: {}, uid: ++uidN, ...extra});
const geo = prims => ({prims});
const EMPTY = geo([]);
function hash(...xs) { let h = 0x9e3779b9 | 0; for (const x of xs) { const k = Math.floor(Number(x) * 1000003) | 0; h = Math.imul(h ^ k, 0x85ebca6b); h ^= h >>> 13; h = Math.imul(h, 0xc2b2ae35); h ^= h >>> 16; } return ((h >>> 0) % 1000000) / 1000000; }
function noise2(x, y, seed) {
  const xi = Math.floor(x), yi = Math.floor(y), xf = x - xi, yf = y - yi, s = t => t * t * (3 - 2 * t);
  const a = hash(seed, xi, yi), b = hash(seed, xi + 1, yi), c = hash(seed, xi, yi + 1), d = hash(seed, xi + 1, yi + 1);
  const u = s(xf), v = s(yf); return (a * (1 - u) + b * u) * (1 - v) + (c * (1 - u) + d * u) * v - 0.5;
}
const mapPts = (g, fn) => geo(g.prims.map(p => ({...p, pts: p.pts.map(fn)})));
function bbox(g) { let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity; g.prims.forEach(p => p.pts.forEach(([x, y]) => { x0 = Math.min(x0, x); y0 = Math.min(y0, y); x1 = Math.max(x1, x); y1 = Math.max(y1, y); })); return {x0, y0, x1, y1}; }
function centroid(p) { let x = 0, y = 0; p.pts.forEach(q => { x += q[0]; y += q[1]; }); return [x / p.pts.length, y / p.pts.length]; }
function inside(pt, poly) { let c = false; for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) { const [xi, yi] = poly[i], [xj, yj] = poly[j]; if ((yi > pt[1]) !== (yj > pt[1]) && pt[0] < (xj - xi) * (pt[1] - yi) / (yj - yi) + xi) c = !c; } return c; }
function chaikin(p) {
  const P = p.pts, n = P.length; if (n < 3) return p; const out = [];
  const m = p.closed ? n : n - 1;
  if (!p.closed) out.push(P[0]);
  for (let i = 0; i < m; i++) { const a = P[i], b = P[(i + 1) % n]; out.push([a[0] * .75 + b[0] * .25, a[1] * .75 + b[1] * .25], [a[0] * .25 + b[0] * .75, a[1] * .25 + b[1] * .75]); }
  if (!p.closed) out.push(P[n - 1]);
  return {...p, pts: out};
}
const toHex = c => typeof c === 'string' ? c : '#' + c.map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, '0')).join('');
function hsv(h, s, v) { h = ((h % 1) + 1) % 1; const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s); return [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i % 6]; }
const V2 = v => [v[0], v[1]];
function countPrims(g) { if (g.prims.length > 20000) throw Error('Geometry exceeds 20,000 primitives in this study.'); return g; }

/* ---------------- operator catalog ----------------
   pos: positional slots, rest: variadic slot type (lists splice), kw: [name, type, default, [soft min, max]]. */
const OPS = {};
function op(name, ctx, spec) { OPS[name] = {name, ctx, pos: [], kw: [], ...spec}; }
const num2 = (f, name) => ({pos: [['a', 'float'], ['b', 'float']], out: ts => ts.includes('vec3') ? 'vec3' : name !== '/' && ts.every(t => t === 'int') ? 'int' : 'float',
  fn: ([a, b]) => { const A = Array.isArray(a), B = Array.isArray(b); if (A || B) { const aa = A ? a : [a, a, a], bb = B ? b : [b, b, b]; return aa.map((x, i) => f(x, bb[i])); } return f(a, b); }, anyNum: true});
op('+', 'value', num2((a, b) => a + b, '+'));
op('-', 'value', num2((a, b) => a - b, '-'));
op('*', 'value', num2((a, b) => a * b, '*'));
op('/', 'value', num2((a, b) => b === 0 ? 0 : a / b, '/'));
op('mod', 'value', num2((a, b) => b === 0 ? 0 : ((a % b) + b) % b, 'mod'));
op('pow', 'value', {...num2((a, b) => Math.pow(Math.abs(a), b), '/')});
op('min', 'value', num2(Math.min, 'min'));
op('max', 'value', num2(Math.max, 'max'));
for (const [k, f] of Object.entries({sin: Math.sin, cos: Math.cos, abs: Math.abs, floor: Math.floor, sqrt: x => Math.sqrt(Math.abs(x))}))
  op(k, 'value', {pos: [['x', 'float']], out: ts => k === 'floor' || (k === 'abs' && ts[0] === 'int') ? 'int' : 'float', fn: ([x]) => f(x)});
for (const [k, f] of Object.entries({'<': (a, b) => a < b, '>': (a, b) => a > b, '<=': (a, b) => a <= b, '>=': (a, b) => a >= b, '=': (a, b) => a === b}))
  op(k, 'value', {pos: [['a', 'float'], ['b', 'float']], out: 'bool', fn: ([a, b]) => f(a, b)});
op('and', 'value', {pos: [['a', 'bool'], ['b', 'bool']], out: 'bool', fn: ([a, b]) => a && b});
op('or', 'value', {pos: [['a', 'bool'], ['b', 'bool']], out: 'bool', fn: ([a, b]) => a || b});
op('not', 'value', {pos: [['a', 'bool']], out: 'bool', fn: ([a]) => !a});
op('value/rand', 'value', {rest: 'float', restName: 'key', out: 'float', fn: (_, __, rest) => hash(...rest), doc: 'Pure hash of its keys, in [0, 1). The same keys always give the same number.'});
op('value/hsv', 'value', {pos: [['h', 'float'], ['s', 'float'], ['v', 'float']], out: 'vec3', fn: ([h, s, v]) => hsv(h, s, v)});
op('value/lerp', 'value', {pos: [['a', 'float'], ['b', 'float'], ['u', 'float']], out: ts => ts[0] === 'vec3' || ts[1] === 'vec3' ? 'vec3' : 'float', anyNum: true,
  fn: ([a, b, u]) => Array.isArray(a) || Array.isArray(b) ? [0, 1, 2].map(i => (Array.isArray(a) ? a[i] : a) * (1 - u) + (Array.isArray(b) ? b[i] : b) * u) : a * (1 - u) + b * u});
op('value/polar', 'value', {pos: [['radius', 'float'], ['angle', 'float']], out: 'vec3', fn: ([r, a]) => [r * Math.cos(a), r * Math.sin(a), 0], doc: 'A point at radius and angle (radians).'});
op('range', 'value', {pos: [['count', 'int']], opt: [['end', 'int']], out: 'list:int', fn: ([a, b]) => { const lo = b === undefined ? 0 : a, hi = b === undefined ? a : b; if (hi - lo > 4096) throw Error(`range ${lo}‥${hi} exceeds 4,096 iterations.`); const o = []; for (let k = lo; k < hi; k++) o.push(k); return o; }});
op('linspace', 'value', {pos: [['from', 'float'], ['to', 'float'], ['count', 'int']], out: 'list:float', fn: ([a, b, n]) => { if (n > 4096) throw Error('linspace exceeds 4,096 values.'); const o = []; for (let k = 0; k < n; k++) o.push(n === 1 ? a : a + (b - a) * k / (n - 1)); return o; }});
op('count', 'value', {pos: [['list', 'list:any']], out: 'int', fn: ([xs]) => xs.length});

op('sop/circle', 'sop', {kw: [['radius', 'float', 0.5, [0, 3]], ['segments', 'int', 32, [3, 96]], ['center', 'vec3', [0, 0, 0]]],
  out: 'geometry', fn: (_, k) => { const n = Math.max(3, Math.min(256, k.segments)), c = k.center; return geo([prim(Array.from({length: n}, (_, i) => [c[0] + k.radius * Math.cos(i / n * Math.PI * 2), c[1] + k.radius * Math.sin(i / n * Math.PI * 2)]), true)]); }});
op('sop/box', 'sop', {kw: [['size', 'vec3', [1, 1, 1]], ['center', 'vec3', [0, 0, 0]]], out: 'geometry',
  fn: (_, k) => { const [w, h] = k.size, [cx, cy] = k.center; return geo([prim([[cx - w / 2, cy - h / 2], [cx + w / 2, cy - h / 2], [cx + w / 2, cy + h / 2], [cx - w / 2, cy + h / 2]], true)]); }});
op('sop/line', 'sop', {kw: [['length', 'float', 1, [0, 4]], ['points', 'int', 2, [2, 64]], ['angle', 'float', 90, [-180, 180]]], out: 'geometry',
  fn: (_, k) => { const a = k.angle * Math.PI / 180, n = Math.max(2, Math.min(512, k.points)); return geo([prim(Array.from({length: n}, (_, i) => [Math.cos(a) * k.length * i / (n - 1), Math.sin(a) * k.length * i / (n - 1)]), false)]); }});
op('sop/poly_path', 'sop', {pos: [['points', 'list:vec3']], kw: [['closed', 'bool', false]], out: 'geometry', fn: ([pts], k) => geo(pts.length ? [prim(pts.map(V2), !!k.closed)] : [])});
op('sop/points', 'sop', {pos: [['points', 'list:vec3']], kw: [['size', 'float', 0.03, [0, 0.3]]], out: 'geometry', fn: ([pts], k) => geo(pts.map(p => prim([V2(p)], false, {point: k.size})))});
op('sop/transform', 'sop', {pos: [['input', 'geometry']], kw: [['translate', 'vec3', [0, 0, 0]], ['rotate', 'float', 0, [-180, 180]], ['scale', 'vec3', [1, 1, 1], [0, 3]], ['pivot', 'vec3', [0, 0, 0]]], out: 'geometry',
  fn: ([g], k) => { const a = k.rotate * Math.PI / 180, c = Math.cos(a), s = Math.sin(a), [px, py] = k.pivot, [tx, ty] = k.translate, sc = Array.isArray(k.scale) ? k.scale : [k.scale, k.scale, k.scale];
    return mapPts(g, ([x, y]) => { x = (x - px) * sc[0]; y = (y - py) * sc[1]; return [x * c - y * s + px + tx, x * s + y * c + py + ty]; }); }});
op('sop/merge', 'sop', {rest: 'geometry', restName: 'input', out: 'geometry', fn: (_, __, rest) => countPrims(geo(rest.flatMap(g => g.prims)))});
op('sop/copy_to_points', 'sop', {pos: [['input', 'geometry'], ['target', 'geometry']], out: 'geometry',
  fn: ([g, t]) => countPrims(geo(t.prims.flatMap((tp, k) => { const [x, y] = centroid(tp); return g.prims.map(p => ({...p, pts: p.pts.map(q => [q[0] + x, q[1] + y]), tags: {...p.tags, '#copy': k}})); })))});
op('sop/scatter', 'sop', {pos: [['input', 'geometry']], kw: [['count', 'int', 60, [1, 400]], ['seed', 'int', 0, [0, 100]]], out: 'geometry',
  fn: ([g], k) => { const b = bbox(g), polys = g.prims.filter(p => p.closed), out = []; let tries = 0;
    while (out.length < Math.min(2000, k.count) && tries++ < k.count * 40) { const x = b.x0 + hash(k.seed, tries, 1) * (b.x1 - b.x0), y = b.y0 + hash(k.seed, tries, 2) * (b.y1 - b.y0); if (!polys.length || polys.some(p => inside([x, y], p.pts))) out.push(prim([[x, y]], false, {point: 0.03})); }
    return geo(out); }});
op('sop/set_color', 'sop', {pos: [['input', 'geometry']], kw: [['color', 'color', '#285f77'], ['group', 'groupref', '']], out: 'geometry',
  fn: ([g], k) => geo(g.prims.map(p => !k.group || p.groups.includes(k.group) ? {...p, color: toHex(k.color)} : p))});
op('sop/group_bounds', 'sop', {pos: [['input', 'geometry']], kw: [['name', 'group', 'group1'], ['min', 'vec3', [-1, -1, -1]], ['max', 'vec3', [1, 1, 1]]], out: 'geometry',
  fn: ([g], k) => geo(g.prims.map(p => { const [x, y] = centroid(p); return x >= k.min[0] && x <= k.max[0] && y >= k.min[1] && y <= k.max[1] ? {...p, groups: [...new Set([...p.groups, k.name])]} : p; }))});
op('sop/group_random', 'sop', {pos: [['input', 'geometry']], kw: [['name', 'group', 'group1'], ['ratio', 'float', 0.5, [0, 1]], ['seed', 'int', 0, [0, 100]]], out: 'geometry',
  fn: ([g], k) => geo(g.prims.map((p, i) => hash(k.seed, i, 7) < k.ratio ? {...p, groups: [...new Set([...p.groups, k.name])]} : p))});
op('sop/blast', 'sop', {pos: [['input', 'geometry']], kw: [['group', 'groupref', ''], ['invert', 'bool', false]], out: 'geometry',
  fn: ([g], k) => geo(g.prims.filter(p => p.groups.includes(k.group) === !!k.invert))});
op('sop/subdivide', 'sop', {pos: [['input', 'geometry']], kw: [['iterations', 'int', 1, [0, 4]]], out: 'geometry',
  fn: ([g], k) => { let ps = g.prims; for (let i = 0; i < Math.min(5, k.iterations); i++) ps = ps.map(chaikin); return geo(ps); }});
op('sop/noise_displace', 'sop', {pos: [['input', 'geometry']], kw: [['amp', 'float', 0.1, [0, 1]], ['frequency', 'float', 2, [0, 10]], ['seed', 'int', 0, [0, 100]]], out: 'geometry',
  fn: ([g], k) => mapPts(g, ([x, y]) => [x + k.amp * noise2(x * k.frequency, y * k.frequency, k.seed), y + k.amp * noise2(x * k.frequency + 17, y * k.frequency - 9, k.seed)])});
op('sop/point_list', 'sop', {pos: [['input', 'geometry']], out: 'list:vec3', fn: ([g]) => g.prims.flatMap(p => p.pts.map(q => [q[0], q[1], 0])).slice(0, 4096)});
op('sop/piece_list', 'sop', {pos: [['input', 'geometry']], out: 'list:geometry', fn: ([g]) => g.prims.slice(0, 4096).map(p => geo([p]))});

op('scene/object', 'scene', {pos: [['geometry', 'geometry']], kw: [['color', 'color', '#285f77'], ['at', 'vec3', [0, 0, 0]], ['scale', 'float', 1, [0, 3]]], out: 'scene',
  fn: ([g], k) => ({items: [{geo: g, color: toHex(k.color), at: k.at, scale: k.scale}]})});
op('scene/merge', 'scene', {rest: 'scene', restName: 'scene', out: 'scene', fn: (_, __, rest) => ({items: rest.flatMap(s => s.items)})});
op('world/layer', 'world', {pos: [['scene', 'scene']], kw: [['name', 'text', 'Layer']], out: 'world', fn: ([s], k) => ({scene: s, name: k.name})});
op('settings/config', 'settings', {kw: [['fps', 'int', 60, [1, 240]], ['seed', 'int', 1, [0, 1000]], ['exposure', 'float', 1, [0, 4]], ['background', 'color', '#f4f5f0']], out: 'settings',
  fn: (_, k) => { if (k.fps < 1 || k.fps > 240 || k.exposure < 0 || k.exposure > 4) throw Error('FPS must be 1–240 and exposure 0–4.'); return {...k, background: toHex(k.background)}; }});
const panel = (kind, extra) => ({kind, ...extra});
op('ui/viewport', 'editor', {pos: [['scene', 'scene']], out: 'panel', fn: ([s]) => panel('viewport', {scene: s})});
for (const k of ['graph', 'inspector', 'outline', 'list', 'lisp']) op('ui/' + k, 'editor', {out: 'panel', fn: () => panel(k)});
op('ui/split', 'editor', {pos: [['axis', 'text'], ['first', 'panel'], ['second', 'panel']], out: 'panel', fn: ([axis, a, b]) => { if (!['horizontal', 'vertical'].includes(axis)) throw Error('Split axis is horizontal or vertical.'); return panel('split', {axis, ratio: .5, children: [a, b]}); }});
op('ui/split-at', 'editor', {pos: [['axis', 'text'], ['ratio', 'float'], ['first', 'panel'], ['second', 'panel']], out: 'panel', fn: ([axis, ratio, a, b]) => { if (!['horizontal', 'vertical'].includes(axis)) throw Error('Split axis is horizontal or vertical.'); if (ratio < .1 || ratio > .9) throw Error('Split ratio is 0.1–0.9.'); return panel('split', {axis, ratio, children: [a, b]}); }});
op('ui/tile', 'editor', {rest: 'panel', restName: 'panel', out: 'panel', fn: (_, __, rest) => { if (!rest.length || rest.length > 16) throw Error('A tile holds 1–16 panels.'); return panel('tile', {children: rest}); }});
op('ui/floating', 'editor', {pos: [['panel', 'panel']], out: 'panel', fn: ([p]) => panel('floating', {children: [p]})});
op('ui/workspace', 'editor', {pos: [['root', 'panel']], out: 'editor', fn: ([p]) => ({panel: p})});

const CONTEXTS = {value: 'float', sop: 'geometry', scene: 'scene', world: 'world', settings: 'settings', editor: 'editor'};
const TYPES = new Set(['float', 'int', 'bool', 'text', 'vec3', 'geometry', 'scene', 'world', 'settings', 'panel', 'editor']);
const NAME = /^[a-z][a-z0-9_-]*$/;
const SPECIAL = new Set(['workspace', 'graph', 'defn', 'defmacro', 'let*', 'ref', 'for', 'fold', 'scan', 'sum', 'if', 'values']);
const RESERVED = new Set([...SPECIAL, 't', 'pi', 'true', 'false', 'nil']);
const ZONES = new Set(['for', 'fold', 'scan', 'sum']);

/* ---------------- shape helpers (shared with the editor) ---------------- */
const body = f => f[f.length - 1];
const paramsOf = f => (f[0] === 'graph' || f[0] === 'defn') && f[4]?.vector && f.length === 6 ? f[4] : vec([]);
function bindings(e) { if (!isL(e) || e[0] !== 'let*') return []; const o = []; for (let i = 0; i < e[1].length; i += 2) o.push({name: e[1][i], expr: e[1][i + 1], index: i}); return o; }
/* Split a call into positional and keyword arguments with their list indices. */
function callArgs(x) {
  const pos = [], kw = {}; for (let i = 1; i < x.length; i++) { if (isKw(x[i])) { kw[x[i].slice(1)] = {idx: i + 1, v: x[i + 1]}; i++; } else pos.push({idx: i, v: x[i]}); }
  return {pos, kw};
}
/* Iteration clauses of a zone: [{name, coll, idx:[vectorIndexInZone, indexInVector]}] */
function zoneVars(z) {
  const h = z[0], out = [];
  const add = (vi, role) => { const v = z[vi]; if (!v?.vector) return; for (let k = 0; k < v.length; k += 2) out.push({name: v[k], expr: v[k + 1], role, at: [vi, k + 1]}); };
  if (h === 'fold' || h === 'scan') { add(1, 'acc'); add(2, 'iter'); } else add(1, 'iter');
  return out;
}
const zoneBody = z => z[z.length - 1];
function freeSymbols(x, bound = new Set(), out = new Set()) {
  if (typeof x === 'string') { if (isKw(x) || RESERVED.has(x)) return out; const b = x.split('.')[0]; if (!bound.has(b)) out.add(b); return out; }
  if (!isL(x)) return out;
  if (x.vector) { x.forEach(y => freeSymbols(y, bound, out)); return out; }
  const h = x[0];
  if (h === 'let*') { const b = new Set(bound); for (let i = 0; i < x[1].length; i += 2) { freeSymbols(x[1][i + 1], b, out); b.add(x[1][i]); } freeSymbols(x[2], b, out); return out; }
  if (ZONES.has(h)) { const b = new Set(bound); zoneVars(x).forEach(v => { freeSymbols(v.expr, v.role === 'acc' ? bound : b, out); b.add(v.name); }); freeSymbols(zoneBody(x), b, out); return out; }
  if (h === 'ref') { x.slice(2).forEach(y => freeSymbols(y, bound, out)); return out; }
  x.slice(1).forEach(y => freeSymbols(y, bound, out)); return out;
}

/* ---------------- compiler / evaluator ---------------- */
function compile(ast, opts = {}) {
  const time = opts.time ?? 0;
  if (!isL(ast) || ast[0] !== 'workspace' || !NAME.test(ast[1])) throw Error('Expected (workspace name …).');
  const graphs = new Map(), defs = new Map(), macros = new Map(), all = new Set();
  for (const f of ast.slice(2)) {
    if (!isL(f) || !['graph', 'defn', 'defmacro'].includes(f[0])) throw Error('Workspace children are graph, defn and defmacro forms.');
    if (!NAME.test(f[1]) || RESERVED.has(f[1]) || all.has(f[1]) || OPS[f[1]]) throw Error(`Invalid, reserved or duplicate name: ${f[1]}.`);
    all.add(f[1]);
    if (f[0] === 'defmacro') {
      if (f.length !== 4 || !f[2]?.vector) throw Error(`Invalid macro: ${f[1]}.`);
      const check = x => { if (isL(x)) { if (x.vector || !OPS[x[0]] || OPS[x[0]].ctx !== 'value') throw Error('Study macros contain value operators only; binding macros need hygienic syntax objects.'); x.slice(1).forEach(check); } else if (typeof x === 'string' && !f[2].includes(x)) throw Error(`Free macro identifier: ${x}.`); };
      check(f[3]); macros.set(f[1], f); continue;
    }
    if (f[2] !== ':context' || !CONTEXTS[f[3]] || !(f.length === 5 || (f.length === 6 && f[4]?.vector))) throw Error(`Invalid shape for ${f[1]}: expected (${f[0]} ${f[1]} :context ctx [params] body).`);
    if (f[0] === 'defn' && f.length !== 6) throw Error(`defn ${f[1]} needs a parameter vector.`);
    const used = new Set();
    for (const p of paramsOf(f)) {
      if (!isL(p) || p.length < 3 || p.length > 4 || p[1] !== ':' || !NAME.test(p[0]) || used.has(p[0]) || !TYPES.has(p[2])) throw Error(`Invalid parameter in ${f[1]}. Each is (name : type default?).`);
      if (f[0] === 'graph' && p.length !== 4) throw Error(`Graph input ${p[0]} of ${f[1]} needs a default, so the graph runs on its own.`);
      used.add(p[0]);
    }
    (f[0] === 'graph' ? graphs : defs).set(f[1], f);
  }
  if (!graphs.size) throw Error('A workspace needs at least one graph.');
  const records = new Map(), types = new Map(), zones = new Map(), cache = new Map(), notes = [];
  let steps = 0;
  function rec(E, id, v) {
    if (E.mode === 'static') { if (!types.has(id) || types.get(id) === 'any') types.set(id, v.t); return; }
    if (!E.record) return;
    let a = records.get(id); if (!a) records.set(id, a = []);
    if (a.length < 4096) a.push({it: E.iters.map(z => z.k), v});
  }
  const resolveHead = (h, ctx) => defs.has(h) ? {def: defs.get(h)} : macros.has(h) ? {macro: macros.get(h)} : OPS[h] ? {op: OPS[h]} : OPS['value/' + h] ? {op: OPS['value/' + h]} : OPS[ctx + '/' + h] ? {op: OPS[ctx + '/' + h]} : null;
  function ev(x, E) {
    if (++steps > 600000) throw Error('Evaluation budget exceeded (600,000 steps). Reduce iteration counts.');
    if (isNum(x)) { const v = numOf(x); if (!Number.isFinite(v)) throw Error('Nonfinite number.'); return val(numIsInt(x) ? 'int' : 'float', v); }
    if (isStr(x)) return val('text', x.text);
    if (typeof x === 'string') {
      if (isKw(x)) throw Error(`Keyword ${x} has no call to belong to.`);
      if (x === 't') return val('float', E.mode === 'static' ? undefined : time);
      if (x === 'pi') return val('float', Math.PI);
      if (x === 'true' || x === 'false') return val('bool', x === 'true');
      if (x === 'nil') return val('geometry', EMPTY);
      const [b, field] = x.split('.');
      if (!E.env.has(b)) throw Error(`${b} is not bound in ${E.scope}.${E.env.size ? ' Bound here: ' + [...E.env.keys()].slice(-6).join(', ') + '.' : ''}`);
      const v = E.env.get(b);
      if (!field) return v;
      if (v.t !== 'vec3' || !'xyz'.includes(field) || field.length !== 1) throw Error(`${b} has no output ${field}. A vec3 has .x .y .z.`);
      return val('float', v.d === undefined ? undefined : v.d['xyz'.indexOf(field)]);
    }
    if (!isL(x) || !x.length) throw Error('Expected an expression.');
    if (x.vector) {
      if (x.length !== 3) throw Error(`A vector has 3 components [x y z]; this one has ${x.length}.`);
      const cs = x.map(c => ev(c, E)); cs.forEach(c => { if (!NUM.has(c.t) && c.t !== 'any') throw Error(`Vector components are numbers; got ${c.t}.`); });
      return val('vec3', cs.some(c => c.d === undefined) ? undefined : cs.map(c => c.d));
    }
    const [head, ...args] = x;
    if (head === 'let*') return evScope(x, E, E.path + '~');
    if (ZONES.has(head)) return evZone(x, E, E.path + '~' + head);
    if (head === 'if') {
      if (args.length !== 3) throw Error('if takes a condition, a then and an else.');
      const c = coerce(ev(args[0], E), 'bool');
      if (!fits(c.t, 'bool')) throw Error(`if needs a bool condition, got ${c.t}.`);
      if (E.mode === 'static' || c.d === undefined) {
        const a = ev(args[1], E), b = ev(args[2], E);
        if (!fits(a.t, b.t) && !fits(b.t, a.t)) throw Error(`Both branches of if must have one type: ${a.t} and ${b.t}.`);
        return val(a.t === 'int' && b.t === 'float' ? 'float' : a.t, undefined);
      }
      return ev(c.d ? args[1] : args[2], E);
    }
    if (head === 'ref') {
      if (!graphs.has(args[0])) throw Error(`Unknown graph reference: ${args[0]}.`);
      if (E.inDef) throw Error('Reusable functions cannot capture project graphs; add an explicit parameter.');
      const g = graphs.get(args[0]), ps = paramsOf(g), over = {};
      const {kw, pos} = callArgs(x.slice(1)); if (pos.length > 1) throw Error('ref takes a graph name, then :input value pairs.');
      for (const [k, a] of Object.entries(kw)) { const p = ps.find(p => p[0] === k); if (!p) throw Error(`Graph ${args[0]} has no input :${k}. Inputs: ${ps.map(p => p[0]).join(', ') || 'none'}.`); const v = coerce(ev(a.v, E), p[2]); if (!fits(v.t, p[2])) throw Error(`:${k} of ${args[0]} is ${p[2]}, got ${v.t}.`); over[k] = v; }
      if (E.mode === 'static') return val(CONTEXTS[g[3]], undefined);
      return graph(args[0], E.stack, over);
    }
    if (typeof head !== 'string') throw Error('A call head is a name.');
    const r = resolveHead(head, E.ctx);
    if (!r) throw Error(`Unknown operator “${head}”.`);
    if (r.macro) { const m = r.macro; if (args.length !== m[2].length) throw Error(`${head} expects ${m[2].length} arguments.`); const sub = y => typeof y === 'string' && m[2].includes(y) ? clone(args[m[2].indexOf(y)]) : isL(y) ? (y.vector ? vec(y.map(sub)) : y.map(sub)) : y; return ev(sub(m[3]), E); }
    if (r.def) return evCall(r.def, x, E);
    return evOp(r.op, x, E);
  }
  function need(v, want, what) { if (!fits(v.t, want)) throw Error(`${what}: expected ${want.replace('list:', 'list of ')}, got ${v.t.replace('list:', 'list of ')}.`); return coerce(v, want); }
  function evOp(o, x, E) {
    if (o.ctx !== 'value' && o.ctx !== E.ctx) throw Error(`${o.name} belongs to ${o.ctx}; it cannot run in ${E.ctx}. Pass data through a typed input or ref.`);
    const {pos, kw} = callArgs(x);
    const slots = [...o.pos, ...(o.opt || [])];
    if (!o.rest && (pos.length < o.pos.length || pos.length > slots.length)) throw Error(`${o.name} takes ${o.pos.length}${o.opt ? '–' + slots.length : ''} positional input${slots.length === 1 ? '' : 's'}${o.pos.length ? ' (' + o.pos.map(p => p[0]).join(', ') + ')' : ''}; got ${pos.length}.`);
    const pv = [], ts = [];
    pos.slice(0, o.rest ? o.pos.length : slots.length).forEach((a, i) => { const s = slots[i], v = ev(a.v, E); ts.push(v.t); pv.push(o.anyNum && (v.t === 'vec3' || NUM.has(v.t)) ? v : need(v, s[1], `${o.name} ${s[0]}`)); });
    const rest = [];
    if (o.rest) pos.slice(o.pos.length).forEach(a => { const v = ev(a.v, E); if (elemOf(v.t) && fits(elemOf(v.t), o.rest)) { if (v.d) rest.push(...v.d.map(d => coerce(val(elemOf(v.t), d), o.rest))); else rest.push(val(o.rest, undefined)); } else rest.push(need(v, o.rest, `${o.name} ${o.restName}`)); });
    const kv = {};
    for (const [k, a] of Object.entries(kw)) {
      const s = o.kw.find(s => s[0] === k); if (!s) throw Error(`${o.name} has no parameter :${k}.${o.kw.length ? ' Parameters: ' + o.kw.map(s => ':' + s[0]).join(' ') + '.' : ''}`);
      const want = s[1] === 'group' || s[1] === 'groupref' ? 'text' : s[1];
      const v = ev(a.v, E); kv[k] = need(v, want, `${o.name} :${k}`);
    }
    const out = typeof o.out === 'function' ? o.out(ts) : o.out;
    if (E.mode === 'static' || pv.some(v => v.d === undefined) || rest.some(v => v.d === undefined) || Object.values(kv).some(v => v.d === undefined)) return val(out, undefined);
    const k = {}; o.kw.forEach(([n, , d]) => { k[n] = kv[n] ? kv[n].d : d; });
    let d = o.fn(pv.map(v => v.d), k, rest.map(v => v.d));
    if (typeof d === 'number' && !Number.isFinite(d)) throw Error(`${o.name} produced a nonfinite value.`);
    if (out === 'int' && typeof d === 'number') d = Math.round(d);
    return val(out, d);
  }
  function evCall(def, x, E) {
    const ctx = def[3]; if (ctx !== 'value' && ctx !== E.ctx) throw Error(`${def[1]} belongs to ${ctx}; it cannot run in ${E.ctx}.`);
    if (E.stack.includes(def[1])) throw Error(`Recursive call: ${[...E.stack, def[1]].join(' → ')}. Use fold for repetition.`);
    const ps = paramsOf(def), {pos, kw} = callArgs(x);
    if (pos.length > ps.length) throw Error(`${def[1]} takes ${ps.length} inputs; got ${pos.length} positional.`);
    const env = new Map();
    ps.forEach((p, i) => {
      const a = i < pos.length ? pos[i] : kw[p[0]];
      if (i < pos.length && kw[p[0]]) throw Error(`${def[1]} input ${p[0]} is given twice.`);
      if (!a) { if (p.length === 4) env.set(p[0], coerce(ev(p[3], E), p[2])); else throw Error(`${def[1]} needs :${p[0]} (${p[2]}).`); return; }
      env.set(p[0], need(ev(a.v, E), p[2], `${def[1]} :${p[0]}`));
    });
    Object.keys(kw).forEach(k => { if (!ps.some(p => p[0] === k)) throw Error(`${def[1]} has no input :${k}. Inputs: ${ps.map(p => p[0]).join(', ')}.`); });
    const inner = {...E, env, ctx, stack: [...E.stack, def[1]], scope: 'ƒ ' + def[1], path: 'def:' + def[1], inDef: true, record: !!E.inspect, iters: []};
    if (inner.record) ps.forEach(p => rec(inner, 'def:' + def[1] + '/:' + p[0], env.get(p[0])));
    return evBody(body(def), inner);
  }
  function evBody(b, E) { return isL(b) && b[0] === 'let*' ? evScope(b, E, E.path) : evResult(b, E, E.path); }
  function evResult(x, E, path) { const v = evBinding(x, E, path + '/@result'); if (isL(x) && !x.vector) rec(E, path + '/@result', v); return v; }
  function evBinding(x, E, id) {
    if (isL(x) && !x.vector && ZONES.has(x[0])) return evZone(x, E, id);
    if (isL(x) && !x.vector && x[0] === 'let*') return evScope(x, E, id);
    return ev(x, E);
  }
  function evScope(x, E, path) {
    if (x.length !== 3 || !x[1]?.vector || x[1].length % 2) throw Error('let* needs [name expression …] and one result.');
    const env = new Map(E.env), seen = new Set();
    for (let i = 0; i < x[1].length; i += 2) {
      const n = x[1][i];
      if (typeof n !== 'string' || !NAME.test(n) || RESERVED.has(n)) throw Error(`Invalid binding name ${atom(n)}${n === 't' ? ': t is the context time' : ''}.`);
      if (seen.has(n)) throw Error(`${n} is bound twice in one let*.`);
      if (E.env.has(n)) throw Error(`${n} shadows an outer name in ${E.scope}. Rename it; the graph cannot show two nodes called ${n} on one wire.`);
      seen.add(n);
      const id = path + '/' + n, v = evBinding(x[1][i + 1], {...E, env, top: false, path: id}, id);
      env.set(n, v); rec(E, id, v);
    }
    return evResult(x[2], {...E, env, top: false}, path);
  }
  function evZone(x, E, id) {
    const h = x[0], vars = zoneVars(x);
    if ((h === 'fold' || h === 'scan') && (x.length !== 4 || !x[1]?.vector || !x[2]?.vector)) throw Error(`${h} is (${h} [acc init] [i collection] body).`);
    if ((h === 'for' || h === 'sum') && (x.length !== 3 || !x[1]?.vector)) throw Error(`${h} is (${h} [i collection …] body).`);
    if (vars.some((v, k) => typeof v.name !== 'string' || !NAME.test(v.name) || RESERVED.has(v.name))) throw Error(`${h} binds names; ${vars.map(v => atom(v.name)).join(', ')} includes an invalid one.`);
    const iters = vars.filter(v => v.role === 'iter'), accs = vars.filter(v => v.role === 'acc');
    if (!iters.length) throw Error(`${h} needs at least one [name collection] clause.`);
    if ((h === 'fold' || h === 'scan') && accs.length !== 1) throw Error(`${h} carries exactly one accumulator in this study: [acc init].`);
    for (const v of vars) if (E.env.has(v.name)) throw Error(`${v.name} shadows an outer name. Pick another loop name.`);
    const b = zoneBody(x), inner = {...E, scope: E.scope + ' › ' + id.split('/').pop(), top: false};
    const info = {kind: h, vars: vars.map(v => v.name), count: 0, items: [], states: [], varTypes: {}};
    // static: type the body once
    const colls = [];
    const env0 = new Map(E.env);
    let accT = null;
    if (accs.length) { const iv = ev(accs[0].expr, E); accT = iv.t; info.varTypes[accs[0].name] = iv.t; env0.set(accs[0].name, val(iv.t, undefined)); colls.acc = iv; }
    const envS = new Map(env0);
    iters.forEach(v => { const c = ev(v.expr, {...E, env: envS}); if (!elemOf(c.t)) throw Error(`${v.name} in ${h} iterates a list (range, linspace, point_list …); got ${c.t}.`); info.varTypes[v.name] = elemOf(c.t); envS.set(v.name, val(elemOf(c.t), undefined)); colls.push(c); });
    if (E.mode === 'static') {
      const bt = evBody(b, {...inner, env: envS, path: id, iters: [...E.iters, {zone: id, k: 0}]});
      if (accT && !fits(bt.t, accT)) throw Error(`${h} body must return the accumulator type ${accT}; it returns ${bt.t}.`);
      if (h === 'sum' && !NUM.has(bt.t) && bt.t !== 'vec3' && bt.t !== 'any') throw Error(`sum adds numbers or vec3; the body returns ${bt.t}.`);
      zones.set(id, {...(zones.get(id) || {}), ...info, bodyType: bt.t});
      if (E.mode === 'static') { types.set(id + '/@yield', bt.t); Object.entries(info.varTypes).forEach(([n, t]) => types.set(id + '/:' + n, t)); }
      return val(h === 'for' || h === 'scan' ? listOf(bt.t) : h === 'sum' ? (bt.t === 'int' ? 'int' : bt.t === 'vec3' ? 'vec3' : 'float') : accT, undefined);
    }
    // run: product iteration, clauses may depend on earlier clause variables
    const outs = [], states = [], items = [];
    let acc = colls.acc || null, k = 0, total = null, sumT = 'int';
    if (acc) states.push({it: [...E.iters.map(z => z.k), -1], v: acc});
    const loop = (ci, env) => {
      if (ci === iters.length) {
        if (k >= 4096) throw Error(`${id.split('/').pop()} runs more than 4,096 iterations.`);
        const envB = new Map(env); if (acc) envB.set(accs[0].name, acc);
        const it = [...E.iters, {zone: id, k}], Ei = {...inner, env: envB, path: id, iters: it};
        vars.forEach(v => rec(Ei, id + '/:' + v.name, envB.get(v.name)));
        const v = evBody(b, Ei);
        const tuple = it.map(z => z.k);
        if (acc) { acc = coerce(v, accT); states.push({it: tuple, v: acc}); if (h === 'scan') outs.push(acc); }
        else if (h === 'sum') { if (v.t === 'vec3') { total = total ? total.map((c, j) => c + v.d[j]) : v.d; sumT = 'vec3'; } else { total = (total || 0) + v.d; if (v.t === 'float') sumT = 'float'; } }
        else outs.push(v);
        items.push({it: tuple, v}); k++; return;
      }
      const c = ci === 0 ? colls[0] : ev(iters[ci].expr, {...E, env});
      if (!c.d) return;
      for (const item of c.d) { const e2 = new Map(env); e2.set(iters[ci].name, val(elemOf(c.t), item)); loop(ci + 1, e2); }
    };
    loop(0, new Map(E.env));
    const prev = zones.get(id) || {};
    if (E.record) zones.set(id, {...prev, ...info, count: (prev.runs ? prev.count : 0) + k, runs: (prev.runs || 0) + 1,
      items: [...(prev.runs ? prev.items : []), ...items].slice(0, 4096), states: [...(prev.runs ? prev.states : []), ...states].slice(0, 4096)});
    if (h === 'fold') return acc;
    if (h === 'sum') return val(total === null ? 'int' : sumT, total === null ? 0 : total);
    const et = outs[0]?.t || types.get(id + '/@yield') || 'any';
    let data = outs.map(o => o.d);
    if (et === 'geometry') data = data.map((g, j) => geo(g.prims.map(p => ({...p, tags: {...p.tags, [id]: j}}))));
    return val(listOf(et), data);
  }
  function graph(name, stack = [], over = null) {
    const key = name + (over && Object.keys(over).length ? JSON.stringify(Object.entries(over).map(([k, v]) => [k, v.d])) : '');
    if (cache.has(key)) return cache.get(key);
    if (stack.includes(name)) throw Error(`Graph cycle: ${[...stack, name].join(' → ')}.`);
    const f = graphs.get(name), env = new Map();
    const E0 = {mode: 'run', ctx: f[3], stack: [...stack, name], scope: name, path: name, iters: [], record: !over, top: true, env};
    paramsOf(f).forEach(p => { env.set(p[0], over?.[p[0]] ? over[p[0]] : coerce(ev(p[3], E0), p[2])); if (!over) rec(E0, name + '/:' + p[0], env.get(p[0])); });
    const v = evBody(body(f), E0);
    if (!fits(v.t, CONTEXTS[f[3]])) throw Error(`${name} must return ${CONTEXTS[f[3]]}, received ${v.t}.`);
    cache.set(key, v); return v;
  }
  // static pass: types every binding, including untaken branches, zero-iteration loops and function bodies
  for (const [name, f] of defs) {
    const env = new Map(paramsOf(f).map(p => [p[0], val(p[2], undefined)]));
    paramsOf(f).forEach(p => types.set('def:' + name + '/:' + p[0], p[2]));
    const t = evBody(body(f), {mode: 'static', ctx: f[3], env, stack: [name], scope: 'ƒ ' + name, path: 'def:' + name, iters: [], inDef: true, top: true});
    if (f[3] !== 'value' && !fits(t.t, CONTEXTS[f[3]]) && !(CONTEXTS[f[3]] === 'geometry' && t.t === 'geometry')) {/* functions may return other types */}
    types.set('def:' + name, t.t);
  }
  for (const [name, f] of graphs) {
    const env = new Map(paramsOf(f).map(p => [p[0], val(p[2], undefined)]));
    paramsOf(f).forEach(p => types.set(name + '/:' + p[0], p[2]));
    const t = evBody(body(f), {mode: 'static', ctx: f[3], env, stack: [name], scope: name, path: name, iters: [], top: true});
    if (!fits(t.t, CONTEXTS[f[3]])) throw Error(`${name} must return ${CONTEXTS[f[3]]}, but its result is ${t.t}.`);
  }
  for (const name of graphs.keys()) graph(name);
  return {ast, graphs, defs, macros, cache, records, types, zones, steps, time,
    inspect(fnName, x, ctx, env) { steps = 0; [...records.keys()].forEach(k => k.startsWith('def:') && records.delete(k)); [...zones.keys()].forEach(k => k.startsWith('def:') && zones.delete(k));
      return evCall(defs.get(fnName), x, {mode: 'run', ctx, env, stack: [], scope: 'preview', path: 'preview', iters: [], record: false, inspect: true}); }};
}

const API = {read, print, printMarked, compile, OPS, CONTEXTS, SPECIAL, ZONES, body, bindings, paramsOf, callArgs, zoneVars, zoneBody, freeSymbols,
  clone, vec, str, isStr, isKw, isNum, numOf, mkNum, fmtNum, atom, fits, elemOf, listOf, hash, toHex, bbox, M1, M2};
if (typeof module !== 'undefined') module.exports = API; else root.Workspace = API;
})(typeof window !== 'undefined' ? window : globalThis);
