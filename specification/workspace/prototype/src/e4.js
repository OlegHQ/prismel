/* ---------- navigator: a map of the workspace, not a menu ---------- */
let olQuery='';
function goto(sc,id){returnScope=null;scope=sc;selection=id?new Set([id]):new Set();piece=null;renderAll();
  requestAnimationFrame(()=>scrollToNode(id,false));}
function flashPanel(name){const el=leaves.find(l=>bindingOfPanel(l._panel)===name);if(!el)return;el.classList.add('flash');setTimeout(()=>el.classList.remove('flash'),900);}
function initOutline(body){
  const q=body.querySelector('.ol-search'),tree=body.querySelector('.ol-tree');
  q.oninput=()=>{olQuery=q.value;fillOutline(body);};
  q.onkeydown=e=>{if(e.key==='Enter'){const first=tree.querySelector('[data-goto-scope]');if(first){goto(first.dataset.gotoScope,first.dataset.gotoNode||null);q.value=olQuery='';fillOutline(body);q.blur();}}else if(e.key==='Escape'){q.value=olQuery='';fillOutline(body);q.blur();}};
  tree.addEventListener('click',e=>{
    const pre=e.target.closest('[data-preset]');if(pre){applyLayout(pre.dataset.preset);return;}
    const fp=e.target.closest('[data-flash]');if(fp){flashPanel(fp.dataset.flash);return;}
    const ed=e.target.closest('[data-edit-panel]');if(ed){goto(editorName(),editorName()+'/'+ed.dataset.editPanel);return;}
    const h=e.target.closest('[data-help]');if(h){actions();return;}
    const m=e.target.closest('[data-macro]');if(m){macroDialog(m.dataset.macro);return;}
    const t=e.target.closest('[data-goto-scope]');if(t)goto(t.dataset.gotoScope,t.dataset.gotoNode||null);
  });
  tree.addEventListener('input',e=>{const s=e.target.closest('.pslider');if(!s)return;const v=Number(s.value);s.nextElementSibling.textContent=s.value;
    liveEdit(f=>{const g=s.dataset.graph===scope?f:null;const form=g||ast.slice(2).find(x=>x[1]===s.dataset.graph);const p=M.paramsOf(form).find(p=>p[0]===s.dataset.param);p[3]=s.dataset.t==='float'?M.mkNum(v,true):Math.round(v);});});
  tree.addEventListener('pointerdown',e=>{const s=e.target.closest('.pslider');if(s)s._pre=snapshot();});
  tree.addEventListener('change',e=>{const s=e.target.closest('.pslider');if(s&&s._pre){past.push(s._pre);future=[];s._pre=null;renderAll();status(`Input ${s.dataset.param} = ${s.value}. This is the default an OCaml caller can override.`);}});
  tree.addEventListener('dragstart',e=>{const d=e.target.closest('[data-drag]');if(!d)return;e.dataTransfer.setData('text/x-rays',d.dataset.drag);e.dataTransfer.setData('text/plain',d.dataset.drag);e.dataTransfer.effectAllowed='copy';});
}
function treeRows(S,sc,depth,out){
  S.nodes.forEach(n=>{
    const t=nodeType(n),z=n.kind==='zone';
    out.push(`<div class="ol-row leaf${selection.has(n.id)&&sc===scope?' sel':''}" style="--d:${depth}" data-goto-scope="${esc(sc)}" data-goto-node="${esc(n.id)}">${z?`<span class="zg z-${n.zkind.replace('*','')}">${esc(ZONE_GLYPH[n.zkind])}</span>`:`<i class="tsq tc-${tc(t)}"></i>`}<span>${n.synthetic?'<i>result</i>':esc(n.name)}</span><small>${esc(z?(program.zones.get(n.id)?.count??'')+(n.zkind==='let*'?'scope':'×'):describe(recordAt(n.id,zoneChain(S))))}</small></div>`);
    if(z)treeRows(n.inner,sc,depth+1,out);
  });
}
function panelTree(p,depth,out){
  if(p.kind==='split'){out.push(`<div class="ol-row pt" style="--d:${depth}"><i class="tsq ${p.axis==='horizontal'?'sp-h':'sp-v'}"></i><span>split ${p.axis==='horizontal'?'side by side':'stacked'}</span><small>${Math.round(p.ratio*100)} / ${100-Math.round(p.ratio*100)}</small></div>`);p.children.forEach(c=>panelTree(c,depth+1,out));}
  else if(p.kind==='floating'||p.kind==='tile'){out.push(`<div class="ol-row pt" style="--d:${depth}"><i class="tsq sp-f"></i><span>${p.kind}${p.kind==='tile'?' · '+p.children.length:''}</span></div>`);p.children.forEach(c=>panelTree(c,depth+1,out));}
  else{const n=bindingOfPanel(p)||'';out.push(`<div class="ol-row pt leafp" style="--d:${depth}" ${n?`data-flash="${esc(n)}"`:''} title="${n?'Click to locate this panel':'Made by a loop in the editor graph'}"><i class="tsq pk-${p.kind}"></i><span>${esc(KINDS.find(k=>k[0]===p.kind)?.[1]||p.kind)}</span><small>${esc(n||'loop')}</small>${n?`<button class="mini" data-edit-panel="${esc(n)}" title="Show in the editor graph">node</button>`:''}</div>`);}
}
function fillOutline(body){
  const tree=body.querySelector('.ol-tree'),q=olQuery.trim().toLowerCase();
  if(q){
    const hits=[];
    const scan=(sc,f)=>{const pre=(program.defs.has(sc)?'def:':'')+sc;(function w(x,path){if(!isL(x))return;if(isScope(x))for(let i=0;i<x[1].length;i+=2){const nm=x[1][i],e=x[1][i+1],id=path+'/'+nm;if(nm.includes(q)||M.print(e).toLowerCase().includes(q))hits.push({sc,id,t:nm,s:sc+(path.split('/').length>1?' › '+path.split('/').slice(1).join(' › '):'')+' · '+M.print(e).replace(/\s+/g,' ').slice(0,60)});
        if(isZone(e))w(M.zoneBody(e),id);else if(isScope(e))w(e,id);}
      else if(isZone(x))w(M.zoneBody(x),path);})(M.body(f),pre);if(sc.includes(q))hits.unshift({sc,id:'',t:(program.defs.has(sc)?'ƒ ':'')+sc,s:'graph · '+f[3]});};
    program.graphs.forEach((f,sc)=>scan(sc,f));program.defs.forEach((f,sc)=>scan(sc,f));
    tree.innerHTML=`<div class="ol-sec">${hits.length} MATCH${hits.length===1?'':'ES'} · Enter opens the first</div>`+hits.slice(0,50).map(h=>`<div class="ol-row hit" data-goto-scope="${esc(h.sc)}" data-goto-node="${esc(h.id)}"><span>${esc(h.t)}</span><small>${esc(h.s)}</small></div>`).join('');
    return;}
  const c=Cases.CASES.find(c=>c.key===caseKey);
  let h=c?`<div class="ol-case"><span class="eyebrow">Case study</span><b>${esc(c.title)}</b><small>${esc(c.tag)}</small></div>`:'';
  const f=curForm(),ps=M.paramsOf(f);
  if(ps.length){h+=`<div class="ol-sec">INPUTS · ${esc(scope)}</div><p class="ol-note">Defaults. An OCaml host and <code>(ref ${esc(scope)} …)</code> can override them.</p>`;
    ps.forEach(p=>{if(!M.isNum(p[3]))return;const v=M.numOf(p[3]),isF=p[2]==='float',max=Math.max(isF?2:24,v*2.5),mn=Math.min(0,v);h+=`<label class="ol-param"><span>${esc(p[0])}</span><input class="pslider" type="range" data-graph="${esc(scope)}" data-param="${esc(p[0])}" data-t="${p[2]}" min="${mn}" max="${+max.toFixed(3)}" step="${isF?0.001:1}" value="${v}" aria-label="${esc(p[0])}"><output>${esc(M.atom(p[3]))}</output></label>`;});}
  h+='<div class="ol-sec">COMPOSITION</div>';
  program.graphs.forEach((g,sc)=>{
    const active=sc===scope,drag=!isDef()&&sc!==scope?` draggable="true" data-drag="ref:${esc(sc)}" title="Drag onto the canvas to insert (ref ${esc(sc)})"`:'';
    const nz=[...program.zones.keys()].filter(k=>k.startsWith(sc+'/')).length;
    h+=`<div class="ol-row ctxrow${active?' active':''}"${drag} data-goto-scope="${esc(sc)}"><i class="ctx ctx-${g[3]}"></i><span>${esc(sc)}</span><small>${nz?nz+' loop'+(nz>1?'s':''):g[3]}</small></div>`;
    if(active&&view){const out=[];treeRows(view.root,sc,1,out);h+=out.join('');}
  });
  if(program.defs.size||program.macros.size){h+='<div class="ol-sec">REUSABLE</div>';
    program.defs.forEach((d,sc)=>{const active=sc===scope;h+=`<div class="ol-row ctxrow${active?' active':''}" draggable="true" data-drag="def:${esc(sc)}" data-goto-scope="${esc(sc)}" title="Drag onto the canvas to place a call"><span class="fnmark">ƒ</span><span>${esc(sc)}</span><small>${countCalls(sc)} call${countCalls(sc)===1?'':'s'}</small></div>`;if(active&&view){const out=[];treeRows(view.root,sc,1,out);h+=out.join('');}});
    program.macros.forEach((m,k)=>{h+=`<div class="ol-row ctxrow" draggable="true" data-drag="macro:${esc(k)}" data-macro="${esc(k)}"><span class="fnmark">λ</span><span>${esc(k)}</span><small>macro</small></div>`;});}
  const refs=x=>{const o=new Set();(function w(y){if(isL(y)){if(y[0]==='ref')o.add(y[1]);y.forEach(w);}})(x);return o;};
  if(!isDef()){const reads=[...refs(M.body(f))],readBy=[...program.graphs].filter(([k,g])=>k!==scope&&refs(M.body(g)).has(scope)).map(([k])=>k);
    h+=`<div class="ol-sec">DATA FLOW · ${esc(scope)}</div><div class="flow"><span class="fl">reads</span>${reads.map(x=>`<button class="chip2" data-goto-scope="${esc(x)}">${esc(x)}</button>`).join('')||'<em>nothing</em>'}<span class="fl">read by</span>${readBy.map(x=>`<button class="chip2" data-goto-scope="${esc(x)}">${esc(x)}</button>`).join('')||'<em>nothing</em>'}</div>`;}
  const root=layoutRoot();
  h+='<div class="ol-sec">SHELL · the applied editor graph</div>';
  const out=[];if(root)panelTree(root,0,out);h+=out.join('');
  h+=`<div class="presets"><button data-preset="three">Default</button><button data-preset="code">Graph + code</button><button data-preset="focus">Focus</button><button data-preset="floating">Floating</button></div><button class="olhelp" data-help="1">Actions &amp; keys</button>`;
  tree.innerHTML=h;
}

