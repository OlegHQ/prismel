/* Design artifact only: a small checked Lisp interpreter for the workspace study.
   Not product code, not a renderer. Geometry is a small 3D illustration kernel. */
(function (root) {
'use strict';
const isL = Array.isArray;
const vec = xs => Object.assign(xs, {vector: true});
const mkMap = xs => Object.assign(xs, {record: true}); // record literal {…}: alternating keyword/value
const isMap = x => isL(x) && x.record === true;
const isCall = x => isL(x) && !x.vector && !isMap(x);
const amap = (xs, f) => Array.prototype.map.call(xs, f);
const str = value => ({text: value});
const isStr = x => !!x && typeof x === 'object' && !isL(x) && 'text' in x;
const isKw = x => typeof x === 'string' && x[0] === ':' && x.length > 1;
const hide = (x, k, v) => Object.defineProperty(x, k, {value: v, writable: true, configurable: true, enumerable: false});
/* Comments are notes on the parent array, keyed by the child they precede: workspace children by form name,
   let* binding vectors by binding name (or printed pattern), anything else by child index; '$end' trails the last child. */
function getNote(x, k) { return isL(x) && x.notes && x.notes[k] != null ? x.notes[k] : null; }
function setNote(x, k, text) { if (!x.notes) hide(x, 'notes', {}); if (text == null || text === '') delete x.notes[k]; else x.notes[k] = String(text); return x; }
function copyFlags(src, out) {
  if (src.vector) out.vector = true; if (isMap(src)) out.record = true;
  if (src.notes && Object.keys(src.notes).length) hide(out, 'notes', {...src.notes});
  if (src.meta?.length) hide(out, 'meta', [...src.meta]);
  return out;
}
const remap = (x, f) => copyFlags(x, amap(x, f));
function clone(x) { return isL(x) ? remap(x, y => clone(y)) : isStr(x) ? {...x} : x; }

/* ---------------- reader ---------------- */
const QUOTES = {"'": 'quote', '`': 'quasiquote', '~': 'unquote', '~@': 'unquote-splicing'};
const QPRE = {quote: "'", quasiquote: '`', unquote: '~', 'unquote-splicing': '~@'};
const OPEN = {'(': ')', '[': ']', '{': '}'}, CLOSE = new Set([')', ']', '}']);
function read(source) {
  if (source.length > 120000) throw Error('Document exceeds the study limit of 120,000 characters.');
  const tokens = []; let i = 0, line = 1;
  while (i < source.length) {
    const c = source[i];
    if (c === '\n') { line++; i++; continue; }
    if (/\s/.test(c)) { i++; continue; }
    const start = i;
    if (c === ';') { while (i < source.length && source[i] !== '\n') i++; tokens.push({note: source.slice(start, i).replace(/^;+ ?/, '').trimEnd(), start, line}); continue; }
    if ('()[]{}'.includes(c)) { tokens.push({v: c, start, line}); i++; continue; }
    if (c === '~' && source[i + 1] === '@') { tokens.push({q: '~@', start, line}); i += 2; continue; }
    if ("'`~^".includes(c)) { tokens.push({q: c, start, line}); i++; continue; }
    if (c === '"') {
      i++; let escaped = false;
      while (i < source.length) { const d = source[i++]; if (d === '"' && !escaped) break; escaped = d === '\\' && !escaped; }
      try { tokens.push({v: str(JSON.parse(source.slice(start, i))), start, line}); }
      catch { throw Error(`Line ${line}: invalid string.`); }
      continue;
    }
    while (i < source.length && !/[\s()[\]{};"]/.test(source[i])) i++;
    const raw = source.slice(start, i);
    tokens.push({v: /^-?(?:\d+\.?\d*|\.\d+)$/.test(raw) ? Number(raw) : raw, start, line, raw});
  }
  let at = 0;
  const notes = () => { const o = []; while (tokens[at] && 'note' in tokens[at]) o.push(tokens[at++].note); return o.length ? o.join('\n') : null; };
  function take(depth) {
    if (depth > 120) throw Error('Nesting exceeds 120 levels.');
    notes(); // a comment between a prefix (' ` ~ ^) and its form has nothing to attach to
    const token = tokens[at++]; if (!token) throw Error('Unexpected end of source.');
    if (token.q === '^') {
      const k = tokens[at++]; if (!k || !isKw(k.v)) throw Error(`Line ${token.line}: ^ is followed by a keyword, as in ^:bypass.`);
      const form = take(depth + 1); if (!isL(form)) throw Error(`Line ${token.line}: metadata ^${k.v} applies to a form in brackets.`);
      hide(form, 'meta', [...(form.meta || []), k.v.slice(1)]); return form;
    }
    if (token.q) return [QUOTES[token.q], take(depth + 1)];
    const x = token.v;
    if (OPEN[x]) {
      const out = [], close = OPEN[x], ns = {};
      for (;;) {
        const n = notes();
        if (tokens[at]?.v === close) { if (n) ns.$end = n; break; }
        if (!tokens[at]) throw Error(`Line ${token.line}: this "${x}" is never closed.`);
        if (CLOSE.has(tokens[at].v)) throw Error(`Line ${tokens[at].line}: expected "${close}" to close the "${x}" on line ${token.line}, found "${tokens[at].v}".`);
        out.push(take(depth + 1)); if (n) ns[out.length - 1] = n;
      }
      at++;
      if (x === '[') vec(out); else if (x === '{') mkMap(out);
      else if (out[0] === 'workspace') { for (const k of Object.keys(ns)) { const f = out[k]; if (/^\d+$/.test(k) && +k >= 2 && isL(f) && typeof f[1] === 'string') { ns[f[1]] = ns[k]; delete ns[k]; } } }
      else if (out[0] === 'let*' && out[1]?.vector && out[1].notes) { const v = out[1], nn = {}; for (const [k, t] of Object.entries(v.notes)) nn[/^\d+$/.test(k) && k % 2 === 0 && +k < v.length ? patKey(v[k]) : k] = t; v.notes = nn; }
      if (Object.keys(ns).length) hide(out, 'notes', ns);
      return out;
    }
    if (CLOSE.has(x)) throw Error(`Line ${token.line}: unexpected "${x}".`);
    if (typeof x === 'number' && token.raw.includes('.') && Number.isInteger(x)) return {float: x}; // 2.0 stays a float
    return x;
  }
  const lead = notes(), result = take(0), tail = notes();
  if (at !== tokens.length) throw Error('Expected one workspace form.');
  if (isL(result)) { if (lead) setNote(result, '$lead', lead); if (tail) setNote(result, '$end', [getNote(result, '$end'), tail].filter(Boolean).join('\n')); }
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
const metaPre = x => isL(x) && x.meta?.length ? x.meta.map(m => '^:' + m + ' ').join('') : '';
function flat(x, mark, parent, i, bare) {
  const m = isMark(mark, x, parent, i);
  let s;
  if (!isL(x)) s = atom(x);
  else {
    const kids = (o, c) => o + amap(x, (y, j) => flat(y, mark, x, j)).join(' ') + c;
    s = (bare ? '' : metaPre(x)) + (x.vector ? kids('[', ']') : isMap(x) ? kids('{', '}') : QPRE[x[0]] && x.length === 2 ? QPRE[x[0]] + flat(x[1], mark, x, 1) : kids('(', ')'));
  }
  return m ? M1 + s + M2 : s;
}
const patKey = p => typeof p === 'string' ? p : flat(p);
const nl = (text, col) => String(text).split('\n').map(l => (l ? '; ' + l : ';') + '\n' + ' '.repeat(col)).join('');
const noteAt = (x, k, col) => { const n = x.notes?.[k]; return n ? nl(n, col) : ''; };
const ownNotes = x => !!x.notes && Object.keys(x.notes).length > 0;
let NM = new WeakMap();
function deepNotes(x) { if (!isL(x)) return false; let r = NM.get(x); if (r === undefined) { r = ownNotes(x) || x.some(deepNotes); NM.set(x, r); } return r; }
const WIDTH = 84;
const BIND_FORMS = new Set(['let*', 'for', 'sum']);
function pp(x, ind = 0, mark, parent, i, bare) {
  if (!isL(x)) return flat(x, mark, parent, i);
  const pre = bare ? '' : metaPre(x);
  if (pre) { const s = pp(x, ind + pre.length, mark, parent, i, true); return s[0] === M1 ? M1 + pre + s.slice(1) : pre + s; }
  const f = flat(x, mark, parent, i, true);
  const m = isMark(mark, x, parent, i), wrap = s => m ? M1 + s + M2 : s, sp = n => ' '.repeat(n);
  const own = ownNotes(x), deep = deepNotes(x), endN = col => x.notes?.$end ? '\n' + sp(col) + nl(x.notes.$end, col) : '';
  if (x.vector || isMap(x)) {
    if (!deep && (x.vector || vis(f) + ind <= WIDTH)) return f;
    const col = ind + 1, parts = [];
    for (let k = 0; k < x.length; k++) {
      if (isMap(x) && k % 2 === 0 && k + 1 < x.length) {
        const key = pp(x[k], col, mark, x, k);
        parts.push(noteAt(x, k, col) + key + (x.notes?.[k + 1] ? '\n' + sp(col + 2) + noteAt(x, k + 1, col + 2) + pp(x[k + 1], col + 2, mark, x, k + 1) : ' ' + pp(x[k + 1], col + vis(key) + 1, mark, x, k + 1)));
        k++;
      } else parts.push(noteAt(x, k, col) + pp(x[k], col, mark, x, k));
    }
    const [o, c] = x.vector ? '[]' : '{}';
    return wrap(o + (x.notes?.[0] ? '\n' + sp(col) : '') + parts.join('\n' + sp(col)) + endN(col) + c);
  }
  const head = x[0];
  if (QPRE[head] && x.length === 2) { const q = QPRE[head]; return wrap(q + pp(x[1], ind + q.length, mark, x, 1)); }
  if (head === 'workspace') return wrap(`(workspace ${x[1]}` + x.slice(2).map((y, j) => '\n\n' + sp(ind + 2) + noteAt(x, isL(y) && typeof y[1] === 'string' && x.notes?.[y[1]] ? y[1] : j + 2, ind + 2) + pp(y, ind + 2, mark, x, j + 2)).join('') + endN(ind + 2) + ')');
  if (!deep && (vis(f) + ind <= WIDTH || (vis(f) <= 44 && !BIND_FORMS.has(head) && head !== 'fold' && head !== 'scan')) && !['graph', 'defn', 'defmacro'].includes(head) && !(head === 'let*' && x[1]?.length > 2)) return f;
  const bvec = (v, col, byName) => { // aligned binding vector
    const rows = [], key = k => byName && v.notes?.[patKey(v[k])] ? patKey(v[k]) : k;
    for (let k = 0; k < v.length; k += 2) {
      const name = flat(v[k], mark, v, k), pad = col + 1 + vis(name) + 1;
      const val = k + 1 >= v.length ? '' : v.notes?.[k + 1] ? '\n' + sp(col + 3) + noteAt(v, k + 1, col + 3) + pp(v[k + 1], col + 3, mark, v, k + 1) : ' ' + pp(v[k + 1], pad, mark, v, k + 1);
      rows.push(noteAt(v, key(k), col + 1) + name + val);
    }
    const s = '[' + (v.length && v.notes?.[key(0)] ? '\n' + sp(col + 1) : '') + rows.join('\n' + sp(col + 1)) + (v.notes?.$end ? '\n' + sp(col + 1) + nl(v.notes.$end, col + 1) : '') + ']';
    return isMark(mark, v, x, x.indexOf(v)) ? M1 + s + M2 : s;
  };
  const tail = (k, col) => '\n' + sp(col) + noteAt(x, k, col) + pp(x[k], col, mark, x, k);
  if (BIND_FORMS.has(head) && x[1]?.vector && x.length === 3) {
    const col = ind + head.length + 2;
    return wrap(`(${head} ` + bvec(x[1], col, head === 'let*') + tail(2, ind + 2) + endN(ind + 2) + ')');
  }
  if ((head === 'fold' || head === 'scan') && x[1]?.vector && x[2]?.vector && x.length === 4) {
    const col = ind + head.length + 2;
    return wrap(`(${head} ` + bvec(x[1], col) + '\n' + sp(col) + bvec(x[2], col) + tail(3, ind + 2) + endN(ind + 2) + ')');
  }
  if (head === 'if' && x.length === 4) return wrap('(if' + (x.notes?.[1] ? '\n' + sp(ind + 4) + noteAt(x, 1, ind + 4) : ' ') + pp(x[1], ind + 4, mark, x, 1) + tail(2, ind + 4) + tail(3, ind + 4) + endN(ind + 4) + ')');
  if (head === 'graph' || head === 'defn') {
    const hasP = x[4]?.vector && x.length === 6;
    const hdr = `(${head} ${x[1]} ${x[2]} ${x[3]}` + (hasP ? ' ' + flat(x[4], mark, x, 4) : '');
    return wrap(hdr + tail(x.length - 1, ind + 2) + endN(ind + 2) + ')');
  }
  if (head === 'defmacro' && x.length === 4) return wrap(`(defmacro ${x[1]} ${flat(x[2])}` + tail(3, ind + 2) + endN(ind + 2) + ')');
  if (head === 'fn' && x.length === 3 && x[1]?.vector) return wrap('(fn ' + flat(x[1], mark, x, 1) + tail(2, ind + 2) + endN(ind + 2) + ')');
  if (head === 'cond' || head === 'case') {
    const col = ind + 2, rows = [], first = head === 'case' ? 2 : 1;
    for (let k = first; k < x.length; k += 2) {
      const a = pp(x[k], col, mark, x, k);
      rows.push(noteAt(x, k, col) + a + (k + 1 >= x.length ? '' : x.notes?.[k + 1] || a.includes('\n') ? tail(k + 1, col + 2) : ' ' + pp(x[k + 1], col + vis(a) + 1, mark, x, k + 1)));
    }
    const hd = head === 'case' ? '(case' + (x.notes?.[1] ? '\n' + sp(col) + noteAt(x, 1, col) : ' ') + pp(x[1], x.notes?.[1] ? col : ind + 6, mark, x, 1) : '(cond';
    return wrap(hd + rows.map(r => '\n' + sp(col) + r).join('') + endN(col) + ')');
  }
  // call: first positional on the head line, keyword pairs aligned below
  const units = []; for (let k = 1; k < x.length; k++) { if (isKw(x[k]) && k + 1 < x.length) { units.push([k, k + 1]); k++; } else units.push([k]); }
  const hs = flat(head, mark, x, 0);
  if (own) { // a form with comments puts every argument on its own line
    const col = ind + 2;
    const u2 = us => noteAt(x, us[0], col) + (us.length === 2 ? x[us[0]] + (x.notes?.[us[1]] ? tail(us[1], col + 2) : ' ' + pp(x[us[1]], col + x[us[0]].length + 1, mark, x, us[1])) : pp(x[us[0]], col, mark, x, us[0]));
    return wrap('(' + (x.notes?.[0] ? noteAt(x, 0, ind + 1) : '') + hs + units.map(us => '\n' + sp(col) + u2(us)).join('') + endN(col) + ')');
  }
  let col = ind + 1 + vis(hs) + 1; if (col > ind + 18) col = ind + 4;
  const u = us => us.length === 2 ? x[us[0]] + ' ' + pp(x[us[1]], col + x[us[0]].length + 1, mark, x, us[1]) : pp(x[us[0]], col, mark, x, us[0]);
  if (!units.length) return f;
  const first = u(units[0]);
  return wrap('(' + hs + ' ' + (col === ind + 4 && units.length > 1 && vis(first) > 30 ? '\n' + sp(col) : '') + units.map(u).join('\n' + sp(col)) + ')');
}
function top(x, mark) { NM = new WeakMap(); const lead = getNote(x, '$lead'); return (lead ? nl(lead, 0) : '') + pp(x, 0, mark); }
const print = (x, mark) => top(x, mark).replace(/[\u0001\u0002]/g, '').replace(/[ \t]+\n/g, '\n');
const printMarked = (x, mark) => top(x, mark);

/* ---------------- types and values ----------------
   Type strings: int float bool text vec3 geometry … fn any, list:T, rec{a:T,b:U} (field order as written). */
const val = (t, d) => ({t, d});
const listOf = t => 'list:' + t;
const elemOf = t => t && t.startsWith('list:') ? t.slice(5) : null;
const NUM = new Set(['int', 'float']);
const TCACHE = new Map();
function parseType(s) {
  let T = TCACHE.get(s); if (T) return T;
  let i = 0;
  const p = () => {
    if (s.startsWith('list:', i)) { i += 5; return {k: 'list', e: p()}; }
    if (s.startsWith('rec{', i)) { i += 4; const f = []; while (i < s.length && s[i] !== '}') { const c = s.indexOf(':', i); if (c < 0) break; const n = s.slice(i, c); i = c + 1; f.push([n, p()]); if (s[i] === ',') i++; } i++; return {k: 'rec', f}; }
    let j = i; while (j < s.length && s[j] !== ',' && s[j] !== '}') j++; const n = s.slice(i, j); i = j; return {k: 'atom', n};
  };
  T = p(); if (TCACHE.size > 4096) TCACHE.clear(); TCACHE.set(s, T); return T;
}
const recT = fs => 'rec{' + fs.map(([n, t]) => n + ':' + t).join(',') + '}';
const formatType = T => T.k === 'list' ? listOf(formatType(T.e)) : T.k === 'rec' ? recT(T.f.map(([n, t]) => [n, formatType(t)])) : T.n;
const recFields = t => t && t.startsWith('rec{') ? parseType(t).f.map(([n, T]) => [n, formatType(T)]) : null;
const hasFn = t => !!t && /(^|[:{,])fn(?=$|[,}])/.test(t);
function fits(have, want) {
  if (!have || !want || have === 'any' || want === 'any') return true;
  if (have === want) return true;
  if (NUM.has(have) && (NUM.has(want) || want === 'bool')) return true;
  if (have === 'bool' && NUM.has(want)) return true;
  if (want === 'color') return have === 'text' || have === 'vec3';
  if (want === 'vec3' && NUM.has(have)) return true;
  if (elemOf(want) && elemOf(have)) return fits(elemOf(have), elemOf(want));
  const hf = recFields(have), wf = recFields(want);
  if (hf && wf) return wf.every(([n, t]) => { const h = hf.find(q => q[0] === n); return !!h && fits(h[1], t); });
  return false;
}
function coerceT(have, want) {
  if (!want || want === 'any' || have === 'any' || have === want) return have;
  if (elemOf(have) && elemOf(want)) return listOf(coerceT(elemOf(have), elemOf(want)));
  const hf = recFields(have), wf = recFields(want);
  if (hf && wf) return recT(hf.map(([n, t]) => { const w = wf.find(q => q[0] === n); return [n, w ? coerceT(t, w[1]) : t]; }));
  if ((NUM.has(have) || have === 'bool') && (NUM.has(want) || want === 'bool' || (want === 'vec3' && have !== 'bool'))) return want;
  return have;
}
function coerceD(d, have, want) {
  if (d === undefined || !want || want === 'any' || have === 'any' || have === want) return d;
  if (elemOf(have) && elemOf(want)) { const h = elemOf(have), w = elemOf(want); return d.map(e => coerceD(e, h, w)); }
  const hf = recFields(have), wf = recFields(want);
  if (hf && wf) { const o = {...d}; wf.forEach(([n, w]) => { const h = hf.find(q => q[0] === n); if (h) o[n] = coerceD(d[n], h[1], w); }); return o; }
  if (want === 'int' && have === 'float') return Math.round(d);
  if (want === 'bool' && NUM.has(have)) return d !== 0;
  if (NUM.has(want) && have === 'bool') return d ? 1 : 0;
  if (want === 'vec3' && NUM.has(have)) return [d, d, d];
  return d;
}
function coerce(v, want) { if (v.d === undefined || v.t === want || !want || want === 'any') return v; const t = coerceT(v.t, want), d = coerceD(v.d, v.t, want); return t === v.t && d === v.d ? v : val(t, d); }
/* The least type both fit into (int+float → float), or null. */
function joinT(a, b) {
  if (a === b) return a; if (!a || a === 'any') return b; if (!b || b === 'any') return a;
  if (NUM.has(a) && NUM.has(b)) return 'float';
  if (elemOf(a) && elemOf(b)) { const j = joinT(elemOf(a), elemOf(b)); return j && listOf(j); }
  const af = recFields(a), bf = recFields(b);
  if (af && bf && af.length === bf.length && af.every(([n]) => bf.some(q => q[0] === n))) { const fs = af.map(([n, t]) => [n, joinT(t, bf.find(q => q[0] === n)[1])]); return fs.every(q => q[1]) ? recT(fs) : null; }
  return null;
}
const unify = (a, b) => joinT(a, b) || (fits(a, b) && fits(b, a) ? a : null);
/* str formatting: ints plain, floats up to 4 decimals, vec3 and lists as [x y z], records as {:a 1}. */
function show(t, d) {
  if (d === undefined) return '?';
  const n = x => String(+(+x).toFixed(4));
  if (t === 'int') return String(d); if (t === 'float') return n(d); if (t === 'bool') return d ? 'true' : 'false'; if (t === 'text') return d;
  if (t === 'vec3') return '[' + d.map(n).join(' ') + ']';
  const e = elemOf(t); if (e) return '[' + d.map(x => show(e, x)).join(' ') + ']';
  const fs = recFields(t); if (fs) return '{' + fs.map(([k, ft]) => ':' + k + ' ' + show(ft, d[k])).join(' ') + '}';
  if (typeof d === 'number') return n(d); if (typeof d === 'boolean' || typeof d === 'string') return String(d);
  return t;
}

/* ---------------- 3D illustration kernel ----------------
   Polygons (faces), polylines and points in 3D. Enough to show the language; not rdk. */
let uidN = 0;
const prim = (pts, closed, extra) => ({pts, closed, kind: closed ? 'face' : pts.length === 1 ? 'point' : 'line', color: null, groups: [], tags: {}, uid: ++uidN, ...extra});
const geo = prims => ({prims});
const EMPTY = geo([]);
function hash(...xs) { let h = 0x9e3779b9 | 0; for (const x of xs) { const k = Math.floor(Number(x) * 1000003) | 0; h = Math.imul(h ^ k, 0x85ebca6b); h ^= h >>> 13; h = Math.imul(h, 0xc2b2ae35); h ^= h >>> 16; } return ((h >>> 0) % 1000000) / 1000000; }
function noise3(x, y, z, seed) {
  const xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z), s = t => t * t * (3 - 2 * t), u = s(x - xi), v = s(y - yi), w = s(z - zi);
  const h = (a, b, c) => hash(seed, xi + a, yi + b, zi + c), L = (a, b, t) => a + (b - a) * t;
  return L(L(L(h(0, 0, 0), h(1, 0, 0), u), L(h(0, 1, 0), h(1, 1, 0), u), v), L(L(h(0, 0, 1), h(1, 0, 1), u), L(h(0, 1, 1), h(1, 1, 1), u), v), w) - 0.5;
}
const mapPts = (g, fn) => geo(g.prims.map(p => ({...p, pts: p.pts.map(fn)})));
function bbox(g) { const lo = [Infinity, Infinity, Infinity], hi = [-Infinity, -Infinity, -Infinity]; g.prims.forEach(p => p.pts.forEach(q => { for (let i = 0; i < 3; i++) { lo[i] = Math.min(lo[i], q[i]); hi[i] = Math.max(hi[i], q[i]); } })); return {x0: lo[0], y0: lo[1], z0: lo[2], x1: hi[0], y1: hi[1], z1: hi[2]}; }
function centroid(p) { const c = [0, 0, 0]; p.pts.forEach(q => { c[0] += q[0]; c[1] += q[1]; c[2] += q[2]; }); return c.map(v => v / p.pts.length); }
/* rotation in radians, XYZ order, then translate: the catalog's transform convention */
function rotXYZ([x, y, z], [rx, ry, rz]) {
  let c = Math.cos(rx), s = Math.sin(rx); [y, z] = [y * c - z * s, y * s + z * c];
  c = Math.cos(ry); s = Math.sin(ry); [x, z] = [x * c + z * s, -x * s + z * c];
  c = Math.cos(rz); s = Math.sin(rz); [x, y] = [x * c - y * s, x * s + y * c];
  return [x, y, z];
}
const place = (pts, k) => pts.map(q => { const us = k.uniform_scale ?? 1, r = rotXYZ([q[0] * us, q[1] * us, q[2] * us], k.rotation || [0, 0, 0]), c = k.center || [0, 0, 0]; return [r[0] + c[0], r[1] + c[1], r[2] + c[2]]; });
function sphere(r, seg, rings) {
  const out = [], P = (i, j) => { const th = i / seg * Math.PI * 2, ph = j / rings * Math.PI; return [r[0] * Math.sin(ph) * Math.cos(th), r[1] * Math.cos(ph), r[2] * Math.sin(ph) * Math.sin(th)]; };
  for (let j = 0; j < rings; j++) for (let i = 0; i < seg; i++) out.push([P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)]);
  return out;
}
function faceNormal(p) { const [a, b, c] = p.pts; if (!c) return [0, 1, 0]; const u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], v = [c[0] - a[0], c[1] - a[1], c[2] - a[2]], n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]], l = Math.hypot(...n) || 1; return n.map(x => x / l); }
function subdivideFace(p) { // one face into quads around its centroid (linear); smoothing is left to the real kernel
  const c = centroid(p), n = p.pts.length, mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2];
  return p.pts.map((q, i) => ({...p, pts: [q, mid(q, p.pts[(i + 1) % n]), c, mid(p.pts[(i + n - 1) % n], q)], uid: ++uidN}));
}
function chaikin(p) {
  const P = p.pts, n = P.length; if (n < 3) return p; const out = [], L = (a, b, t) => a.map((v, i) => v * (1 - t) + b[i] * t);
  if (!p.closed) out.push(P[0]);
  for (let i = 0; i < (p.closed ? n : n - 1); i++) { const a = P[i], b = P[(i + 1) % n]; out.push(L(a, b, .25), L(a, b, .75)); }
  if (!p.closed) out.push(P[n - 1]);
  return {...p, pts: out};
}
function wire(p, radius, sides) { // polywire: a prism around every segment of a line
  const out = [], P = p.pts;
  for (let s = 0; s + 1 < P.length; s++) {
    const a = P[s], b = P[s + 1], d = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], L = Math.hypot(...d) || 1, t = d.map(x => x / L);
    const up = Math.abs(t[1]) < 0.9 ? [0, 1, 0] : [1, 0, 0], u0 = [t[1] * up[2] - t[2] * up[1], t[2] * up[0] - t[0] * up[2], t[0] * up[1] - t[1] * up[0]], ul = Math.hypot(...u0), u = u0.map(x => x / ul), v = [t[1] * u[2] - t[2] * u[1], t[2] * u[0] - t[0] * u[2], t[0] * u[1] - t[1] * u[0]];
    const ring = (c, k) => { const th = k / sides * Math.PI * 2; return [0, 1, 2].map(i => c[i] + radius * (Math.cos(th) * u[i] + Math.sin(th) * v[i])); };
    for (let k = 0; k < sides; k++) out.push({...p, kind: 'face', closed: true, pts: [ring(a, k), ring(a, k + 1), ring(b, k + 1), ring(b, k)], uid: ++uidN});
  }
  return out;
}
const toHex = c => typeof c === 'string' ? c : '#' + c.map(v => Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16).padStart(2, '0')).join('');
function hsv(h, s, v) { h = ((h % 1) + 1) % 1; const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s); return [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i % 6]; }
function countPrims(g) { if (g.prims.length > 40000) throw Error('Geometry exceeds 40,000 primitives in this study.'); return g; }
function pointsOf(g) { const seen = new Set(), out = []; g.prims.forEach(p => p.pts.forEach(q => { const k = q.map(v => v.toFixed(5)).join(','); if (!seen.has(k)) { seen.add(k); out.push(q); } })); return out; }

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
op('value/polar', 'value', {pos: [['radius', 'float'], ['angle', 'float']], opt: [['height', 'float']], out: 'vec3', fn: ([r, a, h]) => [r * Math.cos(a), h ?? 0, r * Math.sin(a)], doc: 'A point on the ground plane at radius and angle (radians), lifted by height.'});
op('range', 'value', {pos: [['count', 'int']], opt: [['end', 'int']], out: 'list:int', fn: ([a, b]) => { const lo = b === undefined ? 0 : a, hi = b === undefined ? a : b; if (hi - lo > 4096) throw Error(`range ${lo}‥${hi} exceeds 4,096 iterations.`); const o = []; for (let k = lo; k < hi; k++) o.push(k); return o; }});
op('linspace', 'value', {pos: [['from', 'float'], ['to', 'float'], ['count', 'int']], out: 'list:float', fn: ([a, b, n]) => { if (n > 4096) throw Error('linspace exceeds 4,096 values.'); const o = []; for (let k = 0; k < n; k++) o.push(n === 1 ? a : a + (b - a) * k / (n - 1)); return o; }});
op('count', 'value', {pos: [['list', 'list:any']], out: 'int', fn: ([xs]) => xs.length});

