/* Browser-only interaction study. The native editor remains PXUI on Metal. */
'use strict';
const M=Workspace,$=s=>document.querySelector(s),$$=s=>[...document.querySelectorAll(s)];
const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const isL=Array.isArray;
const TC={geometry:'geo',float:'float',int:'int',bool:'bool',text:'color',color:'color',vec3:'vec',scene:'vec',panel:'vec',world:'int',settings:'float',editor:'out',group:'color',groupref:'color'};
const tc=t=>t&&t.startsWith('list:')?TC[t.slice(5)]||'out':TC[t]||'out';
const tname=t=>!t?'—':t.startsWith('list:')?t.slice(5)+' ×n':t;
const CTXT=M.CONTEXTS;
const NW=196,RH=24,HH=24,FH=20,RAILW=176,YW=104,STRIP=34,PAD=14,GAP=34;
const ok=(have,want)=>M.fits(have,want==='group'||want==='groupref'?'text':want);
const ZONE_GLYPH={for:'for',fold:'fold',scan:'scan',sum:'Σ','let*':'let'};
const ZONE_LABEL={for:'repeat · collect a list',fold:'feedback · carry a value',scan:'feedback · collect every step',sum:'repeat · add up','let*':'scope · private names'};

let ast,program,scope,selection=new Set(),piece=null,meta={pos:{},collapsed:{}},probe={},past=[],future=[],returnScope=null,
  draft='',dirty=false,codeTab='sel',editing=null,shellKey='',leaves=[],view=null,caseKey='bloom',time=0,playing=false,hoverTag=null;

/* ---------- document ---------- */
function withShell(src){ // cases may omit the scene and editor graphs; the study adds defaults
  const a=M.read(src),has=k=>a.slice(2).some(f=>f[0]==='graph'&&f[3]===k);
  if(!has('scene')){const g=a.slice(2).find(f=>f[0]==='graph'&&f[3]==='sop');a.push(M.read(`(graph scene :context scene (scene/object (ref ${g[1]}) :color "#285f77"))`));}
  if(!has('editor'))a.push(M.read(Cases.EDITOR));
  return a;
}
const compileDoc=a=>M.compile(a,{time});
function loadCase(key,push=true){
  const c=Cases.CASES.find(c=>c.key===key);if(!c)return;
  const next=withShell(c.lisp);
  if(push&&ast){if(!commit(next,`Opened the ${c.title} case study.`,{pos:{},collapsed:{}}))return;}
  else{ast=next;program=compileDoc(ast);draft=M.print(ast);meta={pos:{},collapsed:{}};}
  caseKey=key;probe={};scope=c.focus[0];selection=new Set([c.focus[1]]);piece=null;returnScope=null;
  playing=false;time=0;renderAll();
  requestAnimationFrame(()=>scrollToNode(c.focus[1],true));
}
const curForm=()=>program.graphs.get(scope)||program.defs.get(scope);
const isDef=()=>program.defs.has(scope);
const rootId=()=>(isDef()?'def:':'')+scope;
const editorName=()=>[...program.graphs].find(([,f])=>f[3]==='editor')?.[0];
function countCalls(name){let n=0;(function w(x){if(isL(x)){if(x[0]===name)n++;x.forEach(w);}})(ast.slice(2));return n;}
function describe(v){
  if(!v)return '—';if(v.d===undefined)return tname(v.t);
  const n=x=>Number((+x).toFixed(3)).toString();
  if(v.t==='float'||v.t==='int')return n(v.d);if(v.t==='bool')return v.d?'true':'false';if(v.t==='text')return v.d;
  if(v.t==='vec3')return '['+v.d.map(n).join(' ')+']';
  if(v.t==='geometry')return `${v.d.prims.length} prim${v.d.prims.length===1?'':'s'}${v.d.prims.some(p=>p.groups.length)?' · groups '+[...new Set(v.d.prims.flatMap(p=>p.groups))].join(', '):''}`;
  if(v.t.startsWith('list:'))return `${v.d.length} × ${v.t.slice(5)}`;
  if(v.t==='scene')return `${v.d.items.length} objects`;if(v.t==='panel')return v.d.kind;if(v.t==='world')return v.d.name;return v.t;
}

function scrollToNode(id,reset){const a=view?.abs?.get(id);document.querySelectorAll('.gscroll').forEach(g=>{if(reset){g.scrollLeft=0;g.scrollTop=0;}if(!a)return;
  const w=g.clientWidth,h=g.clientHeight;if(a.x<g.scrollLeft||a.x+Math.min(a.w,w-60)>g.scrollLeft+w)g.scrollLeft=Math.max(0,a.x-40);if(a.y<g.scrollTop||a.y+Math.min(a.h,h-60)>g.scrollTop+h)g.scrollTop=Math.max(0,a.y-40);});}
