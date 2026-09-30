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
  viewport:'<div class="pvwrap"><canvas class="pv" role="img" aria-label="Illustrative 3D preview driven by the checked document. Drag to orbit, scroll to zoom, click a shape to find what made it."></canvas></div>'
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
  el.querySelector('.pctl').addEventListener('click',e=>{const b=e.target.closest('[data-a]');if(!b)return;({add:()=>openPalette(null,null,view.root),repeat:()=>wrapInLoop('for'),iterate:()=>wrapInLoop('fold'),extract:extractDialog,lambda:makeLocalFn,macro:makeMacroDialog,ret:returnToCall,play:togglePlay})[b.dataset.a]?.();});
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
    ctl.innerHTML=`<select class="scopesel" aria-label="Graph or function">${[...program.graphs.keys()].map(n=>`<option value="${esc(n)}"${n===scope?' selected':''}>${esc(n)}</option>`).join('')}${[...program.defs.keys()].map(n=>`<option value="${esc(n)}"${n===scope?' selected':''}>ƒ ${esc(n)}</option>`).join('')}</select><button data-a="add">Add<kbd>A</kbd></button><button data-a="repeat"${zSel?'':' disabled'} title="Wrap the selection in a for zone">Repeat<kbd>R</kbd></button><button data-a="iterate"${zSel?'':' disabled'} title="Feed the selection back into itself with fold">Iterate<kbd>⇧R</kbd></button><button data-a="lambda"${zSel?'':' disabled'} title="Turn the selection into a local function (λ)">λ<kbd>L</kbd></button><button data-a="macro"${zSel?'':' disabled'} title="Turn the selection into a macro template">◆<kbd>M</kbd></button><button data-a="extract"${selection.size&&!isDef()?'':' disabled'} title="Make a shared top-level function">defn<kbd>F</kbd></button>${returnScope?'<button data-a="ret">Return to call</button>':''}`;
    renderGraph(g);g.scrollLeft=sx;g.scrollTop=sy;
  }else if(k==='viewport'){
    const tiled=el.closest('.tile');
    const pb=!tiled&&usesTime()&&ctl.querySelector('[data-a="play"]'),c=liveCounts();
    if(pb){ // update in place: rebuilding the controls every tick would detach Pause under the pointer
      pb.textContent=playing?'Pause':'Play';pb.classList.toggle('on',playing);
      const sl=ctl.querySelector('.tslider');if(document.activeElement!==sl)sl.value=time;
      ctl.querySelector('.ttag').textContent=`t ${time.toFixed(2)}`;ctl.querySelector('.live-read').textContent=`◷ ${c.live} live · ${c.cached} cached · ${cookMs.toFixed(1)} ms`;
    }else ctl.innerHTML=tiled?`<span class="ptag">${esc(describeScene(p.scene))}</span>`:usesTime()?`<button data-a="play" class="${playing?'on':''}">${playing?'Pause':'Play'}</button><input class="tslider" type="range" min="0" max="6.283" step="0.01" value="${time}" aria-label="Time t"><span class="ptag ttag">t ${time.toFixed(2)}</span>${(()=>{return `<span class="ptag live-read" title="In ${esc(scope)}: nodes marked ◷ t recook each frame; the rest are cached. The study recompiles everything; Prismel recooks only the live nodes.">◷ ${c.live} live · ${c.cached} cached · ${cookMs.toFixed(1)} ms</span>`;})()}`:'<span class="ptag">static · no t</span>';
    renderPreview(body.querySelector('canvas'),p.scene,!!tiled);
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
  const tagging=z=>['for','fold','scan','fn'].includes(program.zones.get(z)?.kind);
  for(const id of selection){const n=view?.all.get(id);if(!n)continue;const ch=[...zoneChain(n.scope)];if(n.kind==='zone'&&n.zkind!=='let*')ch.push(n.id);for(let i=ch.length-1;i>=0;i--)if(tagging(ch[i]))return ch[i];}
  return null;
}
/* ---------- viewport: a small 3D painter's-algorithm renderer (an illustration, not Metal) ---------- */
const CAM=new WeakMap();
function camOf(cv){let c=CAM.get(cv);if(!c){c={yaw:-0.7,pitch:0.45,zoom:1,key:''};CAM.set(cv,c);}return c;}
function rgbOf(hex){const h=String(hex||'#888888').replace('#','');const n=parseInt(h.length===3?h.split('').map(c=>c+c).join(''):h.slice(0,6),16);return [(n>>16)&255,(n>>8)&255,n&255];}
function cssVar(n,fb){try{return getComputedStyle(document.documentElement).getPropertyValue(n).trim()||fb;}catch(e){return fb;}}
/* draw scene items into a canvas; returns the drawn list for picking */
function drawScene(cv,items,opt={}){
  const dpr=Math.min(2,window.devicePixelRatio||1),W=Math.max(40,cv.clientWidth||cv.width),H=Math.max(40,cv.clientHeight||cv.height);
  if(cv.width!==Math.round(W*dpr)||cv.height!==Math.round(H*dpr)){cv.width=Math.round(W*dpr);cv.height=Math.round(H*dpr);}
  const g=cv.getContext('2d');g.setTransform(dpr,0,0,dpr,0,0);g.clearRect(0,0,W,H);
  const cam=camOf(cv),xf=(it,q)=>[q[0]*it.scale+it.at[0],q[1]*it.scale+it.at[1],q[2]*it.scale+it.at[2]];
  const lo=[Infinity,Infinity,Infinity],hi=[-Infinity,-Infinity,-Infinity];
  items.forEach(it=>it.geo.prims.forEach(p=>p.pts.forEach(q=>{const w=xf(it,q);for(let i=0;i<3;i++){lo[i]=Math.min(lo[i],w[i]);hi[i]=Math.max(hi[i],w[i]);}})));
  if(!isFinite(lo[0])){lo.fill(-1);hi.fill(1);}
  const key=opt.fitKey||'';if(cam.key!==key||!cam.center){cam.key=key;cam.center=lo.map((v,i)=>(v+hi[i])/2);cam.radius=Math.max(0.5,Math.hypot(hi[0]-lo[0],hi[1]-lo[1],hi[2]-lo[2])/2);}
  const cy=Math.cos(cam.yaw),sy=Math.sin(cam.yaw),cp=Math.cos(cam.pitch),sp=Math.sin(cam.pitch),dist=cam.radius*3.2/cam.zoom,f=Math.min(W,H)*0.44*cam.radius*3.2/cam.radius;
  const proj=w=>{let x=w[0]-cam.center[0],y=w[1]-cam.center[1],z=w[2]-cam.center[2];[x,z]=[x*cy-z*sy,x*sy+z*cy];[y,z]=[y*cp-z*sp,y*sp+z*cp];const d=dist-z;return [W/2+x*f/d,H/2-y*f/d,d];};
  const L=[0.45,0.8,0.4],Ll=Math.hypot(...L),ink=cssVar('--ink','#222'),acc=cssVar('--accent','#285f77');
  const list=[],focus=opt.focus,k=opt.k;
  // ground grid under the model
  const gy=lo[1],R=cam.radius*1.6,cx=cam.center[0],cz=cam.center[2];
  g.strokeStyle=cssVar('--dot','rgba(0,0,0,.15)');g.lineWidth=1;
  for(let i=-4;i<=4;i++){const a=proj([cx+i*R/4,gy,cz-R]),b=proj([cx+i*R/4,gy,cz+R]),c=proj([cx-R,gy,cz+i*R/4]),d=proj([cx+R,gy,cz+i*R/4]);g.beginPath();g.moveTo(a[0],a[1]);g.lineTo(b[0],b[1]);g.moveTo(c[0],c[1]);g.lineTo(d[0],d[1]);g.stroke();}
  items.forEach(it=>it.geo.prims.forEach(p=>{
    const w=p.pts.map(q=>xf(it,q)),s=w.map(proj),depth=s.reduce((a,q)=>a+q[2],0)/s.length;
    const tagged=focus&&(focus in p.tags),dim=focus&&opt.tagged&&!(tagged&&p.tags[focus]===k),hiP=focus&&tagged&&p.tags[focus]===k;
    list.push({p,s,depth,col:p.color||it.color,dim,hi:hiP,w});
  }));
  list.sort((a,b)=>b.depth-a.depth);
  for(const d of list){
    const [r,gg,b]=rgbOf(d.col),a=d.dim?0.18:1;
    if(d.p.kind==='face'&&d.s.length>2){
      const n=faceNormalW(d.w),sh=0.38+0.62*Math.abs((n[0]*L[0]+n[1]*L[1]+n[2]*L[2])/Ll);
      g.beginPath();d.s.forEach((q,i)=>i?g.lineTo(q[0],q[1]):g.moveTo(q[0],q[1]));g.closePath();
      g.fillStyle=`rgba(${r*sh|0},${gg*sh|0},${b*sh|0},${a})`;g.fill();
      g.strokeStyle=d.hi?ink:`rgba(${r*sh*0.8|0},${gg*sh*0.8|0},${b*sh*0.8|0},${a*0.6})`;g.lineWidth=d.hi?1.4:0.5;g.stroke();
    }else if(d.s.length===1){const q=d.s[0],rad=Math.max(1.5,(d.p.size||0.04)*f/q[2]);g.beginPath();g.arc(q[0],q[1],rad,0,Math.PI*2);g.fillStyle=`rgba(${r},${gg},${b},${a})`;g.fill();}
    else{g.beginPath();d.s.forEach((q,i)=>i?g.lineTo(q[0],q[1]):g.moveTo(q[0],q[1]));if(d.p.closed)g.closePath();g.strokeStyle=d.hi?ink:`rgba(${r},${gg},${b},${a})`;g.lineWidth=d.hi?2.4:1.6;g.stroke();}
  }
  if(opt.ghost){g.save();g.setLineDash([4,3]);g.strokeStyle=cssVar('--t-vec','#6b50ae');g.lineWidth=1.2;
    opt.ghost.prims.forEach(p=>{const s=p.pts.map(q=>proj(xf(items[0],q)));g.beginPath();s.forEach((q,i)=>i?g.lineTo(q[0],q[1]):g.moveTo(q[0],q[1]));if(p.closed)g.closePath();g.stroke();});g.restore();}
  cv._drawn=list;return list;
}
function faceNormalW(w){const [a,b,c]=w,u=[b[0]-a[0],b[1]-a[1],b[2]-a[2]],v=[c[0]-a[0],c[1]-a[1],c[2]-a[2]],n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]],l=Math.hypot(...n)||1;return n.map(x=>x/l);}
function pickAt(cv,x,y){const L=cv._drawn||[];for(let i=L.length-1;i>=0;i--){const s=L[i].s;if(s.length===1){if(Math.hypot(s[0][0]-x,s[0][1]-y)<5)return L[i].p;continue;}
  if(s.length>2&&L[i].p.kind==='face'){let c=false;for(let a=0,b=s.length-1;a<s.length;b=a++){if((s[a][1]>y)!==(s[b][1]>y)&&x<(s[b][0]-s[a][0])*(y-s[a][1])/(s[b][1]-s[a][1])+s[a][0])c=!c;}if(c)return L[i].p;}}return null;}
