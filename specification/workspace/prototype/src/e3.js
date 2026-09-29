/* ---------- shell: the workspace is the applied `editor` graph ---------- */
const KINDS=[['outline','Navigator'],['graph','Graph'],['list','List'],['lisp','Lisp'],['inspector','Inspector'],['viewport','Viewport']];
function layoutRoot(){const n=editorName();return n?program.cache.get(n)?.d.panel:null;}
function shapeOf(p){if(p.kind==='split')return `(${p.axis[0]}${p.children.map(shapeOf).join('')})`;if(p.kind==='floating'||p.kind==='tile')return `(${p.kind[0]}${p.children.map(shapeOf).join('')})`;return p.kind[0]+p.kind.length+p.kind.slice(-1);}
function bindingOfPanel(p){const n=editorName();if(!n)return null;for(const [k,v] of program.records)if(k.startsWith(n+'/')&&!k.includes(':')&&v[0]?.v?.d===p){const rest=k.slice(n.length+1);if(!rest.includes('/')&&!rest.includes('~'))return rest;}return null;}
function editorLet(){const f=program.graphs.get(editorName());return f?M.body(f):null;}
function parentOf(name){return M.bindings(editorLet()).find(b=>isL(b.expr)&&['ui/split','ui/split-at','ui/floating','ui/workspace'].includes(b.expr[0])&&b.expr.slice(1).includes(name))||null;}
function editLayout(fn,msg){const n=editorName();return n?mutate(f=>{const s=M.body(f);if(!isScope(s))throw Error('This editor graph is a single expression. Edit it in Lisp.');fn(s,f);reorder(s);},msg,meta,n):false;}
const PANEL_OP={outline:['ui/outline'],graph:['ui/graph'],list:['ui/list'],lisp:['ui/lisp'],inspector:['ui/inspector'],viewport:['ui/viewport',['ref','scene']]};
const setB=(s,name,e)=>{const j=s[1].indexOf(name);s[1][j+1]=e;};
function setKind(p,kind){const name=bindingOfPanel(p);if(!name||kind===p.kind)return;editLayout(s=>setB(s,name,M.clone(PANEL_OP[kind])),`Panel ${name} is now ${kind}.`);}
function splitPanel(p,axis){const name=bindingOfPanel(p);if(!name)return;
  editLayout((s,f)=>{const j=s[1].indexOf(name),a=uniqueName(f,name+'_a'),c=uniqueName(f,name+'_b'),orig=s[1][j+1];
    s[1].splice(j,2,a,orig,c,M.clone(p.kind==='lisp'?PANEL_OP.graph:PANEL_OP.lisp),name,['ui/split-at',M.str(axis),0.5,a,c]);},`Split ${name} ${axis==='horizontal'?'side by side':'top and bottom'}.`);}
function closePanel(p){const name=bindingOfPanel(p);if(!name)return;const par=parentOf(name);
  if(!par||!['ui/split','ui/split-at'].includes(par.expr[0])){status('Only a panel inside a split can close. Restore layout brings the shell back.',true);return;}
  const sibling=par.expr.slice(-2).find(x=>x!==name);
  editLayout(s=>{setB(s,par.name,sibling);const j=s[1].indexOf(name);s[1].splice(j,2);},`Closed panel ${name}.`);}
function setRatio(p,ratio){const name=bindingOfPanel(p);if(!name)return;ratio=Math.round(Math.min(.88,Math.max(.12,ratio))*100)/100;
  editLayout(s=>{const j=s[1].indexOf(name),e=M.clone(s[1][j+1]);if(e[0]==='ui/split-at')e[2]=ratio;else e.splice(0,3,'ui/split-at',e[1],ratio);s[1][j+1]=e;},`Resized ${name} to ${Math.round(ratio*100)}%. The Lisp changed.`);}