/* ---------- structure: scopes, zones and nodes projected from the AST ---------- */
const isZone=e=>isL(e)&&!e.vector&&M.ZONES.has(e[0]);
const isScope=e=>isL(e)&&!e.vector&&e[0]==='let*';
const isCall=e=>isL(e)&&!e.vector&&!isZone(e)&&!isScope(e);
function opSpec(head,ctx){if(program.defs.has(head)||program.macros.has(head))return null;return M.OPS[head]||M.OPS['value/'+head]||M.OPS[ctx+'/'+head]||null;}
function argRows(e,ctx){
  if(!isL(e)||e.vector)return [{label:typeof e==='string'&&!M.isKw(e)&&!['t','pi','true','false','nil'].includes(e)?'from':'value',key:{whole:1},type:null,expr:e,sock:true}];
  const h=e[0],{pos,kw}=M.callArgs(e),rows=[];
  if(h==='if'){['if','then','else'].forEach((l,i)=>rows.push({label:l,key:{pos:i},type:i?null:'bool',expr:pos[i]?.v,sock:true}));return rows;}
  if(h==='ref'){rows.push({label:'graph',key:{pos:0},type:'ref',expr:e[1],sock:false});const g=program.graphs.get(e[1]);M.paramsOf(g||[]).forEach(p=>rows.push({label:p[0],key:{kw:p[0]},type:p[2],expr:kw[p[0]]?.v,def:p[3],sock:true}));return rows;}
  const d=program.defs.get(h);
  if(d){M.paramsOf(d).forEach((p,i)=>rows.push(i<pos.length?{label:p[0],key:{pos:i},type:p[2],expr:pos[i].v,sock:true}:{label:p[0],key:{kw:p[0]},type:p[2],expr:kw[p[0]]?.v,def:p[3],sock:true}));return rows;}
  const m=program.macros.get(h);
  if(m){m[2].forEach((p,i)=>rows.push({label:p,key:{pos:i},type:'float',expr:pos[i]?.v,sock:true}));return rows;}
  const o=opSpec(h,ctxOf());
  if(!o)return pos.map((a,i)=>({label:'arg'+(i+1),key:{pos:i},type:null,expr:a.v,sock:true}));
  const slots=[...o.pos,...(o.opt||[])];
  slots.forEach((s,i)=>{if(i<o.pos.length||pos[i])rows.push({label:s[0],key:{pos:i},type:s[1],expr:pos[i]?.v,sock:true});});
  if(o.rest){pos.slice(o.pos.length).forEach((a,j)=>rows.push({label:o.restName+(j?' '+(j+1):''),key:{pos:o.pos.length+j},type:o.rest,expr:a.v,sock:true,rest:true}));
    rows.push({label:'+ '+o.restName,key:{pos:pos.length},type:o.rest,expr:undefined,sock:true,rest:true,add:true});}
  o.kw.forEach(([n,t,d,soft])=>rows.push({label:n,key:{kw:n},type:t,expr:kw[n]?.v,def:d,soft,sock:t!=='text'&&t!=='group'&&t!=='groupref',kwType:t}));
  return rows;
}
const ctxOf=()=>curForm()[3];
function headLabel(e){if(M.isNum(e))return 'number';if(M.isStr(e))return 'text';if(typeof e==='string')return 'link';if(e?.vector)return 'vector';if(isZone(e)||isScope(e))return e[0];return String(e[0]);}
function buildView(){
  const f=curForm(),id=rootId(),params=M.paramsOf(f);
  const root=buildScope(M.body(f),id,[],null,null);
  root.params=[...params].map(p=>({id:id+'/:'+p[0],name:p[0],kind:'param',type:p[2],def:p[3],rows:p.length===4?[{label:'default',key:{param:p[0]},type:p[2],expr:p[3],sock:false}]:[]}));
  params.forEach(p=>root.names.set(p[0],{param:true,id:id+'/:'+p[0]}));
  root.isRoot=true;
  const all=new Map();(function walk(S){S.nodes.forEach(n=>{all.set(n.id,n);if(n.inner)walk(n.inner);});root.params.forEach(p=>all.set(p.id,p));})(root);
  return {root,all};
}
function buildScope(expr,id,path,owner,parent){
  const S={id,path,owner,parent,nodes:[],names:new Map(),rail:[],result:null};
  const isLet=isScope(expr);
  const bs=isLet?M.bindings(expr):[];
  bs.forEach(b=>{const n=mkNode(b.name,b.expr,id+'/'+b.name,{path,name:b.name},S);S.nodes.push(n);S.names.set(b.name,{node:n});});
  const res=isLet?expr[2]:expr;
  if(typeof res==='string'&&S.names.has(res))S.result={link:res,expr:res};
  else if(isL(res)&&!res.vector){const n=mkNode('@result',res,id+'/@result',{path,name:'@result'},S);n.synthetic=true;S.nodes.push(n);S.result={node:n,expr:res};}
  else S.result={expr:res};
  return S;
}
function mkNode(name,expr,id,loc,S){
  const n={id,name,expr,loc,scope:S,kind:'node'};
  if(isZone(expr)||isScope(expr)){
    n.kind='zone';n.zkind=expr[0];
    const inner=isZone(expr)?M.zoneBody(expr):expr;
    n.inner=buildScope(isZone(expr)?inner:expr,id,[...loc.path,name],n,S);
    if(isZone(expr)){M.zoneVars(expr).forEach(v=>{n.inner.rail.push({name:v.name,role:v.role,expr:v.expr,key:{bv:v.at}});n.inner.names.set(v.name,{rail:true});});}
    const bound=new Set(n.inner.rail.map(r=>r.name)),free=M.freeSymbols(isZone(expr)?M.zoneBody(expr):expr,bound);
    [...free].forEach(s=>{if(resolvable(S,s)){n.inner.rail.push({name:s,role:'capture'});n.inner.names.set(s,{rail:true});}});
    n.rows=[];
  }else n.rows=argRows(expr);
  return n;
}
function resolvable(S,name){for(let s=S;s;s=s.parent){if(s.names.has(name))return true;}return program&&curForm()&&M.paramsOf(curForm()).some(p=>p[0]===name);}
/* the zone chain that encloses a scope (outermost first) */
function zoneChain(S){const o=[];for(let s=S;s;s=s.parent)if(s.owner&&isZone(s.owner.expr))o.unshift(s.owner.id);return o;}
function typeOfName(S,name){
  for(let s=S;s;s=s.parent){
    const e=s.names.get(name);if(!e)continue;
    if(e.param)return program.types.get(e.id);
    if(e.node)return program.types.get(e.node.id);
    if(e.rail){const r=s.rail.find(r=>r.name===name);if(r.role==='capture')continue;return program.types.get(s.id+'/:'+name);}
  }
  const p=M.paramsOf(curForm()).find(p=>p[0]===name);return p?p[2]:null;
}
function nodeType(n){return n.kind==='param'?n.type:program.types.get(n.id);}
/* value of a node (or zone variable) at the current probe */
function recordAt(id,chain){
  const rs=program.records.get(id);if(!rs||!rs.length)return null;
  if(!chain.length)return rs[0].v;
  const want=chain.map(z=>probe[z]||0);
  return (rs.find(r=>r.it.length===want.length&&r.it.every((k,i)=>k===want[i]))||null)?.v||null;
}
function seriesOf(id,chain){ // values across the innermost zone at the current outer probe
  const rs=program.records.get(id);if(!rs||!chain.length)return null;
  const outer=chain.slice(0,-1).map(z=>probe[z]||0);
  return rs.filter(r=>r.it.length===chain.length&&outer.every((k,i)=>r.it[i]===k)).map(r=>r.v);
}
/* does a node change from one iteration to the next of its innermost zone? */
function variesIn(n){
  const S=n.scope;if(!S.owner||!isZone(S.owner.expr))return true;
  const vars=new Set(S.rail.filter(r=>r.role!=='capture').map(r=>r.name)),memo=new Map();
  const dep=m=>{if(memo.has(m.id))return memo.get(m.id);memo.set(m.id,false);
    const fs=M.freeSymbols(m.expr);let v=[...fs].some(s=>vars.has(s)||s==='t'&&false);
    if(!v)v=[...fs].some(s=>{const e=S.names.get(s);return e&&e.node&&dep(e.node);});
    if(!v&&m.inner)v=[...M.freeSymbols(m.expr)].some(s=>vars.has(s));
    memo.set(m.id,v);return v;};
  return dep(n);
}