function initPreview(body){
  const cv=body.querySelector('canvas');let drag=null;
  cv.addEventListener('pointerdown',e=>{drag={x:e.clientX,y:e.clientY,moved:false};cv.setPointerCapture(e.pointerId);});
  cv.addEventListener('pointermove',e=>{if(!drag)return;const dx=e.clientX-drag.x,dy=e.clientY-drag.y;if(!drag.moved&&Math.hypot(dx,dy)<4)return;drag.moved=true;const c=camOf(cv);c.yaw+=dx*0.01;c.pitch=Math.max(-1.4,Math.min(1.4,c.pitch+dy*0.01));drag.x=e.clientX;drag.y=e.clientY;drawScene(cv,cv._items||[],cv._opt||{});});
  cv.addEventListener('pointerup',e=>{const d=drag;drag=null;if(!d||d.moved)return;
    const r=cv.getBoundingClientRect(),p=pickAt(cv,e.clientX-r.left,e.clientY-r.top);if(!p){status('Drag to orbit, scroll to zoom, click a shape to find what made it.');return;}
    const keys=Object.keys(p.tags).filter(k=>!k.startsWith('#'));
    if(!keys.length){status('This shape is not made by a loop or a function call.');return;}
    const fz=focusZone(),zid=keys.includes(fz)?fz:keys.sort((a,b)=>b.length-a.length)[0],g=zid.split('/')[0];
    probe[zid]=p.tags[zid];if(scope!==g&&program.graphs.has(g)){scope=g;returnScope=null;}
    selection=new Set([zid]);piece=null;renderAll();
    const z=program.zones.get(zid);status(z?.kind==='fn'?`That shape came from call ${p.tags[zid]+1} of ${z.count} to ${zid.split('/').pop()}. Every node inside shows its value in that call.`:`That shape came from ${zid.split('/').pop()}, iteration ${p.tags[zid]+1}. Every node in the loop now shows its value there.`);});
  cv.addEventListener('wheel',e=>{e.preventDefault();const c=camOf(cv);c.zoom=Math.max(0.3,Math.min(6,c.zoom*(e.deltaY<0?1.1:1/1.1)));drawScene(cv,cv._items||[],cv._opt||{});},{passive:false});
  cv.addEventListener('dblclick',()=>{const c=camOf(cv);c.key='';c.zoom=1;c.yaw=-0.7;c.pitch=0.45;drawScene(cv,cv._items||[],cv._opt||{});});
}
function renderPreview(cv,scene,small){
  scene=scene||[...program.cache.values()].find(v=>v.t==='scene')?.d;
  const items=scene?.items||[];
  const fz=small?null:focusZone(),zk=fz?program.zones.get(fz):null,k=fz?probe[fz]||0:0;
  const tagged=!!fz&&items.some(it=>it.geo.prims.some(p=>fz in p.tags));
  let ghost=null;if(zk&&(zk.kind==='fold'||zk.kind==='scan')){const st=zk.states.filter(s=>s.it[s.it.length-1]===k)[0];if(st&&st.v.t==='geometry')ghost=st.v.d;}
  const opt={focus:fz,k,tagged,ghost,fitKey:caseKey+'|'+scope};
  cv._items=items;cv._opt=opt;
  requestAnimationFrame(()=>drawScene(cv,items,opt));
  if(!small){const per=zk?(zk.kind==='fold'||zk.kind==='scan'?zk.states.filter(s=>s.it[s.it.length-1]>=0):zk.items).filter(r=>r.it.length===1||r.it.slice(0,-1).every((x,i)=>x===(probe[zoneOwnerChain(fz)[i]]||0))).length:0;
    cv.parentElement.dataset.label=fz?`${fz.split('/').pop()} · ${zk?.kind==='fold'||zk?.kind==='scan'?'state after step':zk?.kind==='fn'?'call':'iteration'} ${k+1} of ${per}`:`${describeScene(scene)} · drag to orbit`;}
}