const XFORM = [['center', 'vec3', [0, 0, 0]], ['rotation', 'vec3', [0, 0, 0]], ['uniform_scale', 'float', 1, [0.01, 10]]];
const faces = (quads, k) => { const piece = ++uidN; return geo(quads.map(q => prim(place(q, k), true, {tags: {'#piece': piece}}))); };
op('sop/box', 'sop', {kw: [['size', 'vec3', [1, 1, 1], [0.01, 10]], ...XFORM], out: 'geometry',
  fn: (_, k) => { const [a, b, c] = k.size.map(v => v / 2), V = (x, y, z) => [x * a, y * b, z * c];
    return faces([[V(-1, -1, 1), V(1, -1, 1), V(1, 1, 1), V(-1, 1, 1)], [V(1, -1, -1), V(-1, -1, -1), V(-1, 1, -1), V(1, 1, -1)], [V(-1, 1, 1), V(1, 1, 1), V(1, 1, -1), V(-1, 1, -1)], [V(-1, -1, -1), V(1, -1, -1), V(1, -1, 1), V(-1, -1, 1)], [V(1, -1, 1), V(1, -1, -1), V(1, 1, -1), V(1, 1, 1)], [V(-1, -1, -1), V(-1, -1, 1), V(-1, 1, 1), V(-1, 1, -1)]], k); }});