/* ---------- list ---------- */
function fillList(body){
  const lb=body.querySelector('.lbody');if(!view){lb.innerHTML='';return;}
  const rows=[];
  (function w(S,d){S.nodes.forEach(n=>{rows.push(`<button class="list-row${selection.has(n.id)?' selected':''}" data-id="${esc(n.id)}" style="--d:${d}"><strong>${n.kind==='zone'?`<span class="zg z-${n.zkind.replace('*','')}">${esc(ZONE_GLYPH[n.zkind])}</span> `:''}${n.synthetic?'<i>result</i>':esc(n.name)}</strong><code>${esc(n.kind==='zone'?(n.zkind==='let*'?'let* …':`(${n.zkind} [${n.inner.rail.filter(r=>r.role!=='capture').map(r=>r.name+' '+M.print(r.expr)).join(' ')}] …)`):M.print(n.expr).replace(/\s+/g,' '))}</code><small>${esc(tname(nodeType(n)))}</small></button>`);if(n.inner)w(n.inner,d+1);});})(view.root,0);
  lb.innerHTML=`<p class="hint">The same bindings in source order. Loop bodies are indented under their zone.</p>`+rows.join('');
  lb.querySelectorAll('.list-row').forEach(b=>{b.onclick=e=>selectNode(b.dataset.id,e.shiftKey);b.ondblclick=()=>enterFunction(b.dataset.id);});
}