const ICON={h:'<svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true"><rect x="1.5" y="2.5" width="9" height="7" fill="none" stroke="currentColor"/><path d="M6 2.5v7" stroke="currentColor"/></svg>',v:'<svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true"><rect x="1.5" y="2.5" width="9" height="7" fill="none" stroke="currentColor"/><path d="M1.5 6h9" stroke="currentColor"/></svg>',x:'<svg viewBox="0 0 12 12" width="12" height="12" aria-hidden="true"><path d="M3 3l6 6M9 3L3 9" stroke="currentColor" fill="none"/></svg>'};
const BODY={
  outline:'<input class="ol-search" placeholder="Go to node, loop, function…  /" aria-label="Go to" autocomplete="off"><div class="ol-tree"></div>',
  graph:'<div class="gscroll" tabindex="0" aria-label="Graph canvas. Drag nodes, drag from an output to an input, double-click to add. Loops are tinted zones."><div class="gcanvas"></div></div>',
  list:'<div class="lbody"></div>',
  lisp:'<div class="ctabs" role="tablist"></div><div class="csel"></div><div class="cdoc" hidden><div class="source-toolbar"><span>Whole workspace · editable draft</span><button class="discard">Discard</button><button class="apply primary">Check &amp; apply<kbd>Ctrl ↵</kbd></button></div><textarea class="doc-src" spellcheck="false" aria-label="Workspace Lisp source"></textarea><div class="source-note">Apply is atomic. Invalid text stays here while every other panel keeps the last valid document.</div></div>',
  inspector:'<div class="ibody"></div>',
  viewport:'<div class="pvwrap"><svg class="pv" role="img" aria-label="Illustrative 2D preview driven by the checked document"></svg></div>'
};
function mkLeaf(p){
  const el=document.createElement('section');el.className='panel';el.dataset.kind=p.kind;
  el.innerHTML=`<header class="phead"><select class="kindsel" aria-label="Panel type">${KINDS.map(([k,l])=>`<option value="${k}"${k===p.kind?' selected':''}>${l}</option>`).join('')}</select><button class="ptitle" title="Show this panel's node in the editor graph"></button><span class="pctl"></span><span class="grow"></span><span class="pbtns"><button class="pbtn" data-act="h" title="Split side by side">${ICON.h}</button><button class="pbtn" data-act="v" title="Split top and bottom">${ICON.v}</button><button class="pbtn" data-act="x" title="Close panel">${ICON.x}</button></span></header><div class="pbody ${p.kind}">${BODY[p.kind]}</div>`;
  el.querySelector('.kindsel').onchange=e=>setKind(el._panel,e.target.value);
  el.querySelector('.ptitle').onclick=()=>{const n=bindingOfPanel(el._panel),ed=editorName();if(ed){returnScope=null;scope=ed;selection=new Set([n?ed+'/'+n:ed+'/sheet']);piece=null;renderAll();}};
  el.querySelectorAll('.pbtn').forEach(b=>b.onclick=()=>{const a=b.dataset.act;if(a==='x')closePanel(el._panel);else splitPanel(el._panel,a==='h'?'horizontal':'vertical');});
  const body=el.querySelector('.pbody');
  if(p.kind==='graph')initGraph(body.querySelector('.gscroll'));
  if(p.kind==='outline')initOutline(body);
  if(p.kind==='lisp')initLisp(body);
  if(p.kind==='viewport')initPreview(body);
  el.querySelector('.pctl').addEventListener('click',e=>{const b=e.target.closest('[data-a]');if(!b)return;({add:()=>openPalette(null,null,view.root),repeat:()=>wrapInLoop('for'),iterate:()=>wrapInLoop('fold'),extract:extractDialog,ret:returnToCall,play:togglePlay})[b.dataset.a]?.();});
  el.querySelector('.pctl').addEventListener('change',e=>{if(e.target.classList.contains('scopesel')){returnScope=null;scope=e.target.value;selection=new Set();piece=null;renderAll();}});
  el.querySelector('.pctl').addEventListener('input',e=>{if(e.target.classList.contains('tslider')){time=Number(e.target.value);playing=false;recompute();}});
  leaves.push(el);return el;
}
function mk(p){
  if(p.kind==='split'&&p.children.some(c=>c.kind==='floating')){
    const fi=p.children.findIndex(c=>c.kind==='floating'),el=document.createElement('div');el.className='split floatwrap';
    const other=mk(p.children[1-fi]),fl=mk(p.children[fi]);el.append(other,fl);el._float={other,fl,fi};return el;}
  if(p.kind==='split'){
    const el=document.createElement('div');el.className='split '+(p.axis==='horizontal'?'h':'v');
    const a=mk(p.children[0]),g=document.createElement('div'),b=mk(p.children[1]);g.className='gutter';g.setAttribute('role','separator');g.tabIndex=0;g.setAttribute('aria-label','Resize panels');
    el.append(a,g,b);el._split={a,b,g};
    g.onpointerdown=e=>{e.preventDefault();g.setPointerCapture(e.pointerId);const r=el.getBoundingClientRect(),h=p.axis==='horizontal';g._live=null;
      g.onpointermove=ev=>{const t=h?(ev.clientX-r.left)/r.width:(ev.clientY-r.top)/r.height;g._live=Math.min(.88,Math.max(.12,t));a.style.flex=`0 0 calc(${g._live*100}% - 3px)`;};
      g.onpointerup=()=>{g.onpointermove=g.onpointerup=null;if(g._live!=null)setRatio(el._panel,g._live);};};
    g.onkeydown=e=>{const step=e.key==='ArrowLeft'||e.key==='ArrowUp'?-.03:e.key==='ArrowRight'||e.key==='ArrowDown'?.03:0;if(step){e.preventDefault();setRatio(el._panel,el._panel.ratio+step);}};
    return el;}
  if(p.kind==='floating'){const el=document.createElement('div');el.className='floating';el.append(mk(p.children[0]));return el;}
  if(p.kind==='tile'){const el=document.createElement('div');el.className='tile';el.style.setProperty('--n',Math.ceil(Math.sqrt(p.children.length)));p.children.forEach(c=>el.append(mk(c)));el._tile=true;return el;}
  return mkLeaf(p);
}
function sync(p,el){
  if(el._float){el._panel=p;const{other,fl,fi}=el._float;sync(p.children[1-fi],other);sync(p.children[fi],fl);}
  else if(p.kind==='split'){el._panel=p;const{a,b}=el._split;a.style.flex=`0 0 calc(${p.ratio*100}% - 3px)`;b.style.flex='1 1 0';sync(p.children[0],a);sync(p.children[1],b);}
  else if(p.kind==='floating'){sync(p.children[0],el.firstElementChild);}
  else if(p.kind==='tile'){el._panel=p;p.children.forEach((c,i)=>sync(c,el.children[i]));}
  else{el._panel=p;}
}
function renderShell(){
  const root=layoutRoot(),shell=$('#shell');
  if(!root){shell.innerHTML='<p class="empty">No editor graph. Restore the layout.</p>';shellKey='';return;}
  const key=shapeOf(root);
  if(key!==shellKey){shellKey=key;leaves=[];shell.innerHTML='';const el=mk(root);el.classList.add('root');shell.append(el);shell._root=el;}
  sync(root,shell._root);
  leaves.forEach(updateLeaf);
}
const usesTime=()=>JSON.stringify(ast).includes('"t"');
function updateLeaf(el){
  const p=el._panel,body=el.querySelector('.pbody'),k=p.kind,nm=bindingOfPanel(p);
  el.querySelector('.kindsel').value=k;el.querySelector('.kindsel').disabled=!nm;
  el.querySelector('.ptitle').textContent=nm?nm:'from a loop';el.querySelector('.ptitle').title=nm?'Show this panel’s node in the editor graph':'This panel is generated by a for in the editor graph. Edit the loop to change it.';
  el.querySelector('.pbtns').hidden=!nm;
  const ctl=el.querySelector('.pctl');
  if(k==='graph'){
    const g=body.querySelector('.gscroll'),sx=g.scrollLeft,sy=g.scrollTop;
    const zSel=[...selection].some(id=>view?.all.get(id));
    ctl.innerHTML=`<select class="scopesel" aria-label="Graph or function">${[...program.graphs.keys()].map(n=>`<option value="${esc(n)}"${n===scope?' selected':''}>${esc(n)}</option>`).join('')}${[...program.defs.keys()].map(n=>`<option value="${esc(n)}"${n===scope?' selected':''}>ƒ ${esc(n)}</option>`).join('')}</select><button data-a="add">Add<kbd>A</kbd></button><button data-a="repeat"${zSel?'':' disabled'} title="Wrap the selection in a for zone">Repeat<kbd>R</kbd></button><button data-a="iterate"${zSel?'':' disabled'} title="Feed the selection back into itself with fold">Iterate<kbd>⇧R</kbd></button><button data-a="extract"${selection.size&&!isDef()?'':' disabled'}>Function<kbd>F</kbd></button>${returnScope?'<button data-a="ret">Return to call</button>':''}`;
    renderGraph(g);g.scrollLeft=sx;g.scrollTop=sy;
  }else if(k==='viewport'){
    const tiled=el.closest('.tile');
    ctl.innerHTML=tiled?`<span class="ptag">${esc(describeScene(p.scene))}</span>`:usesTime()?`<button data-a="play" class="${playing?'on':''}">${playing?'Pause':'Play'}</button><input class="tslider" type="range" min="0" max="6.283" step="0.01" value="${time}" aria-label="Time t"><span class="ptag">t ${time.toFixed(2)}</span>`:'<span class="ptag">static · no t</span>';
    renderPreview(body.querySelector('svg'),p.scene,!!tiled);
  }else if(k==='outline'){ctl.innerHTML='';fillOutline(body);}
  else if(k==='list'){ctl.innerHTML='<span class="ptag">nested bindings</span>';fillList(body);}
  else if(k==='inspector'){ctl.innerHTML='';fillInspector(body.querySelector('.ibody'));}
  else if(k==='lisp'){fillLisp(el,body);}
}
function describeScene(s){return s?.items?`${s.items.length} object${s.items.length===1?'':'s'} · ${s.items.reduce((a,i)=>a+i.geo.prims.length,0)} prims`:'';}
function renderAll(live){
  if(!program.graphs.has(scope)&&!program.defs.has(scope))scope=program.graphs.keys().next().value;
  try{view=buildView();}catch(e){view=null;}
  if(view){selection=new Set([...selection].filter(id=>view.all.has(id)||id.endsWith('/@return')));if(piece&&!view.all.has(piece.id))piece=null;}
  callerPreview();
  renderShell();
  if(!live){$('#undo').disabled=!past.length;$('#redo').disabled=!future.length;}
  const cs=$('#casesel');if(cs&&cs.value!==caseKey)cs.value=caseKey;
}
function recompute(){try{program=compileDoc(ast);renderAll(true);}catch(e){status(e.message,true);}}
function togglePlay(){playing=!playing;renderAll(true);if(playing){let last=performance.now();const tick=now=>{if(!playing)return;if(now-last>50){time=(time+(now-last)/1000)%(Math.PI*2);last=now;recompute();}requestAnimationFrame(tick);};requestAnimationFrame(tick);}}
/* shared definitions preview through one of their calls */
function callerPreview(){
  if(!program.defs.has(scope))return;
  let owner=null,call=null;
  const find=(gname,f)=>{(function w(x,env){if(!isL(x)||call)return;if(x[0]===scope&&!x.vector){call=x;owner=gname;return;}x.forEach(y=>w(y));})(M.body(f));};
  if(returnScope){const f=program.graphs.get(returnScope.scope);if(f)find(returnScope.scope,f);}
  if(!call)for(const [k,f] of program.graphs){find(k,f);if(call)break;}
  if(!call)return;
  const env=new Map();program.records.forEach((rs,k)=>{if(k.startsWith(owner+'/')&&rs[0]){const nm=k.split('/').pop().replace(/^:/,'');if(!env.has(nm))env.set(nm,rs[0].v);}});
  try{program.inspect(scope,call,program.graphs.get(owner)[3],env);}catch(e){}
}