op('sop/uv_sphere', 'sop', {kw: [['radius', 'vec3', [0.5, 0.5, 0.5], [0.01, 10]], ...XFORM, ['segments', 'int', 16, [3, 48]], ['rings', 'int', 8, [2, 32]]], out: 'geometry',
  fn: (_, k) => faces(sphere(k.radius, Math.min(64, k.segments), Math.min(32, k.rings)), k)});
op('sop/tube', 'sop', {kw: [['top_radius', 'float', 0.5, [0, 10]], ['bottom_radius', 'float', 0.5, [0, 10]], ['height', 'float', 1, [0, 10]], ['end_caps', 'bool', true], ...XFORM, ['columns', 'int', 16, [3, 48]]], out: 'geometry',
  fn: (_, k) => { const n = Math.min(64, k.columns), h = k.height / 2, R = (r, y, i) => [r * Math.cos(i / n * Math.PI * 2), y, r * Math.sin(i / n * Math.PI * 2)], q = [];
    for (let i = 0; i < n; i++) q.push([R(k.bottom_radius, -h, i), R(k.bottom_radius, -h, i + 1), R(k.top_radius, h, i + 1), R(k.top_radius, h, i)]);
    if (k.end_caps) { q.push(Array.from({length: n}, (_, i) => R(k.top_radius, h, n - i))); q.push(Array.from({length: n}, (_, i) => R(k.bottom_radius, -h, i))); }
    return faces(q, k); }});
op('sop/torus', 'sop', {kw: [['major_radius', 'float', 1, [0, 10]], ['minor_radius', 'float', 0.25, [0, 10]], ...XFORM, ['rows', 'int', 12, [3, 48]], ['columns', 'int', 24, [3, 64]]], out: 'geometry',
  fn: (_, k) => { const R = k.major_radius, r = k.minor_radius, P = (i, j) => { const u = i / k.columns * Math.PI * 2, v = j / k.rows * Math.PI * 2; return [(R + r * Math.cos(v)) * Math.cos(u), r * Math.sin(v), (R + r * Math.cos(v)) * Math.sin(u)]; }, q = [];
    for (let i = 0; i < k.columns; i++) for (let j = 0; j < k.rows; j++) q.push([P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)]);
    return faces(q, k); }});
op('sop/circle', 'sop', {kw: [['radius', 'float', 0.5, [0, 10]], ['segments', 'int', 32, [3, 96]], ['filled', 'bool', true], ...XFORM], out: 'geometry',
  fn: (_, k) => { const n = Math.max(3, Math.min(256, k.segments)), pts = place(Array.from({length: n}, (_, i) => [k.radius * Math.cos(i / n * Math.PI * 2), 0, k.radius * Math.sin(i / n * Math.PI * 2)]), k); return geo([prim(pts, !!k.filled)]); }});
op('sop/grid', 'sop', {kw: [['width', 'float', 2, [0, 20]], ['height', 'float', 2, [0, 20]], ['columns', 'int', 8, [1, 64]], ['rows', 'int', 8, [1, 64]], ...XFORM], out: 'geometry',
  fn: (_, k) => { const q = [], P = (i, j) => [(i / k.columns - .5) * k.width, 0, (j / k.rows - .5) * k.height];
    for (let i = 0; i < k.columns; i++) for (let j = 0; j < k.rows; j++) q.push([P(i, j), P(i, j + 1), P(i + 1, j + 1), P(i + 1, j)]);
    return faces(q, k); }});
op('sop/line', 'sop', {kw: [['origin', 'vec3', [0, 0, 0]], ['direction', 'vec3', [0, 1, 0]], ['length', 'float', 1, [0, 10]], ['points', 'int', 2, [2, 64]]], out: 'geometry',
  fn: (_, k) => { const n = Math.max(2, Math.min(512, k.points)), l = Math.hypot(...k.direction) || 1, d = k.direction.map(v => v / l);
    return geo([prim(Array.from({length: n}, (_, i) => k.origin.map((o, j) => o + d[j] * k.length * i / (n - 1))), false)]); }});
op('sop/poly_path', 'sop', {pos: [['points', 'list:vec3']], kw: [['closed', 'bool', false]], out: 'geometry', fn: ([pts], k) => geo(pts.length ? [prim(pts.map(p => [...p]), !!k.closed)] : [])});
op('sop/curve', 'sop', {pos: [['points', 'list:vec3']], kw: [['closed', 'bool', false]], out: 'geometry', fn: ([pts], k) => geo(pts.length ? [prim(pts.map(p => [...p]), !!k.closed)] : [])});
op('sop/points', 'sop', {pos: [['points', 'list:vec3']], kw: [['size', 'float', 0.04, [0, 0.5]]], out: 'geometry', fn: ([pts], k) => geo(pts.map(p => prim([[...p]], false, {size: k.size})))});
op('sop/transform', 'sop', {pos: [['input', 'geometry']], kw: [['translate', 'vec3', [0, 0, 0]], ['rotate', 'vec3', [0, 0, 0], [-3.1416, 3.1416]], ['scale', 'vec3', [1, 1, 1], [0, 10]], ['uniform_scale', 'float', 1, [0, 10]]], out: 'geometry',
  fn: ([g], k) => mapPts(g, q => { const s = k.scale, u = k.uniform_scale, r = rotXYZ([q[0] * s[0] * u, q[1] * s[1] * u, q[2] * s[2] * u], k.rotate); return [r[0] + k.translate[0], r[1] + k.translate[1], r[2] + k.translate[2]]; })});
op('sop/merge', 'sop', {rest: 'geometry', restName: 'input', out: 'geometry', fn: (_, __, rest) => countPrims(geo(rest.flatMap(g => g.prims)))});
op('sop/copy_to_points', 'sop', {pos: [['source', 'geometry'], ['targets', 'geometry']], out: 'geometry',
  fn: ([g, t]) => countPrims(geo(pointsOf(t).flatMap((c, k) => g.prims.map(p => ({...p, pts: p.pts.map(q => [q[0] + c[0], q[1] + c[1], q[2] + c[2]]), tags: {...p.tags, '#copy': k}, uid: ++uidN})))))});
op('sop/scatter', 'sop', {pos: [['input', 'geometry']], kw: [['count', 'int', 60, [1, 2000]], ['seed', 'int', 0, [0, 100]]], out: 'geometry',
  fn: ([g], k) => { const fs = g.prims.filter(p => p.kind === 'face'), out = [];
    if (!fs.length) return geo([]);
    const area = fs.map(p => { const n = p.pts.length; let a = 0; for (let i = 1; i + 1 < n; i++) { const u = p.pts[i].map((v, j) => v - p.pts[0][j]), w = p.pts[i + 1].map((v, j) => v - p.pts[0][j]); a += Math.hypot(u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]) / 2; } return a; }), tot = area.reduce((a, b) => a + b, 0) || 1;
    for (let s = 0; s < Math.min(2000, k.count); s++) { let r = hash(k.seed, s, 1) * tot, f = 0; while (f < fs.length - 1 && r > area[f]) { r -= area[f]; f++; }
      const P = fs[f].pts, i = 1 + Math.floor(hash(k.seed, s, 2) * (P.length - 2)); let a = hash(k.seed, s, 3), b = hash(k.seed, s, 4); if (a + b > 1) { a = 1 - a; b = 1 - b; }
      out.push(prim([[0, 1, 2].map(j => P[0][j] + a * (P[i][j] - P[0][j]) + b * (P[i + 1][j] - P[0][j]))], false, {size: 0.04})); }
    return geo(out); }});