/* ---------- AST addressing: a scope path is binding names from the root ---------- */
function scopeRef(form,path){
  let cont=form,idx=form.length-1;
  for(const name of path){
    const cur=cont[idx];
    let e,ci,cx;
    if(name==='@result'){if(isScope(cur)){ci=cur;cx=2;}else{ci=cont;cx=idx;}}
    else{if(!isScope(cur))throw Error('Scope '+path.join('/')+' no longer exists.');const j=cur[1].indexOf(name);if(j<0||j%2)throw Error('Binding '+name+' no longer exists.');ci=cur[1];cx=j+1;}
    e=ci[cx];
    if(isScope(e)){cont=ci;idx=cx;}
    else if(isZone(e)){cont=e;idx=e.length-1;}
    else throw Error(name+' is not a scope.');
  }
  return {get:()=>cont[idx],set:v=>{cont[idx]=v;}};
}
function ensureLet(ref){const e=ref.get();if(isScope(e))return e;const w=['let*',M.vec([]),e];ref.set(w);return w;}
function getNodeExpr(form,loc){const r=scopeRef(form,loc.path),s=r.get();if(loc.name==='@result')return isScope(s)?s[2]:s;const j=s[1].indexOf(loc.name);return s[1][j+1];}
function setNodeExpr(form,loc,e){const r=scopeRef(form,loc.path),s=r.get();if(loc.name==='@result'){if(isScope(s))s[2]=e;else r.set(e);return;}const j=s[1].indexOf(loc.name);s[1][j+1]=e;}
function getArg(e,key){
  if(key.whole)return e;if(key.bv)return e[key.bv[0]][key.bv[1]];
  const {pos,kw}=M.callArgs(e);if('pos' in key)return pos[key.pos]?.v;return kw[key.kw]?.v;
}
function setArg(e,key,v){
  if(key.whole)return v;e=M.clone(e);
  if(key.bv){e[key.bv[0]][key.bv[1]]=v;return e;}
  const {pos,kw}=M.callArgs(e);
  if('pos' in key){if(pos[key.pos])e[pos[key.pos].idx]=v;else{const firstKw=e.findIndex((x,i)=>i>0&&M.isKw(x));if(firstKw>0)e.splice(firstKw,0,v);else e.push(v);}return e;}
  if(kw[key.kw]){if(v===undefined)e.splice(kw[key.kw].idx-1,2);else e[kw[key.kw].idx]=v;}else if(v!==undefined)e.push(':'+key.kw,v);
  return e;
}
function setSub(e,sub,v){if(!sub||!sub.length)return v;const c=M.clone(e);let x=c;for(let i=0;i<sub.length-1;i++)x=x[sub[i]];x[sub[sub.length-1]]=v;return c;}
function getSub(e,sub){let x=e;for(const i of sub||[])x=x?.[i];return x;}
function allNames(form){const s=new Set(M.paramsOf(form).map(p=>p[0]));(function w(x){if(!isL(x))return;if(isScope(x))for(let i=0;i<x[1].length;i+=2)s.add(x[1][i]);if(isZone(x))M.zoneVars(x).forEach(v=>s.add(v.name));x.forEach(w);})(M.body(form));return s;}
function uniqueName(form,base){const used=allNames(form);base=String(base).replace(/^.*\//,'').replace(/[^a-z0-9_]/g,'_').replace(/^_+|_+$/g,'')||'node';if(!/^[a-z]/.test(base))base='n'+base;let n=base,i=2;while(used.has(n)||M.OPS[n]||M.SPECIAL.has(n)||['t','pi'].includes(n))n=base+'_'+i++;return n;}
/* stable topological reorder of a let* after a rewire; authored order wins when valid */
function reorder(le){
  const ps=[];for(let i=0;i<le[1].length;i+=2)ps.push([le[1][i],le[1][i+1]]);
  const names=new Set(ps.map(p=>p[0])),done=new Set(),out=[];let left=[...ps];
  while(left.length){const i=left.findIndex(([,e])=>[...M.freeSymbols(e)].every(s=>!names.has(s)||done.has(s)));
    if(i<0)throw Error('That connection would make a cycle through '+left.map(p=>p[0]).join(', ')+'.');
    const [n,e]=left.splice(i,1)[0];done.add(n);out.push([n,e]);}
  le[1]=M.vec(out.flat());
}

/* ---------- history ---------- */
function status(message,error=false){const s=$('#status');if(!s)return;s.textContent=message;s.classList.toggle('error',error);}
const snapshot=()=>({source:M.print(ast),meta:structuredClone(meta),caseKey});
function commit(next,message,metaNext=meta){
  if(dirty){status('Unapplied Lisp draft. Apply or discard it in the Document tab first.',true);codeTab='doc';renderAll();return false;}
  try{const checked=compileDoc(next);past.push(snapshot());if(past.length>80)past.shift();future=[];ast=next;program=checked;meta=metaNext;draft=M.print(ast);renderAll();status(message);return true;}
  catch(e){status(e.message,true);return false;}
}
function undo(redo=false){
  if(dirty){status('Apply or discard the Lisp draft before undo.',true);return;}
  const from=redo?future:past,to=redo?past:future;if(!from.length)return;to.push(snapshot());
  const s=from.pop();ast=M.read(s.source);program=compileDoc(ast);meta=s.meta;draft=s.source;caseKey=s.caseKey;
  if(!program.graphs.has(scope)&&!program.defs.has(scope))scope=program.graphs.keys().next().value;
  renderAll();status(redo?'Redid.':'Undid.');
}
function mutate(fn,msg,metaNext=meta,formName=scope){
  const next=M.clone(ast),f=next.slice(2).find(x=>x[1]===formName);
  try{fn(f,next);}catch(e){status(e.message,true);return false;}
  return commit(next,msg,metaNext);
}
/* live edit without a history entry (scrubbing); the gesture commits once on release */
function liveEdit(fn){
  const next=M.clone(ast),f=next.slice(2).find(x=>x[1]===scope);
  try{fn(f);const cp=compileDoc(next);ast=next;program=cp;draft=M.print(ast);renderAll(true);return true;}catch(e){status(e.message,true);return false;}
}
function reorderAt(f,path){const r=scopeRef(f,path),s=r.get();if(isScope(s))reorder(s);}

/* ---------- gestures that rewrite the Lisp ---------- */
function nodeById(id){return view?.all.get(id);}
function editRow(id,key,sub,value,msg,live){
  const n=nodeById(id);if(!n)return false;
  const fn=f=>{
    if(key.param){const p=M.paramsOf(f).find(p=>p[0]===key.param);p[3]=setSub(p[3],sub,value);return;}
    const e=getNodeExpr(f,n.loc);let cur=getArg(e,key);
    setNodeExpr(f,n.loc,setArg(e,key,sub&&sub.length?setSub(cur,sub,value):value));
    reorderAt(f,n.loc.path);
  };
  return live?liveEdit(fn):mutate(fn,msg);
}
function connect(src,id,key,srcRole){
  const n=nodeById(id);if(!n)return;
  if(id.endsWith('/@return')){mutate(f=>{const r=scopeRef(f,[]),s=ensureLet(r);s[2]=src;},`Graph now returns ${src}.`);return;}
  let v=src;
  const cur=getArg(n.kind==='zone'&&key.bv?n.expr:n.expr,key);
  if(srcRole==='iter'&&M.isNum(cur)&&M.numOf(cur)!==0&&M.numOf(cur)!==1){v=['*',src,cur];}
  mutate(f=>{const e=getNodeExpr(f,n.loc);setNodeExpr(f,n.loc,setArg(e,key,v));reorderAt(f,n.loc.path);},
    v===src?`Connected ${src} → ${nodeLabel(n)}.${labelOfKey(n,key)}.`:`${nodeLabel(n)}.${labelOfKey(n,key)} = ${src} × ${M.print(cur)}: each iteration steps by ${M.print(cur)}. Scrub or edit the chip to change the step.`);
}
const nodeLabel=n=>n.synthetic?(n.scope.owner?n.scope.owner.name+' result':'result'):n.name;
function labelOfKey(n,key){if(key.bv)return 'collection';const r=(n.rows||[]).find(r=>JSON.stringify(r.key)===JSON.stringify(key));return r?r.label:'input';}
function defaultFor(type,label){if(type==='float')return 0.5;if(type==='int')return 1;if(type==='bool')return 'false';if(type==='vec3')return M.vec([0,0,0]);if(type==='text'||type==='color')return M.str(label==='color'?'#285f77':'text');if(type==='geometry')return 'nil';return null;}
function disconnect(id,key,row){
  const n=nodeById(id);if(!n)return;
  if(key.kw){mutate(f=>{const e=getNodeExpr(f,n.loc);setNodeExpr(f,n.loc,setArg(e,key,undefined));},`Disconnected ${n.name}.${row.label}; it uses the default again.`);return;}
  if(row?.rest){mutate(f=>{const e=M.clone(getNodeExpr(f,n.loc)),{pos}=M.callArgs(e);e.splice(pos[key.pos].idx,1);setNodeExpr(f,n.loc,e);},`Removed ${row.label} from ${n.name}.`);return;}
  const d=defaultFor(row?.type,row?.label);if(d===null){status(`Nothing to fall back to for a ${row?.type}. Drag another output onto it instead.`,true);return;}
  mutate(f=>{const e=getNodeExpr(f,n.loc);setNodeExpr(f,n.loc,setArg(e,key,d));},`Disconnected ${n.name}.${row?.label}.`);
}
function setRowText(id,key,text,sub){
  let e;try{e=M.read(text);}catch(err){status(err.message,true);return false;}
  if(key.param){const n=nodeById(id);return mutate(f=>{const p=M.paramsOf(f).find(p=>p[0]===key.param);p[3]=e;},`Default of input ${key.param} is ${text}.`);}
  return editRow(id,key,sub,e,`Applied ${nodeById(id)?.name}. Every context re-checked.`);
}
/* unfold: a nested call, loop or scope in a row becomes its own node in the same scope */
const unfoldable=e=>isL(e)&&!e.vector&&e[0]!=='ref';
function unfold(id,key,sub){
  const n=nodeById(id);if(!n)return;const whole=getArg(n.expr,key),e=getSub(whole,sub);if(!unfoldable(e))return;
  const f0=curForm(),nm=uniqueName(f0,isZone(e)?(n.name==='@result'?'each':n.name+'_'+(e[0]==='sum'?'total':'each')):isScope(e)?'block':e[0]);
  if(mutate(f=>{const r=scopeRef(f,n.loc.path),s=ensureLet(r);const cur=getNodeExpr(f,n.loc);const arg=getArg(cur,key);
      setNodeExpr(f,n.loc,setArg(cur,key,sub&&sub.length?setSub(arg,sub,nm):nm));
      const j=n.loc.name==='@result'?s[1].length:s[1].indexOf(n.loc.name);s[1].splice(j,0,nm,M.clone(e));reorder(s);},
    `Unfolded ${nm}${isZone(e)?' into a '+e[0]+' zone':''}. Fold it back with the ƒ on its title.`)){
    selection=new Set([n.scope.id+'/'+nm]);piece=null;renderAll();}
}
/* fold: a node used exactly once in its scope is inlined into that use */
function foldInfo(n){
  if(!n||n.kind==='param'||n.synthetic)return null;
  const S=n.scope;let count=0,consumer=null;
  const users=[...S.nodes.filter(m=>m!==n)];
  users.forEach(m=>{const c=countRefs(m.expr,n.name);if(c){count+=c;consumer=m;}});
  if(S.result?.link===n.name){count++;consumer={name:'result',id:null};}
  if(count!==1||!consumer||!consumer.id)return null;
  return {consumer};
}
function countRefs(x,name){if(x===name)return 1;if(!isL(x))return 0;if(isScope(x)){let c=0;for(let i=0;i<x[1].length;i+=2){if(x[1][i]===name)return c;c+=countRefs(x[1][i+1],name);}return c+countRefs(x[2],name);}return x.reduce((a,y)=>a+countRefs(y,name),0);}
function replaceRef(x,name,e){if(x===name)return M.clone(e);if(!isL(x))return x;const r=x.map(y=>replaceRef(y,name,e));return x.vector?M.vec(r):r;}
function fold(id){
  const n=nodeById(id),info=foldInfo(n);if(!info){status('Fold needs exactly one use of this node inside its scope.',true);return;}
  const c=info.consumer;
  if(mutate(f=>{const r=scopeRef(f,n.loc.path),s=r.get(),j=s[1].indexOf(n.name),e=s[1][j+1];
      const cj=s[1].indexOf(c.name);if(c.name==='@result')s[2]=replaceRef(s[2],n.name,e);else s[1][cj+1]=replaceRef(s[1][cj+1],n.name,e);
      s[1].splice(j,2);if(!s[1].length)r.set(s[2]);},`Folded ${n.name} into ${c.name==='@result'?'the result':c.name}.`)){
    selection=new Set([c.id]);piece=null;renderAll();}
}
function deleteSelected(){
  const ns=[...selection].map(nodeById).filter(n=>n&&n.kind!=='param');if(!ns.length)return;
  for(const n of ns){
    if(n.synthetic){status('This node is its scope’s result. Connect another node to the result first.',true);return;}
    const S=n.scope,user=S.nodes.find(m=>!ns.includes(m)&&M.freeSymbols(m.expr).has(n.name));
    if(user){status(`${n.name} still feeds ${user.name==='@result'?'the result':user.name}. Disconnect it first.`,true);return;}
    if(S.result?.link===n.name){status(`${n.name} is the ${S.isRoot?'graph':'scope'} result. Connect another node to the result first.`,true);return;}
  }
  if(mutate(f=>{ns.sort((a,b)=>b.loc.path.length-a.loc.path.length).forEach(n=>{const r=scopeRef(f,n.loc.path),s=r.get(),j=s[1].indexOf(n.name);s[1].splice(j,2);});},`Deleted ${ns.map(n=>n.name).join(', ')}.`)){selection=new Set();piece=null;renderAll();}
}
/* hoist: a node that is the same in every iteration moves out of its loop */
function hoist(id){
  const n=nodeById(id);if(!n||!n.scope.owner){status('Only a node inside a loop or scope can move out.',true);return;}
  if(variesIn(n)&&isZone(n.scope.owner.expr)){status(`${n.name} changes with the loop variable, so it cannot leave the loop.`,true);return;}
  const S=n.scope,local=[...M.freeSymbols(n.expr)].filter(s=>S.names.get(s)?.node);
  if(local.length){status(`${n.name} uses ${local.join(', ')} from inside this ${S.owner.zkind}. Move ${local.length>1?'those':'that'} out first.`,true);return;}
  const owner=S.owner;
  if(mutate(f=>{const r=scopeRef(f,n.loc.path),s=r.get(),j=s[1].indexOf(n.name),e=s[1][j+1];s[1].splice(j,2);if(!s[1].length)r.set(s[2]);
      const pr=scopeRef(f,owner.loc.path),ps=ensureLet(pr),k=owner.loc.name==='@result'?ps[1].length:ps[1].indexOf(owner.loc.name);ps[1].splice(k,0,n.name,e);reorder(ps);},
    `Moved ${n.name} out of ${owner.name}. It is computed once instead of ${program.zones.get(owner.id)?.count||'n'} times; the result is identical.`)){
    selection=new Set([S.parent.id+'/'+n.name]);renderAll();}
}
/* wrap: selected nodes become the body of a for zone. Geometry results are merged, numbers summed. */
function wrapInLoop(kind){
  const ns=[...selection].map(nodeById).filter(n=>n&&n.kind!=='param'&&!n.synthetic);
  if(!ns.length){status('Select the nodes to repeat first.',true);return;}
  const S=ns[0].scope;if(ns.some(n=>n.scope!==S)){status('Select nodes from one scope.',true);return;}
  const sel=new Set(ns.map(n=>n.name)),others=S.nodes.filter(m=>!sel.has(m.name));
  const outs=ns.filter(n=>others.some(m=>M.freeSymbols(m.expr).has(n.name))||S.result?.link===n.name);
  if(outs.length>1){status('Repeat needs one result leaving the selection; '+outs.map(n=>n.name).join(' and ')+' are both used outside.',true);return;}
  const out=outs[0]||ns[ns.length-1],t=nodeType(out);
  if(kind==='fold'){
    const free=[...new Set(ns.flatMap(n=>[...M.freeSymbols(n.expr)]))].filter(s=>!sel.has(s)&&typeOfName(S,s)&&M.fits(typeOfName(S,s),t));
    if(!free.length){status(`Iterate feeds ${out.name} back into an input of the same type (${t}). None of the selected nodes takes one from outside.`,true);return;}
  }
  if(kind==='for'&&t!=='geometry'&&!M.fits(t,'float')&&outs.length){status(`Repeat collects ${t} values into a list, and ${out.name}'s users expect one ${t}. Repeat works on geometry (merged) or numbers (summed).`,true);return;}
  const f0=curForm(),iv=['i','j','k','n','idx'].find(c=>!visibleFrom(S,c)&&!ns.some(n=>M.freeSymbols(n.expr).has(c)||allNames(['x',M.vec([]),n.expr]).has(c))&&!M.paramsOf(f0).some(p=>p[0]===c))||uniqueName(f0,'i');
  mutate(f=>{
    const r=scopeRef(f,S.path),s=ensureLet(r),pairs=[];for(let i=0;i<s[1].length;i+=2)pairs.push([s[1][i],s[1][i+1]]);
    const inner=pairs.filter(p=>sel.has(p[0])),first=pairs.findIndex(p=>sel.has(p[0])),keep=pairs.filter(p=>!sel.has(p[0]));
    const body=inner.length===1?inner[0][1]:['let*',M.vec(inner.filter(p=>p[0]!==out.name).concat(inner.filter(p=>p[0]===out.name)).flat()),out.name];
    let add;
    if(kind==='fold'){
      const free=[...new Set(ns.flatMap(n=>[...M.freeSymbols(n.expr)]))].filter(x=>!sel.has(x)&&M.fits(typeOfName(S,x),t));
      const acc=uniqueName(f,'prev');
      add=[[out.name,['fold',M.vec([acc,free[0]]),M.vec([iv,['range',4]]),replaceRef(body,free[0],acc)]]];
    }else{
      const each=uniqueName(f,out.name+'_each');
      add=t==='geometry'?[[each,['for',M.vec([iv,['range',6]]),body]],[out.name,['sop/merge',each]]]:[[out.name,['sum',M.vec([iv,['range',6]]),body]]];
    }
    keep.splice(Math.min(first,keep.length),0,...add);s[1]=M.vec(keep.flat());reorder(s);
  },kind==='fold'?`Iterate: ${out.name} now feeds itself back 4 times. Drag the count on the zone to change it.`:`Repeated ${ns.map(n=>n.name).join(', ')} 6 times. Nothing uses ${iv} yet, so every copy is identical. Drag from ${iv} to a number to vary it.`);
  const z=kind==='fold'?S.id+'/'+out.name:S.id+'/'+(t==='geometry'?out.name+'_each':out.name);
  selection=new Set([view.all.has(z)?z:[...view.all.keys()].find(k=>k.startsWith(S.id+'/'+out.name))||z]);piece=null;renderAll();
}
function renameNode(id,to){
  const n=nodeById(id);if(!n||n.synthetic||n.kind==='param')return;
  if(!/^[a-z][a-z0-9_]*$/.test(to)||allNames(curForm()).has(to)||M.OPS[to]||M.SPECIAL.has(to)){status('Pick a new lowercase name that is not used anywhere in this graph.',true);return;}
  mutate(f=>{const r=scopeRef(f,n.loc.path),s=r.get(),j=s[1].indexOf(n.name);s[1][j]=to;for(let k=j+1;k<s[1].length;k+=2)s[1][k]=replaceRef(s[1][k],n.name,to);s[2]=replaceRef(s[2],n.name,to);},`Renamed ${n.name} to ${to}. Every use in its scope follows.`);
  selection=new Set([n.scope.id+'/'+to]);renderAll();
}
/* special-case one iteration: the probed index gets its own value */
function exceptIteration(id,key){
  const n=nodeById(id),zone=n?.scope.owner;if(!zone||!isZone(zone.expr))return;
  const v=zone.inner.rail.find(r=>r.role==='iter');if(!v)return;const k=probe[zone.id]||0;
  const cur=getArg(n.expr,key);
  editRow(id,key,null,['if',['=',v.name,k],M.clone(cur),M.clone(cur)],`Only iteration ${v.name} = ${k} can now differ. Scrub the first value in the chip.`);
}

/* ---------- catalog for the add palette ---------- */
function catalog(){
  const ctx=ctxOf(),list=[];
  list.push({key:'lit:float',title:'number',sub:'literal',out:'float',make:()=>0.5},{key:'lit:vec',title:'vector',sub:'literal [x y z]',out:'vec3',make:()=>M.vec([0,0,0])},{key:'lit:text',title:'text',sub:'literal',out:'text',make:()=>M.str('text')});
  list.push({key:'z:for',title:'for · repeat',sub:'loop · collect a list',out:'list:any',make:()=>['for',M.vec(['i',['range',6]]),ctx==='sop'?['sop/circle',':radius',0.2]:'i']},
    {key:'z:fold',title:'fold · feedback',sub:'loop · carry a value',out:'any',make:()=>['fold',M.vec(['acc',ctx==='sop'?['sop/circle']:0]),M.vec(['i',['range',4]]),ctx==='sop'?['sop/transform','acc',':scale',0.8]:['+','acc','i']]},
    {key:'z:sum',title:'Σ sum',sub:'loop · add numbers',out:'float',make:()=>['sum',M.vec(['k',['range',4]]),'k']},
    {key:'z:let',title:'let · scope',sub:'group bindings with private names',out:'any',make:()=>['let*',M.vec(['a',0.5]),'a']},
    {key:'if',head:'if',title:'if',sub:'choose · bool, then, else',out:'any',make:()=>['if','true',0,1]});
  Object.values(M.OPS).forEach(o=>{if(o.ctx==='value'||o.ctx===ctx)list.push({key:'op:'+o.name,head:o.name,title:o.name,sub:`${o.ctx} · ${[...o.pos.map(p=>p[0]),...(o.rest?[o.restName+'…']:[])].join(', ')||'no inputs'}${o.kw.length?' · :'+o.kw.map(k=>k[0]).join(' :'):''}`,out:typeof o.out==='string'?o.out:'float',op:o});});
  program.defs.forEach((d,k)=>{if((d[3]==='value'||d[3]===ctx)&&k!==scope)list.push({key:'def:'+k,head:k,title:k,sub:`function · ${M.paramsOf(d).map(p=>p[0]).join(', ')}`,out:program.types.get('def:'+k),def:d});});
  program.macros.forEach((m,k)=>list.push({key:'macro:'+k,head:k,title:k,sub:'macro · '+m[2].join(', '),out:'float',make:()=>[k,...m[2].map(()=>0.5)]}));
  if(!isDef())program.graphs.forEach((g,k)=>{if(k!==scope)list.push({key:'ref:'+k,title:`(ref ${k})`,sub:`graph · ${CTXT[g[3]]}`,out:CTXT[g[3]],make:()=>['ref',k]});});
  return list;
}
function buildExpr(entry,src,S){
  if(entry.make)return entry.make();
  const srcT=src?typeOfName(S,src):null;let used=!src;
  if(entry.def){const ps=M.paramsOf(entry.def);const e=[entry.head];ps.forEach(p=>{if(!used&&ok(srcT,p[2])){used=true;e.push(':'+p[0],src);}else if(p.length<4){const d=defaultFor(p[2],p[0]);if(d===null)throw Error(`${entry.title} needs a ${p[2]} input. Drag a wire from one.`);e.push(':'+p[0],d);}});return e;}
  const o=entry.op,e=[o.name];
  o.pos.forEach(([n,t])=>{if(!used&&ok(srcT,t)){used=true;e.push(src);return;}const near=[...S.names.keys()].reverse().find(k=>ok(typeOfName(S,k),t)&&k!==src);const d=defaultFor(t,n);if(d!==null&&t!=='geometry')e.push(d);else if(near)e.push(near);else if(d!==null)e.push(d);else throw Error(`${o.name} needs a ${t} input. Drag a wire from one.`);});
  if(o.rest&&!used&&ok(srcT,o.rest)){used=true;e.push(src);}
  if(!used&&src){const k=o.kw.find(k=>ok(srcT,k[1]));if(k)e.push(':'+k[0],src);}
  return e;
}
function addNode(entry,at,src,S=view.root){
  let expr;try{expr=buildExpr(entry,src,S);}catch(e){status(e.message,true);return false;}
  const base=entry.key.startsWith('z:')?entry.key.slice(2)==='let'?'block':(entry.key.slice(2)==='sum'?'total':'each'):entry.head||(entry.key.startsWith('lit:')?'value':'ref_'+entry.key.split(':')[1]),name=uniqueName(curForm(),base);
  const m=structuredClone(meta);if(at)(m.pos??={})[S.id+'/'+name]={x:Math.max(0,Math.round(at.x/8)*8),y:Math.max(0,Math.round(at.y/8)*8)};
  if(mutate(f=>{const r=scopeRef(f,S.path),s=ensureLet(r);s[1].push(name,expr);reorder(s);},`Added ${name}${S.owner?' inside '+S.owner.name:''}.`,m)){selection=new Set([S.id+'/'+name]);piece=null;renderAll();return true;}
  return false;
}
