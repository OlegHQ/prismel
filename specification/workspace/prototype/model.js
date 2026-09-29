/* Design artifact only. Small checked Lisp interpreter; no eval, native code or build integration. */
(function (root) {
'use strict';
const list = (...xs) => xs;
const vec = xs => Object.assign(xs, {vector:true});
const isList = Array.isArray;
const str = value => ({text:value});
function read(source) {
  if (source.length > 60000) throw Error('Document exceeds the prototype limit of 60,000 characters.');
  const tokens = []; let i = 0;
  while (i < source.length) {
    if (/\s/.test(source[i])) {i++; continue;}
    if (source[i] === ';') {while (i < source.length && source[i] !== '\n') i++; continue;}
    const start = i;
    if ('()[]'.includes(source[i])) {tokens.push({v:source[i++],start}); continue;}
    if (source[i] === '"') {
      i++; let escaped = false;
      while (i < source.length) {const c = source[i++]; if (c === '"' && !escaped) break; escaped = c === '\\' && !escaped;}
      try {tokens.push({v:str(JSON.parse(source.slice(start,i))),start});} catch {throw Error(`Invalid string at character ${start + 1}.`);} continue;
    }
    while (i < source.length && !/[\s()[\];"]/.test(source[i])) i++;
    const raw = source.slice(start,i);
    if (!raw) throw Error(`Unexpected character at ${i+1}.`);
    tokens.push({v:/^-?(?:\d+\.?\d*|\.\d+)$/.test(raw) ? Number(raw) : raw,start});
  }
  let at = 0;
  function take(depth = 0) {
    if (depth > 80) throw Error('Nesting exceeds 80 levels.');
    const token = tokens[at++]; if (!token) throw Error('Unexpected end of source.');
    const x = token.v;
    if (x === '(' || x === '[') {
      const out = [], close = x === '(' ? ')' : ']';
      while (tokens[at]?.v !== close) {if (!tokens[at]) throw Error(`Missing ${close} for character ${token.start+1}.`); out.push(take(depth+1));}
      at++; return x === '[' ? vec(out) : out;
    }
    if (x === ')' || x === ']') throw Error(`Unexpected ${x} at character ${token.start+1}.`);
    return x;
  }
  const result = take(); if (at !== tokens.length) throw Error('Expected one workspace form.'); return result;
}
function print(x, depth = 0) {
  if (!isList(x)) return x && typeof x === 'object' ? JSON.stringify(x.text) : String(x);
  if (x.vector) return '[' + x.map(y=>print(y,depth)).join(' ') + ']';
  const pad = '  '.repeat(depth+1);
  if (x[0] === 'workspace') return `(workspace ${x[1]}\n${pad}${x.slice(2).map(y=>print(y,depth+1)).join('\n\n'+pad)})`;
  if (x[0] === 'graph') return `(${x.slice(0,4).join(' ')}\n${pad}${print(x[4],depth+1)})`;
  if (x[0] === 'defn' || x[0] === 'defgraph') return `(${x.slice(0,4).join(' ')} ${print(x[4])}\n${pad}${print(x[5],depth+1)})`;
  if (x[0] === 'let*') {const rows=[]; for(let i=0;i<x[1].length;i+=2) rows.push(`${x[1][i]} ${print(x[1][i+1],depth+1)}`); return `(let* [${rows.join('\n'+pad+'       ')}]\n${pad}${print(x[2],depth+1)})`;}
  return '(' + x.map(y=>print(y,depth)).join(' ') + ')';
}
const val = (type,data) => ({type,data});
const ops = {
  '+': ['value',['float','float'],'float',(a,b)=>a+b],
  '*': ['value',['float','float'],'float',(a,b)=>a*b],
  '/': ['value',['float','float'],'float',(a,b)=>{if(b===0)throw Error('Division by zero.');return a/b;}],
  sin: ['value',['float'],'float',Math.sin],
  'sop/disc':['sop',['float'],'geometry',r=>{if(r<=0||r>5)throw Error('Radius must be greater than 0 and at most 5.');return {radius:r,count:1,twist:0};}],
  'sop/radial':['sop',['geometry','int'],'geometry',(g,n)=>{if(n<1||n>64)throw Error('Count must be 1–64 in this prototype.');return {...g,count:n};}],
  'sop/twist':['sop',['geometry','float'],'geometry',(g,t)=>({...g,twist:t})],
  'scene/object':['scene',['geometry','text'],'scene',(g,color)=>{if(!/^#[0-9a-f]{6}$/i.test(color))throw Error('Use a six-digit hex color.');return {items:[{...g,color}]};}],
  'scene/merge':['scene',['scene','scene'],'scene',(a,b)=>({items:[...a.items,...b.items]})],
  'world/layer':['world',['scene','text'],'world',(s,name)=>({scene:s,name})],
  'settings/config':['settings',['int','int','float'],'settings',(fps,seed,exposure)=>{if(fps<1||fps>240||exposure<0||exposure>4)throw Error('FPS must be 1–240 and exposure 0–4.');return {fps,seed,exposure};}],
  'ui/viewport':['editor',['scene'],'panel',scene=>({kind:'viewport',scene})],
  'ui/graph':['editor',[],'panel',()=>({kind:'graph'})],
  'ui/inspector':['editor',[],'panel',()=>({kind:'inspector'})],
  'ui/split':['editor',['text','panel','panel'],'panel',(axis,a,b)=>{if(!['horizontal','vertical'].includes(axis))throw Error('Split axis is horizontal or vertical.');return {kind:'split',axis,children:[a,b]};}],
  'ui/floating':['editor',['panel'],'panel',panel=>({kind:'floating',children:[panel]})],
  'ui/workspace':['editor',['panel'],'editor',panel=>({panel})]
};
const contexts = {value:'float',sop:'geometry',scene:'scene',world:'world',settings:'settings',editor:'editor'};
const names = /^[a-z][a-z0-9_-]*$/;
const reserved = new Set(['workspace','graph','defn','defgraph','defmacro','let*','ref','values','if','true','false','nil']);
function body(form) {return form[0] === 'graph' ? form[4] : form[5];}
function bindings(form) {const b=body(form); if(b?.[0]!=='let*')return [];const out=[];for(let i=0;i<b[1].length;i+=2)out.push({name:b[1][i],expr:b[1][i+1],index:i});return out;}
function symbols(expr,out=new Set()) {if(isList(expr)) expr.slice(1).forEach(x=>symbols(x,out)); else if(typeof expr==='string' && !['true','false'].includes(expr))out.add(expr);return out;}
function replace(expr,map) {if(typeof expr==='string' && map.has(expr))return clone(map.get(expr));if(isList(expr)){const r=expr.map(x=>replace(x,map));return expr.vector?vec(r):r;}return expr;}
function clone(x) {return isList(x) ? (x.vector?vec(x.map(clone)):x.map(clone)) : x && typeof x==='object'?{...x}:x;}
function compile(ast) {
  if(!isList(ast)||ast[0]!=='workspace'||!names.test(ast[1]))throw Error('Expected (workspace name …).');
  const graphs=new Map(),defs=new Map(),macros=new Map(),all=new Set();
  for(const f of ast.slice(2)) {
    if(!isList(f)||!['graph','defn','defgraph','defmacro'].includes(f[0]))throw Error('Workspace children must be graph, defn, defgraph or defmacro.');
    if(!names.test(f[1])||reserved.has(f[1])||all.has(f[1])||Object.hasOwn(ops,f[1]))throw Error(`Invalid, reserved or duplicate name: ${f[1]}.`);
    all.add(f[1]);
    if(f[0]==='defmacro') {
      if(f.length!==4||!f[2]?.vector||!f[2].every(x=>names.test(x))||new Set(f[2]).size!==f[2].length)throw Error(`Invalid macro interface: ${f[1]}.`);
      // No introduced bindings/free variables: capture cannot occur in this bounded template subset.
      function check(x){if(isList(x)){if(x.vector||!Object.hasOwn(ops,x[0])||ops[x[0]][0]!=='value')throw Error('Prototype macros contain value operators only; binding macros require hygienic syntax objects.');x.slice(1).forEach(check);}else if(typeof x==='string'&&!f[2].includes(x))throw Error(`Free macro identifier: ${x}.`);}
      check(f[3]);macros.set(f[1],f);continue;
    }
    if(f[2]!==':context'||!Object.hasOwn(contexts,f[3])||f.length!==(f[0]==='graph'?5:6))throw Error(`Invalid context or form shape for ${f[1]}.`);
    if(f[0]==='graph')graphs.set(f[1],f);else {
      if(!f[4]?.vector)throw Error('Function parameters use [(name : type) …].');
      const used=new Set();for(const p of f[4]){if(!isList(p)||p.length!==3||p[1]!==':'||!names.test(p[0])||used.has(p[0])||!['float','int','text','geometry','scene','world','settings','panel','editor'].includes(p[2]))throw Error(`Invalid parameter in ${f[1]}.`);used.add(p[0]);}
      defs.set(f[1],f);
    }
  }
  const cache=new Map(),records=new Map(); let steps=0;
  function evaluate(x,context,env=new Map(),stack=[],scope='',staticOnly=false) {
    if(++steps>20000)throw Error('Evaluation budget exceeded (20,000 expressions).');
    if(typeof x==='number'){if(!Number.isFinite(x))throw Error('Nonfinite number.');return val(Number.isInteger(x)?'int':'float',x);}
    if(x&&typeof x==='object'&&!isList(x))return val('text',x.text);
    if(typeof x==='string'){if(!env.has(x))throw Error(`Unbound name “${x}” in ${scope}.`);return env.get(x);}
    if(!isList(x)||x.vector||!x.length)throw Error('Expected an expression.');
    const [head,...args]=x;
    if(head==='let*') {
      if(args.length!==2||!args[0]?.vector||args[0].length%2)throw Error('let* needs [name expression …] and one result.');
      const local=new Map(env),seen=new Set();
      for(let i=0;i<args[0].length;i+=2){const n=args[0][i];if(!names.test(n)||seen.has(n))throw Error(`Invalid or duplicate binding: ${n}.`);seen.add(n);const v=evaluate(args[0][i+1],context,local,stack,scope,staticOnly);local.set(n,v); if(!staticOnly)records.set(scope+'/'+n,v);}
      return evaluate(args[1],context,local,stack,scope,staticOnly);
    }
    if(head==='ref') {
      if(args.length!==1||!graphs.has(args[0]))throw Error(`Unknown graph reference: ${args[0]}.`);
      if(scope.startsWith('def:'))throw Error('Reusable functions cannot capture project graphs; add an explicit parameter.');
      return graph(args[0],stack);
    }
    if(macros.has(head)){const m=macros.get(head);if(args.length!==m[2].length)throw Error(`${head} expects ${m[2].length} arguments.`);return evaluate(replace(m[3],new Map(m[2].map((p,i)=>[p,args[i]]))),context,env,stack,scope,staticOnly);}
    const definition=defs.get(head),op=Object.hasOwn(ops,head)?ops[head]:null;
    if(!definition&&!op)throw Error(`Unknown operator “${head}”.`);
    const required=definition?definition[3]:op[0];
    if(required!=='value'&&required!==context)throw Error(`${head} belongs to ${required}; it cannot run in ${context}. Pass data through a typed parameter or ref.`);
    const types=definition?definition[4].map(p=>p[2]):op[1];
    if(args.length!==types.length)throw Error(`${head} expects ${types.length} arguments; received ${args.length}.`);
    const values=args.map(a=>evaluate(a,context,env,stack,scope,staticOnly));
    values.forEach((v,i)=>{if(v.type!==types[i]&&!(v.type==='int'&&types[i]==='float'))throw Error(`${head} argument ${i+1}: expected ${types[i]}, received ${v.type}.`);});
    if(definition){if(stack.includes(head))throw Error(`Recursive call: ${[...stack,head].join(' → ')}.`);return evaluate(body(definition),required,new Map(definition[4].map((p,i)=>[p[0],values[i]])),[...stack,head],'def:'+head,staticOnly);}
    if(staticOnly)return val(op[2],undefined);
    const data=op[3](...values.map(v=>v.data));if(typeof data==='number'&&!Number.isFinite(data))throw Error(`${head} produced a nonfinite value.`);return val(op[2],data);
  }
  function graph(name,stack=[]){if(cache.has(name))return cache.get(name);if(stack.includes(name))throw Error(`Graph cycle: ${[...stack,name].join(' → ')}.`);const f=graphs.get(name),v=evaluate(body(f),f[3],new Map(),[...stack,name],name);if(v.type!==contexts[f[3]]&&!(f[3]==='value'&&v.type==='int'))throw Error(`${name} must return ${contexts[f[3]]}, received ${v.type}.`);cache.set(name,v);return v;}
  for(const [name,f] of defs)evaluate(body(f),f[3],new Map(f[4].map(p=>[p[0],val(p[2],undefined)])),[name],'def:'+name,true);
  for(const name of graphs.keys())graph(name);
  if(!graphs.size)throw Error('A workspace needs at least one graph.');
  return {ast,graphs,defs,macros,cache,records,steps,inspectCall(expr,context,env,scope){steps=0;return evaluate(expr,context,env,[],scope);}};
}
const initial=`(workspace bloom_studio
  ; One definition, two calls. Parameters are explicit; no ambient scene state.
  (defn half :context value [(x : float)] (* x 0.5))
  (defmacro twice [x] (+ x x))
  (defn bloom :context sop [(radius : float) (petals : int)]
    (let* [disc (sop/disc radius)
           ring (sop/radial disc petals)] ring))
  (graph geometry :context sop
    (let* [size 0.7
           petals 12
           flower (bloom size petals)
           twist (half 0.8)
           result (sop/twist flower twist)] result))
  (graph accent :context sop
    (let* [flower (bloom 0.35 7)] flower))
  (graph scene :context scene
    (let* [main (scene/object (ref geometry) "#d69f61")
           accent (scene/object (ref accent) "#6fa6a1")
           composed (scene/merge main accent)] composed))
  (graph world :context world
    (let* [layer (world/layer (ref scene) "Bloom study")] layer))
  (graph settings :context settings
    (let* [fps 60
           seed 42
           exposure (twice 0.5)
           config (settings/config fps seed exposure)] config))
  (graph editor :context editor
    (let* [preview (ui/viewport (ref scene))
           network (ui/graph)
           inspector (ui/inspector)
           tools (ui/split "horizontal" network inspector)
           panels (ui/split "vertical" preview tools)
           workspace (ui/workspace panels)] workspace)))`;
const API={read,print,compile,initial,ops,body,bindings,symbols,replace,clone,vec,str};
if(typeof module!=='undefined')module.exports=API;else root.Workspace=API;
})(typeof window!=='undefined'?window:globalThis);