op('sop/set_color', 'sop', {pos: [['input', 'geometry']], kw: [['color', 'color', '#285f77'], ['group', 'groupref', '']], out: 'geometry',
  fn: ([g], k) => geo(g.prims.map(p => !k.group || p.groups.includes(k.group) ? {...p, color: toHex(k.color)} : p))});
op('sop/group_bounds', 'sop', {pos: [['input', 'geometry']], kw: [['name', 'group', 'group1'], ['center', 'vec3', [0, 0, 0]], ['size', 'vec3', [1, 1, 1]]], out: 'geometry',
  fn: ([g], k) => geo(g.prims.map(p => { const c = centroid(p); return c.every((v, i) => Math.abs(v - k.center[i]) <= k.size[i] / 2) ? {...p, groups: [...new Set([...p.groups, k.name])]} : p; }))});
op('sop/group_random', 'sop', {pos: [['input', 'geometry']], kw: [['name', 'group', 'group1'], ['probability', 'float', 0.5, [0, 1]], ['seed', 'int', 0, [0, 100]]], out: 'geometry',
  fn: ([g], k) => { const byUid = new Map(); return geo(g.prims.map((p, i) => { const key = p.tags['#piece'] ?? i; if (!byUid.has(key)) byUid.set(key, hash(k.seed, key, 7) < k.probability); return byUid.get(key) ? {...p, groups: [...new Set([...p.groups, k.name])]} : p; })); }});
op('sop/blast', 'sop', {pos: [['input', 'geometry']], kw: [['group', 'groupref', ''], ['selected', 'bool', true], ['owner', 'text', 'Primitives']], out: 'geometry',
  fn: ([g], k) => geo(g.prims.filter(p => p.groups.includes(k.group) !== !!k.selected))});
op('sop/normals', 'sop', {pos: [['input', 'geometry']], kw: [['owner', 'text', 'Vertex']], out: 'geometry', fn: ([g]) => g});
op('sop/subdivide', 'sop', {pos: [['input', 'geometry']], kw: [['iterations', 'int', 1, [0, 4]]], out: 'geometry',
  fn: ([g], k) => { let ps = g.prims; for (let i = 0; i < Math.min(4, k.iterations); i++) ps = ps.flatMap(p => p.kind === 'face' ? subdivideFace(p) : p.kind === 'line' ? [chaikin(p)] : [p]); return countPrims(geo(ps)); }});
op('sop/noise_displace', 'sop', {pos: [['input', 'geometry']], kw: [['amplitude', 'float', 0.1, [0, 2]], ['frequency', 'float', 2, [0, 10]], ['seed', 'int', 0, [0, 100]]], out: 'geometry',
  fn: ([g], k) => mapPts(g, ([x, y, z]) => { const f = k.frequency, a = k.amplitude; return [x + a * noise3(x * f, y * f, z * f, k.seed), y + a * noise3(x * f + 17, y * f - 9, z * f + 3, k.seed), z + a * noise3(x * f - 5, y * f + 11, z * f - 13, k.seed)]; })});
op('sop/polywire', 'sop', {pos: [['input', 'geometry']], kw: [['radius', 'float', 0.03, [0, 1]], ['sides', 'int', 6, [3, 16]]], out: 'geometry',
  fn: ([g], k) => countPrims(geo(g.prims.flatMap(p => p.kind === 'line' ? wire(p, k.radius, Math.max(3, Math.min(16, k.sides))) : [p])))});
op('sop/point_list', 'sop', {pos: [['input', 'geometry']], out: 'list:vec3', fn: ([g]) => pointsOf(g).slice(0, 4096)});
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

// list access: generic over the element type
const lt = j => ts => ts[j] && ts[j].startsWith('list:') ? ts[j] : 'list:any', et = j => ts => elemOf(lt(j)(ts));
const L = ['list', 'list:any'];
op('first', 'value', {pos: [L], out: et(0), fn: ([xs]) => { if (!xs.length) throw Error('first of an empty list.'); return xs[0]; }});
op('last', 'value', {pos: [L], out: et(0), fn: ([xs]) => { if (!xs.length) throw Error('last of an empty list.'); return xs[xs.length - 1]; }});
op('rest', 'value', {pos: [L], out: lt(0), fn: ([xs]) => xs.slice(1)});
op('nth', 'value', {pos: [L, ['index', 'int']], out: et(0), fn: ([xs, i]) => { if (i < 0 || i >= xs.length) throw Error(`nth index ${i} is out of range for a list of length ${xs.length}.`); return xs[i]; }});
op('reverse', 'value', {pos: [L], out: lt(0), fn: ([xs]) => [...xs].reverse()});
op('take', 'value', {pos: [['n', 'int'], L], out: lt(1), fn: ([n, xs]) => xs.slice(0, Math.max(0, n))});
op('drop', 'value', {pos: [['n', 'int'], L], out: lt(1), fn: ([n, xs]) => xs.slice(Math.max(0, n))});

const CONTEXTS = {value: 'float', sop: 'geometry', scene: 'scene', world: 'world', settings: 'settings', editor: 'editor'};
const TYPES = new Set(['float', 'int', 'bool', 'text', 'vec3', 'geometry', 'scene', 'world', 'settings', 'panel', 'editor']);
const NAME = /^[a-z][a-z0-9_-]*$/;
const SPECIAL = new Set(['workspace', 'graph', 'defn', 'defmacro', 'let*', 'ref', 'for', 'fold', 'scan', 'sum', 'if', 'values',
  'fn', 'cond', 'case', 'list', 'concat', 'str', 'get', 'assoc', 'map', 'filter', 'reduce', 'sort-by', 'quote', 'quasiquote', 'unquote', 'unquote-splicing']);
const RESERVED = new Set([...SPECIAL, 't', 'pi', 'true', 'false', 'nil']);
const ZONES = new Set(['for', 'fold', 'scan', 'sum']);
const HOFS = new Set(['map', 'filter', 'reduce', 'sort-by']);
const isOpName = s => !!(OPS[s] || OPS['value/' + s] || Object.keys(CONTEXTS).some(c => OPS[c + '/' + s]));
/* Type expressions in parameters: a type name, fn, (list T) or {:field T …}. Returns a type string or null. */
function typeExpr(x) {
  if (typeof x === 'string') return TYPES.has(x) || x === 'fn' ? x : null;
  if (isMap(x)) { if (x.length % 2) return null; const fs = []; for (let k = 0; k < x.length; k += 2) { const t = isKw(x[k]) && NAME.test(x[k].slice(1)) && typeExpr(x[k + 1]); if (!t || fs.some(q => q[0] === x[k].slice(1))) return null; fs.push([x[k].slice(1), t]); } return recT(fs); }
  if (isCall(x) && x[0] === 'list' && x.length === 2) { const t = typeExpr(x[1]); return t && listOf(t); }
  return null;
}

/* ---------------- shape helpers (shared with the editor) ---------------- */
const body = f => f[f.length - 1];
const paramsOf = f => (f[0] === 'graph' || f[0] === 'defn') && f[4]?.vector && f.length === 6 ? f[4] : vec([]);
function bindings(e) { if (!isL(e) || e[0] !== 'let*') return []; const o = []; for (let i = 0; i < e[1].length; i += 2) o.push({name: e[1][i], expr: e[1][i + 1], index: i}); return o; }
/* Split a call into positional and keyword arguments with their list indices. */
function callArgs(x) {
  const pos = [], kw = {}; for (let i = 1; i < x.length; i++) { if (isKw(x[i])) { kw[x[i].slice(1)] = {idx: i + 1, v: x[i + 1]}; i++; } else pos.push({idx: i, v: x[i]}); }
  return {pos, kw};
}
/* Names a binding pattern binds: a name, [a b …] (nested), {:keys [a b]}, or an annotated (pattern : type). */
function patNames(p, out = []) {
  if (typeof p === 'string') out.push(p);
  else if (isMap(p)) { if (p[1]?.vector) p[1].forEach(n => patNames(n, out)); }
  else if (isL(p) && p.vector) p.forEach(q => patNames(q, out));
  else if (isCall(p) && p[1] === ':') patNames(p[0], out);
  return out;
}
/* Iteration clauses of a zone: [{name (a name or pattern), names, expr, role, at:[vectorIndexInZone, indexInVector]}] */
function zoneVars(z) {
  const h = z[0], out = [];
  const add = (vi, role) => { const v = z[vi]; if (!v?.vector) return; for (let k = 0; k < v.length; k += 2) out.push({name: v[k], names: patNames(v[k]), expr: v[k + 1], role, at: [vi, k + 1]}); };
  if (h === 'fold' || h === 'scan') { add(1, 'acc'); add(2, 'iter'); } else add(1, 'iter');
  return out;
}
const zoneBody = z => z[z.length - 1];
function freeSymbols(x, bound = new Set(), out = new Set()) {
  if (typeof x === 'string') { if (isKw(x) || RESERVED.has(x) || x === ':') return out; const b = x.split('.')[0]; if (!bound.has(b)) out.add(b); return out; }
  if (!isL(x)) return out;
  if (x.vector || isMap(x)) { x.forEach(y => freeSymbols(y, bound, out)); return out; }
  const h = x[0];
  if (h === 'defmacro' || h === 'quote') return out;
  if (h === 'quasiquote') { (function w(y) { if (!isL(y)) return; if (isCall(y) && (y[0] === 'unquote' || y[0] === 'unquote-splicing')) freeSymbols(y[1], bound, out); else y.forEach(w); })(x[1]); return out; }
  if (h === 'let*') { const b = new Set(bound); for (let i = 0; i < (x[1]?.length || 0); i += 2) { freeSymbols(x[1][i + 1], b, out); patNames(x[1][i]).forEach(n => b.add(n)); } freeSymbols(x[2], b, out); return out; }
  if (ZONES.has(h)) { const b = new Set(bound); zoneVars(x).forEach(v => { freeSymbols(v.expr, v.role === 'acc' ? bound : b, out); v.names.forEach(n => b.add(n)); }); freeSymbols(zoneBody(x), b, out); return out; }
  if (h === 'fn') { const b = new Set(bound); if (x[1]?.vector) x[1].forEach(p => patNames(p).forEach(n => b.add(n))); x.slice(2).forEach(y => freeSymbols(y, b, out)); return out; }
  if (h === 'ref') { x.slice(2).forEach(y => freeSymbols(y, bound, out)); return out; }
  // a call head is a dependency when it may be a local function (not an operator or special form)
  if (typeof h === 'string' && !isKw(h) && !RESERVED.has(h) && !h.includes('/') && !isOpName(h) && !bound.has(h)) out.add(h);
  x.slice(1).forEach(y => freeSymbols(y, bound, out)); return out;
}

/* ---------------- macros ----------------
   (defmacro name [a b & rest] `template): ~a substitutes a parameter, ~@rest splices the rest parameter,
   x# is a fresh name x__N (N counts through one expansion, so one call always expands to the same text).
   Every other template symbol must be global (special form, operator, defn, graph, macro, type, t/pi/true/false/nil). */