function zoneOwnerChain(zid){const n=view?.all.get(zid);return n?zoneChain(n.scope):[];}
/* ---------- viewport: an illustration, with iteration highlights ---------- */
function focusZone(){
  const tagging=z=>['for'].includes(program.zones.get(z)?.kind)||['fold','scan'].includes(program.zones.get(z)?.kind);
  for(const id of selection){const n=view?.all.get(id);if(!n)continue;const ch=[...zoneChain(n.scope)];if(n.kind==='zone'&&n.zkind!=='let*')ch.push(n.id);for(let i=ch.length-1;i>=0;i--)if(tagging(ch[i]))return ch[i];}
  return null;
}
function initPreview(body){
  const svg=body.querySelector('svg');
  svg.addEventListener('click',e=>{
    const el=e.target.closest('[data-tags]');if(!el)return;const tags=JSON.parse(el.dataset.tags);const keys=Object.keys(tags).filter(k=>!k.startsWith('#'));
    if(!keys.length){status('This shape is not made by a loop.');return;}
    const fz=focusZone(),zid=keys.includes(fz)?fz:keys.sort((a,b)=>b.length-a.length)[0],g=zid.split('/')[0];
    probe[zid]=tags[zid];if(scope!==g){scope=g;returnScope=null;}
    selection=new Set([zid]);piece=null;renderAll();
    const z=program.zones.get(zid);status(`That shape came from ${zid.split('/').pop()}, iteration ${tags[zid]+1} of ${z?.count??'?'}. Every node in the loop now shows its value there.`);
  });
  svg.addEventListener('mousemove',e=>{const el=e.target.closest('[data-tags]');const t=el?el.dataset.tags:null;if(t!==hoverTag){hoverTag=t;svg.querySelectorAll('.hov').forEach(x=>x.classList.remove('hov'));if(el){const tg=JSON.parse(t),fz=focusZone();if(fz&&fz in tg)svg.querySelectorAll('[data-tags]').forEach(x=>{if(JSON.parse(x.dataset.tags)[fz]===tg[fz])x.classList.add('hov');});}}});
}
function renderPreview(svg,scene,small){
  const settings=[...program.cache.values()].find(v=>v.t==='settings')?.d;
  scene=scene||[...program.cache.values()].find(v=>v.t==='scene')?.d;
  const items=scene?.items||[];
  const xf=(it,[x,y])=>[x*it.scale+it.at[0],y*it.scale+it.at[1]];
  let x0=Infinity,y0=Infinity,x1=-Infinity,y1=-Infinity;
  items.forEach(it=>it.geo.prims.forEach(p=>p.pts.forEach(q=>{const [x,y]=xf(it,q);x0=Math.min(x0,x);x1=Math.max(x1,x);y0=Math.min(y0,y);y1=Math.max(y1,y);})));
  if(!isFinite(x0)){x0=-1;y0=-1;x1=1;y1=1;}
  const pad=Math.max(x1-x0,y1-y0)*0.08+0.05;x0-=pad;y0-=pad;x1+=pad;y1+=pad;
  svg.setAttribute('viewBox',`${x0} ${-y1} ${x1-x0} ${y1-y0}`);svg.setAttribute('preserveAspectRatio','xMidYMid meet');
  const fz=small?null:focusZone(),zk=fz?program.zones.get(fz):null,k=fz?probe[fz]||0:0;
  const tagged=fz&&items.some(it=>it.geo.prims.some(p=>fz in p.tags));
  const exposure=Math.min(1,(settings?.exposure??1));
  let h='';
  const pt=(it,q)=>{const [x,y]=xf(it,q);return `${x.toFixed(4)},${(-y).toFixed(4)}`;};
  items.forEach(it=>it.geo.prims.forEach(p=>{
    const col=p.color||it.color,cls=tagged?(p.tags[fz]===k?' hi':' dim'):'',tags=esc(JSON.stringify(p.tags));
    if(p.point||p.pts.length===1){const [x,y]=xf(it,p.pts[0]);h+=`<circle class="pp${cls}" cx="${x}" cy="${-y}" r="${(p.point||0.03)*it.scale}" fill="${col}" data-tags="${tags}"/>`;}
    else if(p.closed)h+=`<polygon class="pp${cls}" points="${p.pts.map(q=>pt(it,q)).join(' ')}" fill="${col}" fill-opacity="${(p.color?0.82:0.14)*exposure}" stroke="${col}" data-tags="${tags}"/>`;
    else h+=`<polyline class="pp line${cls}" points="${p.pts.map(q=>pt(it,q)).join(' ')}" stroke="${col}" data-tags="${tags}"/>`;
  }));
  if(zk&&(zk.kind==='fold'||zk.kind==='scan')&&items[0]){
    const st=zk.states.filter(s=>s.it[s.it.length-1]===k)[0];
    if(st&&st.v.t==='geometry')h+=st.v.d.prims.map(p=>p.pts.length>1?`<${p.closed?'polygon':'polyline'} class="fghost" points="${p.pts.map(q=>pt(items[0],q)).join(' ')}"/>`:'').join('');
  }
  svg.innerHTML=`<rect class="pvbg" x="${x0}" y="${-y1}" width="${x1-x0}" height="${y1-y0}"/>`+h;
  if(!small){const per=zk?(zk.kind==='fold'||zk.kind==='scan'?zk.states.filter(s=>s.it[s.it.length-1]>=0):zk.items).filter(r=>r.it.length===1||r.it.slice(0,-1).every((x,i)=>x===(probe[zoneOwnerChain(fz)[i]]||0))).length:0;
    svg.parentElement.dataset.label=fz?`${fz.split('/').pop()} · ${zk?.kind==='fold'||zk?.kind==='scan'?'state after step':'iteration'} ${k+1} of ${per}${tagged||zk?.kind!=='for'?'':' · not in this scene'}`:describeScene(scene);}
}