/* ---------- inspector ---------- */
function crumbs(n){const o=[];for(let s=n.scope;s;s=s.parent){if(s.owner)o.unshift(`<button class="crumb" data-sel="${esc(s.owner.id)}">${esc(s.owner.synthetic?'result':s.owner.name)} <em>${esc(ZONE_GLYPH[s.owner.zkind])}${program.zones.get(s.owner.id)?' '+program.zones.get(s.owner.id).count+'×':''}</em></button>`);}o.unshift(`<span>${esc(scope)}</span>`);return o.join('<span class="sep">›</span>');}
function fillInspector(panel){
  const q=s=>panel.querySelector(s),qa=s=>[...panel.querySelectorAll(s)];
  const ids=[...selection],n=ids.length===1?view?.all.get(ids[0]):null;
  if(!n){
    const z=[...program.zones].filter(([k])=>k.startsWith(rootId()+'/'));
    panel.innerHTML=`<h3>${esc(scope)}</h3><div class="type-label">${isDef()?'shared definition · '+countCalls(scope)+' calls':esc(curForm()[3])+' graph'}${z.length?' · '+z.length+' loop'+(z.length>1?'s':''):''}</div>${ids.length>1?`<p class="hint">${ids.length} nodes selected. <b>Repeat</b> (R) wraps them in a for zone. <b>Iterate</b> (⇧R) feeds the result back in with fold. <b>Function</b> (F) extracts a reusable call.</p>`:''}<p class="hint">Drag numbers to scrub. Drag from an output dot to an input. Drag across a loop’s strip to probe one iteration. Click a shape in the viewport to find the iteration that made it.</p><div class="fold-help"><b>ƒ</b> A nested call, loop or scope is a chip. Its ƒ unfolds it into a node or zone; the ƒ on a node’s title folds it back.</div>${scope===editorName()?'<div class="inspector-actions"><button class="layout-options primary">Try shell layouts</button></div>':''}`;
    q('.layout-options')&&(q('.layout-options').onclick=layoutDialog);return;
  }
  const t=nodeType(n),chain=zoneChain(n.scope),v=recordAt(n.id,chain);
  let h=`<div class="crumbs">${crumbs(n)}</div>`;
  if(n.kind==='param'){
    h+=`<h3>${esc(n.name)}</h3><div class="type-label">input · ${esc(n.type)}</div><p class="hint">A typed graph input with a default. <code>(ref ${esc(scope)} :${esc(n.name)} …)</code> and the OCaml caller can override it. Drag the default on the node to change it.</p>`;
    panel.innerHTML=h;qa('[data-sel]').forEach(b=>b.onclick=()=>selectNode(b.dataset.sel,false));return;
  }
  const nameField=n.synthetic?`<h3><i>result</i> of ${esc(n.scope.owner?n.scope.owner.name:scope)}</h3>`:`<form class="rename"><input class="nm" value="${esc(n.name)}" aria-label="Binding name" spellcheck="false"><button>Rename</button></form>`;
  h+=nameField;
  if(n.kind==='zone'){
    const z=program.zones.get(n.id),iters=n.inner.rail.filter(r=>r.role==='iter'),acc=n.inner.rail.find(r=>r.role==='acc'),caps=n.inner.rail.filter(r=>r.role==='capture');
    const expl={for:`Runs its body once for every ${iters.map(r=>r.name).join(' × ')} and collects the results into a list${iters.length>1?' (a product: every combination, the last name varying fastest)':''}.`,fold:`Starts ${acc?.name} at its initial value. Each step's result becomes the next ${acc?.name}. The zone returns the last one.`,scan:`Like fold, but returns every step's ${acc?.name} as a list.`,sum:'Adds up what its body returns for every iteration.','let*':'A scope. Its bindings are private: only its result leaves, so it reads as one step from outside.',fn:`A function value. It runs once per call; its strip shows every call it received, and the probe picks one. Pass it by wiring its λ output into map, filter, reduce, sort-by or a defn input of type fn, or call it by name.`}[n.zkind];
    h+=`<div class="type-label">${esc(ZONE_LABEL[n.zkind])} · ${esc(tname(t))}</div><p class="hint">${esc(expl)}</p>`;
    if(z)h+=`<div class="kv"><span>${n.zkind==='fn'?'calls':'iterations'}</span><b>${z.count}${z.runs>1?' over '+z.runs+' runs':''}</b>${iters.map(r=>`<span>${esc(r.name)} ∈</span><b>${esc(M.print(r.expr))}</b>`).join('')}${acc?`<span>${esc(acc.name)} starts</span><b>${esc(M.print(acc.expr))}</b>`:''}${caps.length?`<span>same every time</span><b>${caps.map(c=>esc(c.name)).join(', ')}</b>`:''}<span>result</span><b>${esc(describe(v))}</b></div>`;
    if(z&&n.zkind!=='let*'){const items=(n.zkind==='fold'?z.states.filter(s=>s.it[s.it.length-1]>=0):z.items).filter(r=>r.it.length===chain.length+1&&chain.every((c,i)=>r.it[i]===(probe[c]||0)));
      h+=`<div class="itab" role="list">${items.slice(0,64).map((r,i)=>`<button class="irow${(probe[n.id]||0)===i?' on':''}" data-probe="${i}"><span>${i+1}</span><b>${esc(describe(r.v))}</b></button>`).join('')}${items.length>64?`<p class="hint">…and ${items.length-64} more.</p>`:''}</div>`;}
    h+=`<div class="inspector-actions"><button class="tog">${meta.collapsed[n.id]?'Expand zone':'Collapse to a card'}</button>${foldInfo(n)?`<button class="do-fold">Fold into ${esc(foldInfo(n).consumer.name)}</button>`:''}</div>`;
  }else{
    const e=n.expr,fn=isL(e)&&program.defs.get(e[0]),mac=isL(e)&&program.macros.get(e[0]);
    const badge=M.isNum(e)?'LITERAL':typeof e==='string'?'CONNECTION':e?.vector?'VECTOR':fn?'FUNCTION CALL':mac?'MACRO':isL(e)&&e[0]==='if'?'BRANCH':'OPERATOR';
    h+=`<div class="type-label">${esc(tname(t))}</div><div class="badge">${badge}</div>`;
    h+=`<form class="field expression-form"><label for="ins-expr">Expression</label><div class="field-line"><input id="ins-expr" class="expression" value="${esc(M.print(e).replace(/\s+/g,' '))}" spellcheck="false"><button type="submit">Apply</button></div></form>`;
    h+=`<div class="kv"><span>value${chain.length?' at probe':''}</span><b>${esc(describe(v))}</b></div>`;
    if(usesTime())h+=`<div class="kv"><span>cook</span><b>${isLive(n)?'◷ live: recooks every frame while playing':'cached: t does not reach it'}</b></div>`;
    if(chain.length){
      const ser=seriesOf(n.id,chain)||[],zid=chain[chain.length-1],zn=view.all.get(zid);
      h+=`<p class="hint">Inside <b>${esc(zn?.name||'')}</b>: this node runs ${program.records.get(n.id)?.length||0} times. ${variesIn(n)?'It changes with the loop variable.':'It is the same every time, so it can move out of the loop.'}</p>`;
      if(ser.length)h+=`<div class="itab">${ser.slice(0,64).map((x,i)=>`<button class="irow${(probe[zid]||0)===i?' on':''}" data-probe-z="${esc(zid)}" data-probe="${i}"><span>${i+1}</span><b>${esc(describe(x))}</b></button>`).join('')}</div>`;
      h+=`<div class="inspector-actions">${!variesIn(n)?'<button class="do-hoist primary">Move out of the loop</button>':''}${piece&&piece.id===n.id&&(zn?.inner.rail.some(r=>r.role==='iter'))?`<button class="do-except" title="Writes (if (= i k) new old)">Only iteration ${(probe[zid]||0)} differs</button>`:''}</div>`;
    }
    if(fn){h+=`<p class="hint">Arguments belong to this call. The body is shared by <strong>${countCalls(e[0])} calls</strong>.</p><div class="inspector-actions"><button class="enter-fn primary">Edit shared definition</button><button class="unique">Make unique</button></div>`;}
    if(mac)h+=`<div class="inspector-actions"><button class="inspect-macro">Inspect macro expansion</button></div>`;
    if(n.macro){let ex='';try{ex=M.print(M.expand(program,n.expr));}catch(e){ex=e.message;}h+=`<p class="hint">A call to the macro <b>${esc(n.macro)}</b>. It is rewritten before checking; the rows are its holes. Press ⤵ on the node to step through the expansion.</p><pre class="lisp mini">${hl(ex)}</pre><div class="inspector-actions"><button class="do-inline">Replace call with expansion</button><button class="do-msrc">Template</button></div>`;}
    const fi=foldInfo(n);if(fi)h+=`<div class="inspector-actions"><button class="do-fold">Fold into ${esc(fi.consumer.name==='@result'?'the result':fi.consumer.name)}</button></div>`;
  }
  if(!n.synthetic)h+=`<div class="field"><label for="ins-note">Note · a ; comment above ${esc(n.name)} in the Lisp</label><textarea id="ins-note" class="notearea" rows="2" placeholder="Why this node exists…">${esc(n.note||'')}</textarea></div>`;
  if(n.kind==='node'&&isL(n.expr)&&!n.expr.vector&&!M.isMap(n.expr))h+=`<div class="inspector-actions"><button class="do-bypass">${n.bypass?'Run again (remove ^:bypass)':'Bypass (^:bypass)'}</button></div>`;
  if(n.kind==='zone'&&n.zkind==='fn'){const z=program.zones.get(n.id);if(z?.args)h+=`<p class="hint">Every call this function received, with its arguments and result. Click one to probe it.</p><div class="itab calls">${z.args.slice(0,48).map((a,i)=>`<button class="irow${(probe[n.id]||0)===i?' on':''}" data-probe="${i}"><span>${i+1}</span><b>(${esc(a.v.map(x=>describe(x)).join(' '))}) → ${esc(describe(z.items[i]?.v))}</b></button>`).join('')}</div>`;}
  const users=n.scope.nodes.filter(m=>m!==n&&M.freeSymbols(m.expr).has(n.name));
  h+=`<div class="usedby"><span class="fl">used by</span>${users.map(m=>`<button class="chip2" data-sel="${esc(m.id)}">${esc(m.synthetic?'result':m.name)}</button>`).join('')||(n.scope.result?.link===n.name?'<em>the '+(n.scope.owner?n.scope.owner.zkind+' result':'graph result')+'</em>':'<em>nothing</em>')}</div>`;
  panel.innerHTML=h;
  q('.rename')&&(q('.rename').onsubmit=e=>{e.preventDefault();renameNode(n.id,q('.nm').value.trim());});
  q('.expression-form')&&(q('.expression-form').onsubmit=e=>{e.preventDefault();let x;try{x=M.read(q('.expression').value);}catch(err){status(err.message,true);return;}mutate(f=>{setNodeExpr(f,n.loc,x);reorderAt(f,n.loc.path);},`Applied ${n.name}.`);});
  qa('[data-sel]').forEach(b=>b.onclick=()=>selectNode(b.dataset.sel,false));
  qa('[data-probe]').forEach(b=>b.onclick=()=>{probe[b.dataset.probeZ||n.id]=Number(b.dataset.probe);renderAll(true);});
  q('.tog')&&(q('.tog').onclick=()=>{meta.collapsed[n.id]=!meta.collapsed[n.id];renderAll();});
  q('.do-fold')&&(q('.do-fold').onclick=()=>fold(n.id));
  q('.do-bypass')&&(q('.do-bypass').onclick=()=>toggleBypass(n.id));
  q('.do-inline')&&(q('.do-inline').onclick=()=>inlineMacro(n.id));
  q('.do-msrc')&&(q('.do-msrc').onclick=()=>macroDialog(n.macro));
  q('.notearea')&&(q('.notearea').onchange=e=>setNodeNote(n.id,e.target.value));
  q('.do-hoist')&&(q('.do-hoist').onclick=()=>hoist(n.id));
  q('.do-except')&&(q('.do-except').onclick=()=>exceptIteration(n.id,piece.key));
  q('.enter-fn')&&(q('.enter-fn').onclick=()=>enterFunction(n.id));
  q('.unique')&&(q('.unique').onclick=()=>makeUnique(n));
  q('.inspect-macro')&&(q('.inspect-macro').onclick=()=>macroDialog(n.expr[0],n.expr));
}