const isQuasi = m => isCall(m[3]) && m[3][0] === 'quasiquote' && m[3].length === 2;
function macroParams(m) {
  const ps = m[2], req = []; let rest = null;
  for (let k = 0; k < ps.length; k++) {
    const p = ps[k];
    if (p === '&') { if (k !== ps.length - 2 || typeof ps[k + 1] !== 'string' || !NAME.test(ps[k + 1]) || req.includes(ps[k + 1])) throw Error(`Macro ${m[1]}: & is followed by exactly one rest parameter, at the end.`); rest = ps[k + 1]; break; }
    if (typeof p !== 'string' || !NAME.test(p) || req.includes(p)) throw Error(`Macro ${m[1]}: invalid or repeated parameter ${atom(p)}.`);
    req.push(p);
  }
  return {req, rest};
}
function checkMacro(m, known) {
  const {req, rest} = macroParams(m), ps = rest ? [...req, rest] : req;
  if (!isQuasi(m)) { // legacy value template: parameters are substituted by name
    const check = x => { if (isL(x)) { if (x.vector || isMap(x) || !OPS[x[0]] || OPS[x[0]].ctx !== 'value') throw Error('Study macros without a ` template contain value operators only; write `(…) with ~parameters for anything else.'); x.slice(1).forEach(check); } else if (typeof x === 'string' && !ps.includes(x)) throw Error(`Free macro identifier: ${x}.`); };
    check(m[3]); return;
  }
  const ok = s => RESERVED.has(s) || TYPES.has(s) || s === 'fn' || s === ':' || isOpName(s) || known.has(s);
  const walk = y => {
    if (typeof y === 'string') {
      if (isKw(y)) return;
      const b = y.split('.')[0];
      if (b.endsWith('#')) { if (!NAME.test(b.slice(0, -1))) throw Error(`Macro ${m[1]}: ${y} is not a valid fresh name.`); return; }
      if (ok(b)) return;
      throw Error(`Macro ${m[1]}: ${y} would capture a name from the call site. Pass it as a parameter (~${b}) or write ${b}# for a fresh name.`);
    }
    if (!isL(y)) return;
    if (isCall(y) && (y[0] === 'unquote' || y[0] === 'unquote-splicing')) {
      if (y.length !== 2 || typeof y[1] !== 'string' || !ps.includes(y[1])) throw Error(`Macro ${m[1]}: macros unquote only their parameters; ${flat(y)} is not one.`);
      if (y[0] === 'unquote' && y[1] === rest) throw Error(`Macro ${m[1]}: splice the rest parameter with ~@${rest}.`);
      if (y[0] === 'unquote-splicing' && y[1] !== rest) throw Error(`Macro ${m[1]}: ~@ splices the rest parameter only${rest ? ` (~@${rest})` : ''}.`);
      return;
    }
    if (isCall(y) && (y[0] === 'quasiquote' || y[0] === 'quote')) throw Error(`Macro ${m[1]}: nested quoting is not supported.`);
    y.forEach(walk);
  };
  walk(m[3][1]);
}
const countForms = x => isL(x) ? 1 + x.reduce((a, y) => a + countForms(y), 0) : 1;
/* One expansion step of the call x by the macro form m. st = {n, size} carries the fresh-name counter and size budget. */
function macroStep(m, x, st) {
  const {req, rest} = macroParams(m), args = x.slice(1);
  if (rest ? args.length < req.length : args.length !== req.length) throw Error(`${m[1]} expects ${rest ? 'at least ' : ''}${req.length} argument${req.length === 1 ? '' : 's'}; got ${args.length}.`);
  const env = new Map(req.map((p, i) => [p, args[i]])), more = rest ? args.slice(req.length) : [];
  if (!isQuasi(m)) { const sub = y => typeof y === 'string' && env.has(y) ? clone(env.get(y)) : isL(y) ? remap(y, sub) : y; return sub(m[3]); }
  const fresh = new Map();
  const gs = s => { const [b, ...fs] = s.split('.'); if (!b.endsWith('#')) return s; if (!fresh.has(b)) fresh.set(b, b.slice(0, -1) + '__' + (++st.n)); return [fresh.get(b), ...fs].join('.'); };
  const q = y => {
    if (typeof y === 'string') return isKw(y) ? y : gs(y);
    if (!isL(y)) return clone(y);
    if (isCall(y) && y[0] === 'unquote') { if (!env.has(y[1])) throw Error(`Macro ${m[1]}: macros unquote only their parameters; ${flat(y)} is not one.`); return clone(env.get(y[1])); }
    const out = [];
    y.forEach(c => { if (isCall(c) && c[0] === 'unquote-splicing') { if (c[1] !== rest) throw Error(`Macro ${m[1]}: ~@ splices the rest parameter only.`); out.push(...more.map(clone)); } else out.push(q(c)); });
    return copyFlags(y, out);
  };
  return q(m[3][1]);
}
function expandAll(M, x, st, depth) {
  if (!isL(x)) return x;
  if (isCall(x) && (x[0] === 'defmacro' || x[0] === 'quote' || x[0] === 'quasiquote')) return x;
  if (isCall(x) && typeof x[0] === 'string' && M.has(x[0])) {
    if (depth >= 32) throw Error(`Macro expansion exceeds 32 nested expansions (at ${x[0]}).`);
    const y = macroStep(M.get(x[0]), x, st);
    st.size += countForms(y); if (st.size > 5000) throw Error(`Macro expansion of ${x[0]} exceeds 5,000 forms.`);
    return expandAll(M, y, st, depth + 1);
  }
  return remap(x, c => expandAll(M, c, st, depth));
}
function macrosOf(p) {
  if (p instanceof Map) return p;
  if (p && p.macros instanceof Map) return p.macros;
  if (isCall(p) && p[0] === 'workspace') return new Map(p.slice(2).filter(f => isCall(f) && f[0] === 'defmacro').map(f => [f[1], f]));
  throw Error('expand takes a compiled program, a Map of macros or a workspace form.');
}
/* The call with every macro expanded, recursively. */
const expand = (p, x) => expandAll(macrosOf(p), x, {n: 0, size: 0}, 0);
/* One step for a stepper: expands the leftmost-outermost macro call; returns x itself when none is left.
   Pass one state object {n: 0} through all steps to get the same fresh names as expand. */
function expandOnce(p, x, st = {n: 0, size: 0}) {
  const M = macrosOf(p); let done = false;
  const w = y => {
    if (done || !isL(y)) return y;
    if (isCall(y) && (y[0] === 'defmacro' || y[0] === 'quote' || y[0] === 'quasiquote')) return y;
    if (isCall(y) && typeof y[0] === 'string' && M.has(y[0])) { done = true; return macroStep(M.get(y[0]), y, st); }
    const z = remap(y, w); return z;
  };
  const r = w(x); return done ? r : x;
}