/* ---------- Lisp panel: the selection is its own subgraph ---------- */
function hl(text){
  return esc(text).replace(/(?<!&[a-z0-9#]{1,6});[^\n]*/g,m=>`<span class="cm">${m}</span>`)
    .replace(/\((?:\u0001)?([^\s()[\]<&\u0001\u0002]+)/g,(m,h)=>m.replace(h,`<span class="kw${['for','fold','scan','sum','let*','if','fn','cond','case','map','filter','reduce','sort-by'].includes(h)?' zk':''}${program?.macros?.has(h)||h==='defmacro'?' mk':''}">${h}</span>`))
    .replace(/(\^:[a-z]+)/g,'<span class="meta">$1</span>').replace(/(`|~@|~)/g,'<span class="qq">$1</span>')
    .replace(/(^|[\s[(])(:[a-z_][a-z0-9_-]*)/g,'$1<span class="kwd">$2</span>')
    .replace(/&quot;(.*?)&quot;/g,'<span class="str">&quot;$1&quot;</span>')
    .replace(/\u0001/g,'<mark>').replace(/\u0002/g,'</mark>');
}
function markFor(n){
  if(!n)return null;
  if(piece&&piece.id===n.id&&n.kind!=='zone'){const a=getArg(n.expr,piece.key);if(isL(a))return {obj:a};if(!piece.key.whole&&isL(n.expr)){const {pos,kw}=M.callArgs(n.expr);const idx='pos' in piece.key?pos[piece.key.pos]?.idx:kw[piece.key.kw]?.idx;if(idx)return {parent:n.expr,idx};}}
  if(isL(n.expr))return {obj:n.expr};
  const s=scopeRef(curForm(),n.loc.path).get();if(isScope(s)&&n.name!=='@result'){const j=s[1].indexOf(n.name);return {parent:s[1],idx:j+1};}
  return null;
}
function selectionCode(){
  const f=curForm(),ids=[...selection].filter(id=>view?.all.has(id)),n=ids.length?view.all.get(ids[ids.length-1]):null;
  if(!n)return `<div class="cnote">;; nothing selected · the whole ${isDef()?'function':'graph'}</div><pre class="lisp">${hl(M.printMarked(f))}</pre>`;
  if(n.kind==='param')return `<div class="cnote">;; input ${esc(n.name)} of ${esc(scope)}</div><pre class="lisp">${hl(M.printMarked(f,{obj:M.paramsOf(f).find(p=>p[0]===n.name)}))}</pre>`;
  const top=n.loc.path[0]||n.loc.name,body=M.body(f),root=isScope(body)?M.bindings(body):[];
  const mark=markFor(n);
  if(!isScope(body)||top==='@result')return `<div class="cnote">;; ${esc(n.name)} in context</div><pre class="lisp">${hl(M.printMarked(f,mark))}</pre>`;
  const byName=new Map(root.map(b=>[b.name,b])),need=new Set();
  const walk=nm=>{if(need.has(nm)||!byName.has(nm))return;need.add(nm);M.freeSymbols(byName.get(nm).expr).forEach(walk);};walk(top);
  const sub=root.filter(b=>need.has(b.name));
  const vecb=M.vec(sub.flatMap(b=>[b.name,b.expr])),form=['let*',vecb,top];
  const ps=M.paramsOf(f).filter(p=>[...sub].some(b=>M.freeSymbols(b.expr).has(p[0])));
  const inside=n.loc.path.length?` · inside ${n.loc.path.join(' › ')}`:'';
  let h=`<div class="cnote">;; ${esc(n.synthetic?'result':n.name)}${esc(inside)} · ${sub.length>1?`with ${sub.length-1} upstream binding${sub.length===2?'':'s'}`:'no upstream bindings'}${ps.length?' and inputs '+esc(ps.map(p=>p[0]).join(', ')):''}</div><pre class="lisp">${hl(M.printMarked(form,mark))}</pre>`;
  if(isL(n.expr)&&program.defs.has(n.expr[0])){const d=program.defs.get(n.expr[0]);h+=`<div class="cnote">;; shared definition of ${esc(d[1])} · ${countCalls(d[1])} call${countCalls(d[1])===1?'':'s'}</div><pre class="lisp defpeek">${hl(M.print(d))}</pre><button class="open-def" data-id="${esc(n.id)}">Edit shared definition</button>`;}
  if(!n.synthetic||isL(n.expr))h+=`<details class="bedit"${editing&&editing.line===n.id?' open':''}><summary>Edit ${esc(n.synthetic?'this result':n.name)} as text</summary><textarea class="bsrc" spellcheck="false" aria-label="Binding source">${esc(M.print(n.expr))}</textarea><div class="source-toolbar"><span>Checks the whole workspace</span><button class="bapply primary" data-id="${esc(n.id)}">Apply<kbd>Ctrl ↵</kbd></button></div></details>`;
  return h;
}
function initLisp(body){
  const tabs=body.querySelector('.ctabs'),csel=body.querySelector('.csel'),ta=body.querySelector('.doc-src');
  tabs.onclick=e=>{const b=e.target.closest('[data-tab]');if(b){codeTab=b.dataset.tab;renderAll();}};
  const applyB=id=>{const n=view.all.get(id),src=csel.querySelector('.bsrc').value;let x;try{x=M.read(src);}catch(err){status(err.message,true);return;}if(mutate(f=>{setNodeExpr(f,n.loc,x);reorderAt(f,n.loc.path);},`Applied ${n.name} from text.`))editing=null;};
  csel.addEventListener('click',e=>{const od=e.target.closest('.open-def');if(od){enterFunction(od.dataset.id);return;}const ba=e.target.closest('.bapply');if(ba)applyB(ba.dataset.id);});
  csel.addEventListener('keydown',e=>{if(e.target.classList.contains('bsrc')&&(e.metaKey||e.ctrlKey)&&e.key==='Enter'){e.preventDefault();const b=csel.querySelector('.bapply');if(b)applyB(b.dataset.id);}});
  csel.addEventListener('toggle',e=>{if(e.target.classList?.contains('bedit')){const id=[...selection].pop();editing=e.target.open?{line:id}:null;}},true);
  ta.oninput=e=>{draft=e.target.value;dirty=draft!==M.print(ast);$$('.doc-src').forEach(t=>{if(t!==ta)t.value=draft;});status(dirty?'Unapplied draft. Every panel shows the last valid document.':'Source matches the applied document.');updateDirtyUI();};
  body.querySelector('.apply').onclick=applySource;
  body.querySelector('.discard').onclick=()=>{dirty=false;draft=M.print(ast);status('Discarded draft. The applied document is unchanged.');renderAll();};
}
function updateDirtyUI(){$$('.ctabs [data-tab="doc"]').forEach(b=>b.classList.toggle('dirty',dirty));}
function fillLisp(el,body){
  const tabs=body.querySelector('.ctabs'),csel=body.querySelector('.csel'),cdoc=body.querySelector('.cdoc'),ta=body.querySelector('.doc-src');
  const T=[['sel','Selection'],['graph','Graph'],['doc','Document']];
  tabs.innerHTML=T.map(([k,l])=>`<button role="tab" data-tab="${k}" aria-selected="${codeTab===k}" class="${k==='doc'&&dirty?'dirty':''}">${l}</button>`).join('');
  el.querySelector('.pctl').innerHTML=`<span class="ptag">${esc(scope)}</span>`;
  csel.hidden=codeTab==='doc';cdoc.hidden=codeTab!=='doc';
  if(codeTab==='doc'){if(!dirty&&document.activeElement!==ta)ta.value=draft;return;}
  if(csel.contains(document.activeElement)&&document.activeElement.classList.contains('bsrc'))return;
  if(codeTab==='sel')csel.innerHTML=selectionCode();
  else{const ids=[...selection].filter(id=>view?.all.has(id));csel.innerHTML=`<div class="cnote">;; the whole ${isDef()?'function':'graph'}${ids.length?' · selection marked':''}</div><pre class="lisp">${hl(M.printMarked(curForm(),markFor(view?.all.get(ids[ids.length-1]))))}</pre>`;}
  const m=csel.querySelector('mark');if(m){const top=m.offsetTop-csel.offsetTop;if(top<csel.scrollTop||top>csel.scrollTop+csel.clientHeight-40)csel.scrollTop=Math.max(0,top-30);}
}