/* ---------------- compiler / evaluator ---------------- */
let branchIds = 0;
const usesTime = x => x === 't' || (Array.isArray(x) && x.some(usesTime));
function compile(ast, opts = {}) {
  const time = opts.time ?? 0;
  if (!isL(ast) || ast[0] !== 'workspace' || !NAME.test(ast[1])) throw Error('Expected (workspace name …).');
  const graphs = new Map(), defs = new Map(), macros = new Map(), all = new Set(), branches = new Map();
  for (const f of ast.slice(2)) {
    if (!isCall(f) || !['graph', 'defn', 'defmacro'].includes(f[0])) throw Error('Workspace children are graph, defn and defmacro forms.');
    if (!NAME.test(f[1]) || RESERVED.has(f[1]) || all.has(f[1]) || OPS[f[1]]) throw Error(`Invalid, reserved or duplicate name: ${f[1]}.`);
    all.add(f[1]);
    if (f[0] === 'defmacro') { if (f.length !== 4 || !f[2]?.vector) throw Error(`Invalid macro: ${f[1]}.`); macroParams(f); macros.set(f[1], f); continue; }
    if (f[2] !== ':context' || !CONTEXTS[f[3]] || !(f.length === 5 || (f.length === 6 && f[4]?.vector))) throw Error(`Invalid shape for ${f[1]}: expected (${f[0]} ${f[1]} :context ctx [params] body).`);
    if (f[0] === 'defn' && f.length !== 6) throw Error(`defn ${f[1]} needs a parameter vector.`);
    const used = new Set();
    for (const p of paramsOf(f)) {
      if (!isCall(p) || p.length < 3 || p.length > 4 || p[1] !== ':' || typeof p[0] !== 'string' || !NAME.test(p[0]) || RESERVED.has(p[0]) || used.has(p[0]) || !typeExpr(p[2])) throw Error(`Invalid parameter in ${f[1]}. Each is (name : type default?).`);
      const pt = typeExpr(p[2]);
      if (hasFn(pt) && (pt !== 'fn' || f[0] === 'graph')) throw Error(`${f[1]} input ${p[0]}: a function value cannot be stored or returned (E_FN_ESCAPES); ${f[0] === 'graph' ? 'graph inputs are data' : 'only a defn input may have type fn'}.`);
      if (pt === 'fn' && p.length === 4) throw Error(`${f[1]} input ${p[0]}: a fn input has no default; callers pass a function.`);
      if (f[0] === 'graph' && p.length !== 4) throw Error(`Graph input ${p[0]} of ${f[1]} needs a default, so the graph runs on its own.`);
      used.add(p[0]);
    }
    (f[0] === 'graph' ? graphs : defs).set(f[1], f);
  }
  for (const m of macros.values()) checkMacro(m, all);
  if (!graphs.size) throw Error('A workspace needs at least one graph.');
  const records = new Map(), types = new Map(), zones = new Map(), cache = new Map(), expansions = new WeakMap(), bypassT = new WeakMap();
  const prov = new Set(); // types recorded while a fn body is typed with its declared parameter types; a real call replaces them
  let steps = 0;
  const pT = p => typeExpr(p[2]);
  // which arm a geometry branch took, so a t-driven choice between shapes can be reported (E_TIME_BRANCH)
  function pick(x, E, arm, v) {
    if (v.t === 'geometry') branches.set(E.path + ' ' + (x.bid ??= ++branchIds) + ' ' + E.iters.map(i => i.k).join('.'), arm);
    return v;
  }
  function rec(E, id, v) {
    if (!E) return;
    if (E.mode === 'static') { if (E.prov) { if (!types.has(id)) { types.set(id, v.t); prov.add(id); } } else if (!types.has(id) || types.get(id) === 'any' || prov.delete(id)) types.set(id, v.t); return; }
    if (!E.record) return;
    let a = records.get(id); if (!a) records.set(id, a = []);
    if (a.length < 4096) a.push({it: E.iters.map(z => z.k), v});
  }
  const noFn = (t, what) => { if (hasFn(t)) throw Error(`${what} is a function; a function value cannot be stored or returned (E_FN_ESCAPES). Call it where it is bound.`); };
  const resolveHead = (h, ctx) => defs.has(h) ? {def: defs.get(h)} : macros.has(h) ? {macro: macros.get(h)} : OPS[h] ? {op: OPS[h]} : OPS['value/' + h] ? {op: OPS['value/' + h]} : OPS[ctx + '/' + h] ? {op: OPS[ctx + '/' + h]} : null;
  const expandCall = x => { let y = expansions.get(x); if (!y) { y = expandAll(macros, x, {n: 0, size: 0}, 0); expansions.set(x, y); } return y; };
  function field(v, f, name) {
    if (v.t === 'any') return val('any', undefined);
    if (v.t === 'vec3' && f.length === 1 && 'xyz'.includes(f)) return val('float', v.d === undefined ? undefined : v.d['xyz'.indexOf(f)]);
    const fs = recFields(v.t);
    if (fs) { const h = fs.find(q => q[0] === f); if (!h) throw Error(`${name} has no field ${f}. Fields: ${fs.map(q => q[0]).join(', ') || 'none'}.`); return val(h[1], v.d === undefined ? undefined : v.d[f]); }
    throw Error(`${name} has no output ${f}. A vec3 has .x .y .z; a record has its fields.`);
  }
  /* binding patterns */
  function checkPat(pat, E, seen, form, zone) {
    const shape = typeof pat === 'string' || (pat?.vector && pat.length > 0) || (isMap(pat) && pat.length === 2 && pat[0] === ':keys' && pat[1]?.vector && pat[1].length > 0);
    if (!shape) throw Error(zone ? `${form} binds names; ${patKey(pat)} is not a name or pattern.` : `Invalid binding name ${isL(pat) ? flat(pat) : atom(pat)}. Bind a name, [a b] or {:keys [a b]}.`);
    if (pat.vector) { pat.forEach(p => checkPat(p, E, seen, form, zone)); return; }
    for (const n of patNames(pat)) {
      if (typeof n !== 'string' || !NAME.test(n) || RESERVED.has(n)) throw Error(zone ? `${form} binds names; ${atom(n)} is not a valid one.` : `Invalid binding name ${atom(n)}${n === 't' ? ': t is the context time' : ''}.`);
      if (seen.has(n)) throw Error(`${n} is bound twice in one ${form}.`);
      if (E.env.has(n)) throw Error(zone ? `${n} shadows an outer name. Pick another loop name.` : `${n} shadows an outer name in ${E.scope}. Rename it; the graph cannot show two nodes called ${n} on one wire.`);
      seen.add(n);
    }
  }
  /* Bind pat to v in env; records the whole value at prefix+<printed pattern> and each name at prefix+name. */
  function bindPat(pat, v, env, E, prefix) { if (typeof pat !== 'string') rec(E, prefix + patKey(pat), v); bindParts(pat, v, env, E, prefix); }
  function bindParts(pat, v, env, E, prefix) {
    if (typeof pat === 'string') { env.set(pat, v); rec(E, prefix + pat, v); return; }
    const pk = patKey(pat);
    if (isMap(pat)) {
      if (v.t !== 'any' && !recFields(v.t)) throw Error(`${pk} destructures a record; got ${v.t}.`);
      pat[1].forEach(n => bindParts(n, field(v, n, pk), env, E, prefix)); return;
    }
    let t;
    if (v.t === 'vec3') { t = 'float'; if (pat.length > 3) throw Error(`${pk} needs ${pat.length} elements; a vec3 has 3.`); }
    else if (elemOf(v.t)) t = elemOf(v.t);
    else if (v.t === 'any') t = 'any';
    else throw Error(`${pk} destructures a list or vec3; got ${v.t}.`);
    if (v.d !== undefined && v.d.length < pat.length) throw Error(`${pk} needs ${pat.length} elements; the list has ${v.d.length}.`);
    pat.forEach((p, j) => bindParts(p, val(t, v.d === undefined ? undefined : v.d[j]), env, E, prefix));
  }
  function ev(x, E, bare) {
    if (++steps > 600000) throw Error('Evaluation budget exceeded (600,000 steps). Reduce iteration counts.');
    if (isNum(x)) { const v = numOf(x); if (!Number.isFinite(v)) throw Error('Nonfinite number.'); return val(numIsInt(x) ? 'int' : 'float', v); }
    if (isStr(x)) return val('text', x.text);
    if (typeof x === 'string') {
      if (isKw(x)) throw Error(`Keyword ${x} has no call to belong to.`);
      if (x === 't') return val('float', E.mode === 'static' ? undefined : time);
      if (x === 'pi') return val('float', Math.PI);
      if (x === 'true' || x === 'false') return val('bool', x === 'true');
      if (x === 'nil') return val('geometry', EMPTY);
      const [b, ...fs] = x.split('.');
      if (!E.env.has(b)) throw Error(`${b} is not bound in ${E.scope}.${E.env.size ? ' Bound here: ' + [...E.env.keys()].slice(-6).join(', ') + '.' : ''}`);
      let v = E.env.get(b), path = b;
      for (const f of fs) { v = field(v, f, path); path += '.' + f; }
      return v;
    }
    if (!bare && isL(x) && x.meta?.length) return evBypass(x, E);
    if (isMap(x)) return evRecord(x, 0, E, 'A record');
    if (!isL(x) || !x.length) throw Error('Expected an expression.');
    if (x.vector) {
      if (x.length !== 3) throw Error(`A vector has 3 components [x y z]; this one has ${x.length}.`);
      const cs = x.map(c => ev(c, E)); cs.forEach(c => { if (!NUM.has(c.t) && c.t !== 'any') throw Error(`Vector components are numbers; got ${c.t}.`); });
      return val('vec3', cs.some(c => c.d === undefined) ? undefined : cs.map(c => c.d));
    }
    const [head, ...args] = x;
    if (head === 'let*') return evScope(x, E, E.path + '~');
    if (ZONES.has(head)) return evZone(x, E, E.path + '~' + head);
    if (head === 'fn') return mkFn(x, E, E.path + '~fn', 'fn');
    if (head === 'if') {
      if (args.length !== 3) throw Error('if takes a condition, a then and an else.');
      const c = coerce(ev(args[0], E), 'bool');
      if (!fits(c.t, 'bool')) throw Error(`if needs a bool condition, got ${c.t}.`);
      if (E.mode === 'static' || c.d === undefined) {
        const a = ev(args[1], E), b = ev(args[2], E);
        if (!fits(a.t, b.t) && !fits(b.t, a.t)) throw Error(`Both branches of if must have one type: ${a.t} and ${b.t}.`);
        noFn(a.t, 'An if branch'); noFn(b.t, 'An if branch');
        return val(unify(a.t, b.t) || a.t, undefined);
      }
      return pick(x, E, c.d ? 1 : 2, ev(c.d ? args[1] : args[2], E));
    }
    if (head === 'cond' || head === 'case') return evCond(x, E);
    if (head === 'ref') {
      if (!graphs.has(args[0])) throw Error(`Unknown graph reference: ${args[0]}.`);
      if (E.inDef) throw Error('Reusable functions cannot capture project graphs; add an explicit parameter.');
      const g = graphs.get(args[0]), ps = paramsOf(g), over = {};
      const {kw, pos} = callArgs(x.slice(1)); if (pos.length > 1) throw Error('ref takes a graph name, then :input value pairs.');
      for (const [k, a] of Object.entries(kw)) { const p = ps.find(p => p[0] === k); if (!p) throw Error(`Graph ${args[0]} has no input :${k}. Inputs: ${ps.map(p => p[0]).join(', ') || 'none'}.`); const v0 = ev(a.v, E); noFn(v0.t, `Input :${k} of ${args[0]}`); const v = coerce(v0, pT(p)); if (!fits(v.t, pT(p))) throw Error(`:${k} of ${args[0]} is ${pT(p)}, got ${v.t}.`); over[k] = v; }
      if (E.mode === 'static') return val(CONTEXTS[g[3]], undefined);
      return graph(args[0], E.stack, over);
    }
    if (head === 'values') return evRecord(x, 1, E, 'values');
    if (head === 'list') {
      const vs = args.map(a => ev(a, E)); let t = 'any';
      vs.forEach(v => { noFn(v.t, 'A list element'); const j = joinT(t, v.t); if (!j) throw Error(`List elements share one type; got ${t} and ${v.t}.`); t = j; });
      return val(listOf(t), vs.some(v => v.d === undefined) ? undefined : vs.map(v => coerceD(v.d, v.t, t)));
    }
    if (head === 'concat') {
      const vs = args.map(a => ev(a, E)); let t = 'list:any';
      vs.forEach(v => { if (!elemOf(v.t) && v.t !== 'any') throw Error(`concat joins lists; got ${v.t}.`); const j = joinT(t, v.t === 'any' ? 'list:any' : v.t); if (!j) throw Error(`concat joins lists of one type; got ${t} and ${v.t}.`); t = j; });
      if (vs.some(v => v.d === undefined)) return val(t, undefined);
      const d = vs.flatMap(v => coerceD(v.d, v.t, t)); if (d.length > 4096) throw Error('concat exceeds 4,096 elements.');
      return val(t, d);
    }
    if (head === 'str') { const vs = args.map(a => ev(a, E)); return val('text', vs.some(v => v.d === undefined) ? undefined : vs.map(v => show(v.t, v.d)).join('')); }
    if (head === 'get') {
      if (args.length !== 2 || !isKw(args[1])) throw Error('get is (get record :field).');
      const r = ev(args[0], E); if (!recFields(r.t) && r.t !== 'any') throw Error(`get reads a record field; got ${r.t}.`);
      return field(r, args[1].slice(1), flat(args[0]));
    }
    if (head === 'assoc') {
      if (args.length < 3 || args.length % 2 === 0) throw Error('assoc is (assoc record :field value …).');
      const r = ev(args[0], E), fs = recFields(r.t)?.slice();
      if (!fs) { if (r.t === 'any') return val('any', undefined); throw Error(`assoc updates a record; got ${r.t}.`); }
      let d = r.d === undefined ? undefined : {...r.d};
      for (let k = 1; k < args.length; k += 2) {
        if (!isKw(args[k])) throw Error(`assoc keys are keywords; got ${atom(args[k])}.`);
        const n = args[k].slice(1), v = ev(args[k + 1], E), i = fs.findIndex(q => q[0] === n); noFn(v.t, `Record field :${n}`);
        let nv = v;
        if (i >= 0) { if (!fits(v.t, fs[i][1])) throw Error(`assoc :${n} is ${fs[i][1]}; got ${v.t}.`); nv = coerce(v, fs[i][1]); }
        else fs.push([n, v.t]);
        if (nv.d === undefined) d = undefined; else if (d) d[n] = nv.d;
      }
      return val(recT(fs), d);
    }
    if (HOFS.has(head)) return evHof(head, args, E);
    if (QPRE[head]) throw Error(`${head} belongs in a defmacro template (\`…).`);
    if (typeof head !== 'string') throw Error('A call head is a name.');
    const local = E.env.get(head);
    if (local && (local.t === 'fn' || local.t === 'any')) {
      if (args.some(isKw)) throw Error(`${head} is a local function; it takes positional arguments only.`);
      return callFn(local, args.map(a => evArg(a, E)), E);
    }
    const r = resolveHead(head, E.ctx);
    if (!r) throw Error(local ? `${head} is ${local.t}, not a function.` : `Unknown operator “${head}”.`);
    if (r.macro) return ev(expandCall(x), E);
    if (r.def) return evCall(r.def, x, E);
    return evOp(r.op, x, E);
  }
  function evRecord(x, s, E, what) {
    if ((x.length - s) % 2) throw Error(`${what} is :key value pairs; a key has no value.`);
    const fs = [], d = {}; let known = true;
    for (let k = s; k < x.length; k += 2) {
      if (!isKw(x[k]) || !NAME.test(x[k].slice(1))) throw Error(`${what} keys are keywords like :size; got ${isL(x[k]) ? flat(x[k]) : atom(x[k])}.`);
      const n = x[k].slice(1); if (fs.some(q => q[0] === n)) throw Error(`${what} gives :${n} twice.`);
      const v = ev(x[k + 1], E); noFn(v.t, `Record field :${n}`);
      fs.push([n, v.t]); if (v.d === undefined) known = false; else d[n] = v.d;
    }
    return val(recT(fs), known ? d : undefined);
  }
  function evCond(x, E) {
    const h = x[0], s = h === 'case' ? 2 : 1, a = x.slice(s);
    if ((h === 'case' && x.length < 2) || a.length < 2 || a.length % 2) throw Error(h === 'case' ? 'case is (case value literal result … :else result).' : 'cond is (cond test value … :else value).');
    if (a[a.length - 2] !== ':else') throw Error(`${h} needs a final :else arm, so it always has a value.`);
    const arms = []; for (let k = 0; k < a.length; k += 2) arms.push([a[k], a[k + 1]]);
    const sv = h === 'case' ? ev(x[1], E) : null;
    const test = c => {
      if (h === 'cond') { const v = coerce(ev(c, E), 'bool'); if (!fits(v.t, 'bool')) throw Error(`cond tests are bool; got ${v.t}.`); return v; }
      if (!(isNum(c) || isStr(c) || c === 'true' || c === 'false')) throw Error(`case matches literal numbers, text or booleans; got ${isL(c) ? flat(c) : atom(c)}.`);
      const lv = ev(c, E); if (!fits(lv.t, sv.t) && !fits(sv.t, lv.t)) throw Error(`case compares ${sv.t} with the ${lv.t} literal ${atom(c)}.`);
      if (sv.d === undefined) return val('bool', undefined);
      return val('bool', typeof sv.d === 'boolean' || typeof lv.d === 'boolean' ? !!sv.d === !!lv.d : sv.d === lv.d);
    };
    arms.slice(0, -1).forEach(([c]) => { if (c === ':else') throw Error(`:else is the last arm of ${h}.`); });
    if (E.mode === 'static' || (sv && sv.d === undefined)) {
      let t = null;
      for (const [c, e] of arms) { if (c !== ':else') test(c); const v = ev(e, E); noFn(v.t, `A ${h} arm`); const j = t === null ? v.t : unify(t, v.t); if (!j) throw Error(`All arms of ${h} must have one type: ${t} and ${v.t}.`); t = j; }
      return val(t, undefined);
    }
    for (let k = 0; k < arms.length; k++) { const [c, e] = arms[k]; if (c === ':else' || test(c).d) return pick(x, E, k, ev(e, E)); }
  }
  /* function values */
  function evArg(x, E) { // a bare defn or operator name in a function position is a function value
    if (typeof x === 'string' && !isKw(x) && !E.env.has(x) && !RESERVED.has(x)) {
      const r = resolveHead(x, E.ctx);
      if (r?.def) return val('fn', {kind: 'def', def: r.def, name: x});
      if (r?.op) return val('fn', {kind: 'op', op: r.op, name: x});
      if (r?.macro) throw Error(`${x} is a macro; a macro is not a function value. Wrap it: (fn [a] (${x} a)).`);
    }
    return ev(x, E);
  }
  function evFn(x, E, what) { const v = evArg(x, E); if (v.t !== 'fn' && v.t !== 'any') throw Error(`${what} expects a function (fn, a defn or an operator name); got ${v.t}.`); return v; }
  function mkFn(x, E, id, name) {
    if (x.length !== 3 || !x[1]?.vector) throw Error('fn is (fn [params] body).');
    const seen = new Set();
    const params = x[1].map(p => {
      let pat = p, type = null;
      if (isCall(p) && p[1] === ':') { if (p.length !== 3 || !(type = typeExpr(p[2]))) throw Error(`Invalid fn parameter ${flat(p)}. Annotate it as (name : type).`); pat = p[0]; }
      checkPat(pat, E, seen, 'fn'); return {pat, type};
    });
    const F = {kind: 'closure', params, body: x[2], env: new Map(E.env), id, name, ctx: E.ctx, scope: E.scope + ' › ' + name, stack: E.stack, inDef: !!E.inDef, record: !!E.record, calls: 0};
    const f = val('fn', F), prev = zones.get(id) || {}, vars = params.flatMap(p => patNames(p.pat));
    if (E.mode === 'static') {
      if (!prev.runs) zones.set(id, {...prev, kind: 'fn', vars, count: 0, items: [], args: [], states: [], varTypes: {}});
      callFn(f, params.map(p => val(p.type || 'any', undefined)), {...E, prov: true}); // type the body with its declared types; calls refine it
    } else if (F.record) zones.set(id, {...prev, kind: 'fn', vars, varTypes: prev.varTypes || {}, bodyType: prev.bodyType, count: prev.runs ? prev.count : 0, runs: (prev.runs || 0) + 1, items: prev.runs ? prev.items : [], args: prev.runs ? prev.args : [], states: []});
    return f;
  }
  /* Call a function value with evaluated arguments. A closure call is an iteration frame {zone: fnId, k: callIndex}. */
  function callFn(f, as, E) {
    if (f.t === 'any' || f.d === undefined) return val('any', undefined);
    const F = f.d;
    if (F.kind === 'op') return applyOp(F.op, as.map(v => ({val: v})), {}, E);
    if (F.kind === 'def') return applyDef(F.def, as.map(v => ({val: v})), {}, E);
    if (as.length !== F.params.length) throw Error(`${F.name} takes ${F.params.length} argument${F.params.length === 1 ? '' : 's'}; got ${as.length}.`);
    if ((E.depth || 0) > 64) throw Error('Call depth exceeds 64.');
    const run = E.mode !== 'static', k = run ? F.calls++ : 0, iters = [...E.iters, {zone: F.id, k}], env = new Map(F.env);
    const Ei = {...E, env, ctx: F.ctx, scope: F.scope, path: F.id, iters, stack: [...new Set([...E.stack, ...F.stack])], inDef: F.inDef, record: run ? F.record : E.record, top: false, depth: (E.depth || 0) + 1};
    const argv = F.params.map((p, i) => { const v = p.type ? need(as[i], p.type, `${F.name} ${patKey(p.pat)}`) : as[i]; bindPat(p.pat, v, env, Ei, F.id + '/:'); return v; });
    const v = evBody(F.body, Ei), z = zones.get(F.id);
    if (z && run && F.record) { z.count++; if (z.items.length < 4096) { const it = iters.map(q => q.k); z.items.push({it, v}); z.args.push({it, v: argv}); } }
    else if (z && !run && !z.runs) { z.bodyType = v.t; z.varTypes = {...z.varTypes}; F.params.forEach(p => { patNames(p.pat).forEach(n => { z.varTypes[n] = env.get(n).t; }); if (typeof p.pat !== 'string') z.varTypes[patKey(p.pat)] = argv[F.params.indexOf(p)].t; }); }
    if (run && v.t === 'geometry' && v.d) return val('geometry', geo(v.d.prims.map(p => ({...p, tags: {...p.tags, [F.id]: k}}))));
    return v;
  }
  function evHof(h, args, E) {
    const [lo, hi] = {map: [2, 4], filter: [2, 2], reduce: [3, 3], 'sort-by': [2, 2]}[h];
    if (args.length < lo || args.length > hi) throw Error({map: 'map is (map f list …) with 1–3 lists.', filter: 'filter is (filter pred list).', reduce: 'reduce is (reduce f init list).', 'sort-by': 'sort-by is (sort-by key list).'}[h]);
    const f = evFn(args[0], E, h), init = h === 'reduce' ? ev(args[1], E) : null;
    if (init) noFn(init.t, 'The reduce accumulator');
    const ls = args.slice(h === 'reduce' ? 2 : 1).map(a => { const v = ev(a, E); if (!elemOf(v.t) && v.t !== 'any') throw Error(`${h} iterates a list; got ${v.t}.`); return v; });
    const el = l => elemOf(l.t) || 'any';
    if (E.mode === 'static' || ls.some(l => l.d === undefined) || (init && init.d === undefined)) {
      const SE = E.mode === 'static' ? E : {...E, mode: 'static'};
      const r = callFn(f, h === 'reduce' ? [val(init.t, undefined), val(el(ls[0]), undefined)] : ls.map(l => val(el(l), undefined)), SE);
      if (h === 'map') { noFn(r.t, 'The map result'); return val(listOf(r.t), undefined); }
      if (h === 'filter' && !fits(r.t, 'bool')) throw Error(`filter's predicate returns bool; it returns ${r.t}.`);
      if (h === 'sort-by' && !NUM.has(r.t) && r.t !== 'bool' && r.t !== 'any') throw Error(`sort-by's key returns a number; it returns ${r.t}.`);
      if (h === 'reduce') { noFn(r.t, 'The reduce result'); if (!fits(r.t, init.t)) throw Error(`reduce's function must return the accumulator type ${init.t}; it returns ${r.t}.`); return val(init.t, undefined); }
      return val(ls[0].t, undefined);
    }
    const at = (l, k) => val(el(l), l.d[k]);
    if (h === 'map') {
      const n = Math.min(...ls.map(l => l.d.length)), outs = [];
      for (let k = 0; k < n; k++) outs.push(callFn(f, ls.map(l => at(l, k)), E));
      const t = outs.length ? outs.reduce((a, o) => joinT(a, o.t) || a, 'any') : callFn(f, ls.map(l => val(el(l), undefined)), {...E, mode: 'static'}).t;
      noFn(t, 'The map result');
      return val(listOf(t), outs.map(o => coerceD(o.d, o.t, t)));
    }
    const l = ls[0];
    if (h === 'filter') return val(l.t, l.d.filter((_, k) => coerce(callFn(f, [at(l, k)], E), 'bool').d));
    if (h === 'sort-by') { const keys = l.d.map((_, k) => Number(callFn(f, [at(l, k)], E).d)); return val(l.t, l.d.map((_, k) => k).sort((a, b) => keys[a] - keys[b] || a - b).map(k => l.d[k])); }
    let acc = init; for (let k = 0; k < l.d.length; k++) { const v = callFn(f, [acc, at(l, k)], E); acc = val(init.t, coerceD(v.d, v.t, init.t)); }
    return acc;
  }
  function evBypass(x, E) {
    const bad = x.meta.filter(m => m !== 'bypass');
    if (bad.length) throw Error(`Unknown metadata ^:${bad[0]}. The only metadata is ^:bypass.`);
    const h = x[0], what = typeof h === 'string' ? h : flat(x);
    if (!isCall(x) || typeof h !== 'string' || SPECIAL.has(h) || macros.has(h)) throw Error(`can't bypass ${what}: only operator and function calls pass an input through.`);
    const {pos} = callArgs(x);
    if (!pos.length) throw Error(`can't bypass ${h}: it has no positional input to pass through.`);
    let ct = bypassT.get(x);
    if (ct === undefined) { ct = ev(x, E.mode === 'static' ? E : {...E, mode: 'static'}, true).t; bypassT.set(x, ct); }
    const v = ev(pos[0].v, E);
    if (!fits(v.t, ct) || hasFn(v.t)) throw Error(`can't bypass ${h}: its input is ${v.t} but it returns ${ct}.`);
    return E.mode === 'static' ? val(ct === 'any' ? v.t : ct, undefined) : coerce(v, ct);
  }
  function need(v, want, what) { if (!fits(v.t, want)) throw Error(`${what}: expected ${want.replace('list:', 'list of ')}, got ${v.t.replace('list:', 'list of ')}.`); return coerce(v, want); }
  const astArgs = x => { const {pos, kw} = callArgs(x); return [pos, kw]; }; // argument entries are callArgs entries {v: ast} or evaluated {val}
  const evOp = (o, x, E) => applyOp(o, ...astArgs(x), E);
  function applyOp(o, pos, kw, E) {
    if (o.ctx !== 'value' && o.ctx !== E.ctx) throw Error(`${o.name} belongs to ${o.ctx}; it cannot run in ${E.ctx}. Pass data through a typed input or ref.`);
    const get = a => a.val || ev(a.v, E);
    const slots = [...o.pos, ...(o.opt || [])];
    if (!o.rest && (pos.length < o.pos.length || pos.length > slots.length)) throw Error(`${o.name} takes ${o.pos.length}${o.opt ? '–' + slots.length : ''} positional input${slots.length === 1 ? '' : 's'}${o.pos.length ? ' (' + o.pos.map(p => p[0]).join(', ') + ')' : ''}; got ${pos.length}.`);
    const pv = [], ts = [];
    pos.slice(0, o.rest ? o.pos.length : slots.length).forEach((a, i) => { const s = slots[i], v = get(a); ts.push(v.t); pv.push(o.anyNum && (v.t === 'vec3' || NUM.has(v.t)) ? v : need(v, s[1], `${o.name} ${s[0]}`)); });
    const rest = [];
    if (o.rest) pos.slice(o.pos.length).forEach(a => { const v = get(a); if (elemOf(v.t) && fits(elemOf(v.t), o.rest)) { if (v.d) rest.push(...v.d.map(d => coerce(val(elemOf(v.t), d), o.rest))); else rest.push(val(o.rest, undefined)); } else rest.push(need(v, o.rest, `${o.name} ${o.restName}`)); });
    const kv = {};
    for (const [k, a] of Object.entries(kw)) {
      const s = o.kw.find(s => s[0] === k); if (!s) throw Error(`${o.name} has no parameter :${k}.${o.kw.length ? ' Parameters: ' + o.kw.map(s => ':' + s[0]).join(' ') + '.' : ''}`);
      const want = s[1] === 'group' || s[1] === 'groupref' ? 'text' : s[1];
      kv[k] = need(get(a), want, `${o.name} :${k}`);
    }
    const out = typeof o.out === 'function' ? o.out(ts) : o.out;
    if (E.mode === 'static' || pv.some(v => v.d === undefined) || rest.some(v => v.d === undefined) || Object.values(kv).some(v => v.d === undefined)) return val(out, undefined);
    const k = {}; o.kw.forEach(([n, , d]) => { k[n] = kv[n] ? kv[n].d : d; });
    let d = o.fn(pv.map(v => v.d), k, rest.map(v => v.d));
    if (typeof d === 'number' && !Number.isFinite(d)) throw Error(`${o.name} produced a nonfinite value.`);
    if (out === 'int' && typeof d === 'number') d = Math.round(d);
    return val(out, d);
  }
  const evCall = (def, x, E) => applyDef(def, ...astArgs(x), E);
  function applyDef(def, pos, kw, E) {
    const ctx = def[3]; if (ctx !== 'value' && ctx !== E.ctx) throw Error(`${def[1]} belongs to ${ctx}; it cannot run in ${E.ctx}.`);
    if (E.stack.includes(def[1])) throw Error(`Recursive call: ${[...E.stack, def[1]].join(' → ')}. Use fold for repetition.`);
    const ps = paramsOf(def);
    if (pos.length > ps.length) throw Error(`${def[1]} takes ${ps.length} inputs; got ${pos.length} positional.`);
    const env = new Map();
    ps.forEach((p, i) => {
      const pt = pT(p), a = i < pos.length ? pos[i] : kw[p[0]];
      if (i < pos.length && kw[p[0]]) throw Error(`${def[1]} input ${p[0]} is given twice.`);
      if (!a) { if (p.length === 4) env.set(p[0], coerce(ev(p[3], E), pt)); else throw Error(`${def[1]} needs :${p[0]} (${pt}).`); return; }
      const v = a.val || (pt === 'fn' ? evFn(a.v, E, `${def[1]} :${p[0]}`) : ev(a.v, E));
      env.set(p[0], need(v, pt, `${def[1]} :${p[0]}`));
    });
    Object.keys(kw).forEach(k => { if (!ps.some(p => p[0] === k)) throw Error(`${def[1]} has no input :${k}. Inputs: ${ps.map(p => p[0]).join(', ')}.`); });
    const inner = {...E, env, ctx, stack: [...E.stack, def[1]], scope: 'ƒ ' + def[1], path: 'def:' + def[1], inDef: true, record: !!E.inspect, iters: [], depth: (E.depth || 0) + 1};
    if (inner.record) ps.forEach(p => rec(inner, 'def:' + def[1] + '/:' + p[0], env.get(p[0])));
    return evBody(body(def), inner);
  }
  function evBody(b, E) { return isCall(b) && b[0] === 'let*' && !b.meta?.length ? evScope(b, E, E.path) : evResult(b, E, E.path); }
  function evResult(x, E, path) { const v = evBinding(x, E, path + '/@result'); noFn(v.t, `The result of ${E.scope}`); if (isCall(x)) rec(E, path + '/@result', v); return v; }
  function evBinding(x, E, id) {
    if (isL(x) && x.meta?.length) return ev(x, E);
    if (isCall(x) && ZONES.has(x[0])) return evZone(x, E, id);
    if (isCall(x) && x[0] === 'let*') return evScope(x, E, id);
    return ev(x, E);
  }
  function evScope(x, E, path) {
    if (x.length !== 3 || !x[1]?.vector || x[1].length % 2) throw Error('let* needs [name expression …] and one result.');
    const env = new Map(E.env), seen = new Set();
    for (let i = 0; i < x[1].length; i += 2) {
      const n = x[1][i], expr = x[1][i + 1];
      checkPat(n, E, seen, 'let*');
      const id = path + '/' + patKey(n), Eb = {...E, env, top: false, path: id};
      const v = typeof n === 'string' && isCall(expr) && expr[0] === 'fn' && !expr.meta?.length ? mkFn(expr, Eb, id, n) : evBinding(expr, Eb, id);
      bindPat(n, v, env, E, path + '/');
    }
    return evResult(x[2], {...E, env, top: false}, path);
  }
  function evZone(x, E, id) {
    const h = x[0], vars = zoneVars(x);
    if ((h === 'fold' || h === 'scan') && (x.length !== 4 || !x[1]?.vector || !x[2]?.vector)) throw Error(`${h} is (${h} [acc init] [i collection] body).`);
    if ((h === 'for' || h === 'sum') && (x.length !== 3 || !x[1]?.vector)) throw Error(`${h} is (${h} [i collection …] body).`);
    const seenZ = new Set(); vars.forEach(v => checkPat(v.name, E, seenZ, h, true));
    const iters = vars.filter(v => v.role === 'iter'), accs = vars.filter(v => v.role === 'acc');
    if (!iters.length) throw Error(`${h} needs at least one [name collection] clause.`);
    if ((h === 'fold' || h === 'scan') && accs.length !== 1) throw Error(`${h} carries exactly one accumulator: [acc init]. Carry several values in a record: [{:keys [a b]} {:a 0 :b 1}].`);
    const b = zoneBody(x), inner = {...E, scope: E.scope + ' › ' + id.split('/').pop(), top: false};
    const info = {kind: h, vars: vars.flatMap(v => v.names), count: 0, items: [], states: [], varTypes: {}};
    // static: type the body once
    const colls = [], env0 = new Map(E.env);
    let accT = null;
    if (accs.length) { const iv = ev(accs[0].expr, E); noFn(iv.t, `The ${h} accumulator`); accT = iv.t; bindPat(accs[0].name, val(iv.t, undefined), env0, null); colls.acc = iv; if (typeof accs[0].name !== 'string') info.varTypes[patKey(accs[0].name)] = iv.t; }
    const envS = new Map(env0);
    iters.forEach(v => { const c = ev(v.expr, {...E, env: envS}), t = elemOf(c.t) || (c.t === 'any' ? 'any' : null); if (!t) throw Error(`${patKey(v.name)} in ${h} iterates a list (range, linspace, point_list …); got ${c.t}.`); bindPat(v.name, val(t, undefined), envS, null); colls.push(c); if (typeof v.name !== 'string') info.varTypes[patKey(v.name)] = t; });
    info.vars.forEach(n => { info.varTypes[n] = envS.get(n).t; });
    if (E.mode === 'static') {
      const bt = evBody(b, {...inner, env: envS, path: id, iters: [...E.iters, {zone: id, k: 0}]});
      if (accT && !fits(bt.t, accT)) throw Error(`${h} body must return the accumulator type ${accT}; it returns ${bt.t}.`);
      if (h === 'sum' && !NUM.has(bt.t) && bt.t !== 'vec3' && bt.t !== 'any') throw Error(`sum adds numbers or vec3; the body returns ${bt.t}.`);
      if (!zones.get(id)?.runs) zones.set(id, {...(zones.get(id) || {}), ...info, bodyType: bt.t});
      types.set(id + '/@yield', bt.t); Object.entries(info.varTypes).forEach(([n, t]) => types.set(id + '/:' + n, t));
      return val(h === 'for' || h === 'scan' ? listOf(bt.t) : h === 'sum' ? (bt.t === 'int' ? 'int' : bt.t === 'vec3' ? 'vec3' : 'float') : accT, undefined);
    }
    // run: product iteration, clauses may depend on earlier clause variables
    const outs = [], states = [], items = [];
    let acc = colls.acc || null, k = 0, total = null, sumT = 'int';
    if (acc) states.push({it: [...E.iters.map(z => z.k), -1], v: acc});
    const loop = (ci, env, wh) => {
      if (ci === iters.length) {
        if (k >= 4096) throw Error(`${id.split('/').pop()} runs more than 4,096 iterations.`);
        const envB = new Map(env); if (acc) bindPat(accs[0].name, acc, envB, null);
        const it = [...E.iters, {zone: id, k}], Ei = {...inner, env: envB, path: id, iters: it};
        vars.forEach(v => { if (typeof v.name !== 'string') rec(Ei, id + '/:' + patKey(v.name), v.role === 'acc' ? acc : wh[iters.indexOf(v)]); v.names.forEach(n => rec(Ei, id + '/:' + n, envB.get(n))); });
        const v = evBody(b, Ei);
        const tuple = it.map(z => z.k);
        if (acc) { acc = coerce(v, accT); states.push({it: tuple, v: acc}); if (h === 'scan') outs.push(acc); }
        else if (h === 'sum') { if (v.t === 'vec3') { total = total ? total.map((c, j) => c + v.d[j]) : v.d; sumT = 'vec3'; } else { total = (total || 0) + v.d; if (v.t === 'float') sumT = 'float'; } }
        else outs.push(v);
        items.push({it: tuple, v}); k++; return;
      }
      const c = ci === 0 ? colls[0] : ev(iters[ci].expr, {...E, env});
      if (!c.d) return;
      const t = elemOf(c.t) || 'any';
      for (const item of c.d) { const e2 = new Map(env), w = val(t, item); bindPat(iters[ci].name, w, e2, null); loop(ci + 1, e2, [...wh, w]); }
    };
    loop(0, new Map(E.env), []);
    const prev = zones.get(id) || {};
    if (E.record) zones.set(id, {...prev, ...info, count: (prev.runs ? prev.count : 0) + k, runs: (prev.runs || 0) + 1,
      items: [...(prev.runs ? prev.items : []), ...items].slice(0, 4096), states: [...(prev.runs ? prev.states : []), ...states].slice(0, 4096)});
    if (h === 'fold') return acc;
    if (h === 'sum') return val(total === null ? 'int' : sumT, total === null ? 0 : total);
    const et = outs.reduce((a, o) => joinT(a, o.t) || a, null) || types.get(id + '/@yield') || 'any';
    let data = outs.map(o => coerceD(o.d, o.t, et));
    if (et === 'geometry') data = data.map((g, j) => geo(g.prims.map(p => ({...p, tags: {...p.tags, [id]: j}}))));
    return val(listOf(et), data);
  }
  function graph(name, stack = [], over = null) {
    const key = name + (over && Object.keys(over).length ? JSON.stringify(Object.entries(over).map(([k, v]) => [k, v.d])) : '');
    if (cache.has(key)) return cache.get(key);
    if (stack.includes(name)) throw Error(`Graph cycle: ${[...stack, name].join(' → ')}.`);
    const f = graphs.get(name), env = new Map();
    const E0 = {mode: 'run', ctx: f[3], stack: [...stack, name], scope: name, path: name, iters: [], record: !over, top: true, env};
    paramsOf(f).forEach(p => { env.set(p[0], over?.[p[0]] ? over[p[0]] : coerce(ev(p[3], E0), pT(p))); if (!over) rec(E0, name + '/:' + p[0], env.get(p[0])); });
    const v = evBody(body(f), E0);
    if (!fits(v.t, CONTEXTS[f[3]])) throw Error(`${name} must return ${CONTEXTS[f[3]]}, received ${v.t}.`);
    cache.set(key, v); return v;
  }
  // static pass: types every binding, including untaken branches, zero-iteration loops and function bodies
  for (const [name, f] of defs) {
    const env = new Map(paramsOf(f).map(p => [p[0], val(pT(p), undefined)]));
    paramsOf(f).forEach(p => types.set('def:' + name + '/:' + p[0], pT(p)));
    const t = evBody(body(f), {mode: 'static', ctx: f[3], env, stack: [name], scope: 'ƒ ' + name, path: 'def:' + name, iters: [], inDef: true, top: true});
    types.set('def:' + name, t.t);
  }
  for (const [name, f] of graphs) {
    const env = new Map(paramsOf(f).map(p => [p[0], val(pT(p), undefined)]));
    paramsOf(f).forEach(p => types.set(name + '/:' + p[0], pT(p)));
    const t = evBody(body(f), {mode: 'static', ctx: f[3], env, stack: [name], scope: name, path: name, iters: [], top: true});
    if (!fits(t.t, CONTEXTS[f[3]])) throw Error(`${name} must return ${CONTEXTS[f[3]]}, but its result is ${t.t}.`);
  }
  for (const name of graphs.keys()) graph(name);
  // t may drive parameters, never structure: loop counts and geometry branches must not change with time.
  if (opts.timeCheck !== false && usesTime(ast)) {
    const shape = (zs, rs, bs) => { const o = new Map();
      for (const [k, arm] of bs) o.set('arm  ' + k.split(' ')[0], arm);
      for (const [k, z] of zs) if (z.kind !== 'fn') o.set('zone ' + k, z.count + '×' + (z.runs || 1));
      for (const [k, r] of rs) if (!k.startsWith('def:') && r.some(e => e.v && e.v.t === 'geometry')) o.set('node ' + k, r.length);
      return o; };
    const a = shape(zones, records, branches);
    for (const dt of [0.7, 2.3]) {
      const q = compile(ast, {...opts, time: time + dt, timeCheck: false}), b = shape(q.zones, q.records, q.branches);
      for (const k of new Set([...a.keys(), ...b.keys()])) if (a.get(k) !== b.get(k)) {
        const [kind, id] = [k.slice(0, 4), k.slice(5)];
        throw Error(kind === 'zone'
          ? `E_TIME_COUNT: the number of iterations of ${id} changes with t (${a.get(k)} at t=${time.toFixed(2)}, ${b.get(k)} at t=${(time + dt).toFixed(2)}). Loop counts are fixed while playing; animate parameters instead, for example scale a piece to 0.`
          : kind === 'arm ' ? `E_TIME_BRANCH: a branch in ${id} picks between shapes by t (arm ${a.get(k)} at t=${time.toFixed(2)}, arm ${b.get(k)} at t=${(time + dt).toFixed(2)}). The network keeps its shape while playing; pick a value instead, for example an if on a size or a colour.`
          : `E_TIME_BRANCH: ${id} makes geometry only at some times, so t picks between shapes. Pick with a value instead, for example an if on a size or a colour.`);
      }
    }
  }
  return {ast, graphs, defs, macros, cache, records, types, zones, steps, time, branches,
    expand: x => expandCall(x),
    inspect(fnName, x, ctx, env) { steps = 0; [...records.keys()].forEach(k => k.startsWith('def:') && records.delete(k)); [...zones.keys()].forEach(k => k.startsWith('def:') && zones.delete(k));
      return evCall(defs.get(fnName), x, {mode: 'run', ctx, env, stack: [], scope: 'preview', path: 'preview', iters: [], record: false, inspect: true}); }};
}

const API = {read, print, usesTime, printMarked, compile, OPS, CONTEXTS, SPECIAL, RESERVED, ZONES, HOFS, TYPES, body, bindings, paramsOf, callArgs, zoneVars, zoneBody, freeSymbols,
  clone, vec, str, isStr, isKw, isNum, numOf, mkNum, fmtNum, atom, fits, elemOf, listOf, hash, toHex, bbox, M1, M2,
  mkMap, isMap, isCall, amap, getNote, setNote, patNames, patKey, typeExpr, parseType, formatType, recT, recFields, joinT, hasFn, coerce, show,
  expand, expandOnce, macroParams, isOpName};
if (typeof module !== 'undefined') module.exports = API; else root.Workspace = API;
})(typeof window !== 'undefined' ? window : globalThis);
