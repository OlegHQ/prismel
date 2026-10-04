/* ---------- functions, extraction, macros ---------- */
function dialog(title,html){$('#dialog-title').textContent=title;$('#dialog-body').innerHTML=html;if(!$('#dialog').open)$('#dialog').showModal();}
function enterFunction(id){const n=view.all.get(id);if(!n||!isL(n.expr)||!program.defs.has(n.expr[0]))return;returnScope={scope,id};scope=n.expr[0];selection=new Set();piece=null;renderAll();status(`Editing shared definition ${scope}: ${countCalls(scope)} call${countCalls(scope)===1?'':'s'} change with it. Values shown are from one call.`);}
function returnToCall(){if(!returnScope)return;scope=returnScope.scope;selection=new Set([returnScope.id]);returnScope=null;piece=null;renderAll();}
function makeUnique(n){
  const f0=program.defs.get(n.expr[0]);let name=f0[1]+'_copy',i=2;while(program.defs.has(name)||program.graphs.has(name))name=f0[1]+'_copy'+i++;
  const next=M.clone(ast),copy=M.clone(next.slice(2).find(x=>x[1]===f0[1]));copy[1]=name;next.splice(2,0,copy);
  const f=next.slice(2).find(x=>x[1]===scope),e=M.clone(getNodeExpr(f,n.loc));e[0]=name;setNodeExpr(f,n.loc,e);
  commit(next,`Created ${name}. Only this call uses it; the other calls still share ${f0[1]}.`);
}
function extractDialog(){
  if(isDef()||!selection.size)return;
  const ns=[...selection].map(id=>view.all.get(id)).filter(n=>n&&n.kind!=='param'&&!n.synthetic);const S=ns[0]?.scope;
  if(!ns.length||ns.some(n=>n.scope!==S)||S!==view.root){status('Make function works on nodes at the top of a graph in this study. Select nodes outside loops.',true);return;}
  const sel=new Set(ns.map(n=>n.name)),others=S.nodes.filter(m=>!sel.has(m.name));
  const outs=ns.filter(n=>others.some(m=>M.freeSymbols(m.expr).has(n.name))||S.result?.link===n.name);
  if(outs.length!==1){status('A function returns one value here. Select a chain with exactly one result used outside it.',true);return;}
  const free=[...new Set(ns.flatMap(n=>[...M.freeSymbols(n.expr)]))].filter(s=>!sel.has(s));
  const refsG=ns.some(n=>JSON.stringify(n.expr).includes('"ref"'));
  if(refsG){status('Reusable functions cannot read project graphs. Pass that data in as an input first.',true);return;}
  const ctx=curForm()[3];
  dialog('Make a reusable function',`<p>Replace ${ns.length} bindings with one call. Its boundary becomes a typed interface.</p><pre>inputs: ${esc(free.map(s=>`${s} : ${tname(typeOfName(S,s))}`).join(', ')||'none')}\nresult: ${esc(outs[0].name)} → ${esc(tname(nodeType(outs[0])))}</pre><label for="function-name">Function name</label><input id="function-name" value="my_shape"><p class="hint">The definition is shared. Each call keeps its own arguments. Undo restores the original nodes.</p><button id="confirm-extract" class="primary">Create function</button>`);
  $('#confirm-extract').onclick=()=>{const name=$('#function-name').value.trim();
    if(!/^[a-z][a-z0-9_]*$/.test(name)||program.defs.has(name)||program.graphs.has(name)||M.OPS[name]){status('Choose a unique lowercase function name.',true);return;}
    const next=M.clone(ast),f=next.slice(2).find(x=>x[1]===scope),s=M.body(f);
    const pairs=[];for(let i=0;i<s[1].length;i+=2)pairs.push([s[1][i],s[1][i+1]]);
    const inner=pairs.filter(p=>sel.has(p[0])),params=M.vec(free.map(x=>[x,':',typeAst(typeOfName(S,x))]));
    next.splice(2,0,['defn',name,':context',ctx,params,inner.length===1?inner[0][1]:['let*',M.vec(inner.flat()),outs[0].name]]);
    const last=Math.max(...inner.map(p=>pairs.indexOf(p)));const keep=[];pairs.forEach((p,i)=>{if(!sel.has(p[0]))keep.push(p);if(i===last)keep.push([outs[0].name,[name,...free.flatMap(x=>[':'+x,x])]]);});s[1]=M.vec(keep.flat());
    if(commit(next,`Created ${name} with ${free.length} typed input${free.length===1?'':'s'}.`)){selection=new Set([rootId()+'/'+outs[0].name]);$('#dialog').close();renderAll();}};
}
function macroDialog(name,call){
  const m=program.macros.get(name);if(!m)return;
  let ex='';if(call){try{ex=M.print(M.expand(program,call));}catch(e){ex=e.message;}}
  const uses=[];(function w(x){if(isL(x)){if(x[0]===name&&!x.vector)uses.push(x);[...x].forEach(w);}})(ast.slice(2).filter(f=>f[0]!=='defmacro'));
  dialog('Macro · '+name,`<p>A macro is a template that is filled in before checking. Holes are written <code>~name</code>; names ending in <code>#</code> are fresh at every use, so a template can never capture a name from the call site.</p><pre class="lisp">${hl(M.print(m))}</pre>${call?`<p>This call, expanded</p><pre class="lisp">${hl(ex)}</pre>`:''}<p class="hint">${uses.length} use${uses.length===1?'':'s'} in this workspace. Edit the template in the Document tab; every use changes.</p><button id="macro-source">Edit in Document</button>`);
  $('#macro-source').onclick=()=>{$('#dialog').close();codeTab='doc';renderAll();const ta=$('.doc-src');if(ta){ta.focus();const at=ta.value.indexOf('(defmacro '+name);if(at>=0)ta.setSelectionRange(at,at+10+name.length);}};
}

/* ---------- shell layouts ---------- */
const layouts={
  three:'(let* [outline (ui/outline) network (ui/graph) preview (ui/viewport (ref scene)) inspector (ui/inspector) code (ui/lisp) lower (ui/split-at "vertical" 0.46 inspector code) side (ui/split-at "vertical" 0.4 preview lower) main (ui/split-at "horizontal" 0.62 network side) panels (ui/split-at "horizontal" 0.13 outline main) shell (ui/workspace panels)] shell)',
  code:'(let* [outline (ui/outline) network (ui/graph) preview (ui/viewport (ref scene)) code (ui/lisp) right (ui/split-at "vertical" 0.34 preview code) main (ui/split-at "horizontal" 0.55 network right) panels (ui/split-at "horizontal" 0.13 outline main) shell (ui/workspace panels)] shell)',
  focus:'(let* [network (ui/graph) shell (ui/workspace network)] shell)',
  floating:'(let* [outline (ui/outline) network (ui/graph) preview (ui/viewport (ref scene)) inspector (ui/inspector) tools (ui/floating inspector) canvas (ui/split-at "horizontal" 0.62 network preview) stage (ui/split "horizontal" canvas tools) panels (ui/split-at "horizontal" 0.13 outline stage) shell (ui/workspace panels)] shell)'
};
function applyLayout(key){const n=editorName();if(!n){status('This document has no editor graph.',true);return false;}
  const hasScene=program.graphs.has('scene');
  return mutate(f=>{f[f.length-1]=M.read(hasScene?layouts[key]:layouts[key].replace('(ui/viewport (ref scene))','(ui/lisp)'));},`Applied the ${({three:'default',code:'graph + code',focus:'focus',floating:'floating tools'})[key]} shell. The editor graph changed, and so did the Lisp.`,meta,n);}
function shellHTML(p){if(p.kind==='split'||p.kind==='tile')return `<div class="shell-panel split ${p.axis==='vertical'?'vertical':''}">${p.children.map(shellHTML).join('')}</div>`;if(p.kind==='floating')return `<div class="shell-panel floating">${p.children.map(shellHTML).join('')}</div>`;return `<div class="shell-panel">${esc((KINDS.find(k=>k[0]===p.kind)?.[1]||p.kind).toUpperCase())}</div>`;}
function layoutDialog(){
  const root=layoutRoot();
  dialog('Compose the shell',`<p>The shell you are using is the applied <code>editor</code> graph. A layout rewrites that graph. Undo and Restore layout live outside it, so a broken shell is always recoverable.</p><div class="shell-preview">${root?shellHTML(root):'No editor composition'}</div><div class="inspector-actions"><button data-layout="three">Default</button><button data-layout="code">Graph + code</button><button data-layout="focus">Focus graph</button><button data-layout="floating">Floating tools</button></div><p class="hint">You can also split, close and retype panels from their headers, drag dividers, or edit the editor graph. Each of those is a Lisp edit. The Variations case study loops inside the editor graph.</p>`);
  $$('[data-layout]').forEach(b=>b.onclick=()=>{if(applyLayout(b.dataset.layout))$('#dialog').close();});
}
function actions(){
  dialog('Actions & keyboard',`<label for="action-search">Find an action</label><input id="action-search" placeholder="repeat, fold, hoist, layout…"><div id="actions"></div><p class="hint">Shortcuts work outside text fields. Drag a number to scrub it, with Shift for fine steps. Drag an output dot onto an input to connect. Drag across a loop’s strip to probe an iteration.</p>`);
  const entries=[['Add a node · A',()=>openPalette(null,null,view.root)],['Repeat selection in a for zone · R',()=>wrapInLoop('for')],['Iterate selection with fold · Shift R',()=>wrapInLoop('fold')],['Make function · F',extractDialog],['Make a local λ function from the selection · L',makeLocalFn],['Make a macro from the selection · M',makeMacroDialog],['Bypass or run the selected node · B',()=>{const id=[...selection][0];if(id)toggleBypass(id);}],['Write a note on the selected node · N',()=>document.querySelector('.ibody .notearea')?.focus()],['Delete selection · Delete',deleteSelected],['Collapse or expand the selected zone · C',()=>{const id=[...selection][0];if(id){meta.collapsed[id]=!meta.collapsed[id];renderAll();}}],['Next / previous iteration · ] and [ (or ← → on a selector)',()=>stepProbe(1)],['Compose shell layouts',layoutDialog],['Go to node · / or Ctrl K',()=>$('.ol-search')?.focus()],['Undo · Ctrl/⌘ Z',()=>undo()],['Redo · Ctrl/⌘ Shift Z',()=>undo(true)],['Return to call · Esc',returnToCall],['Restore default shell',()=>applyLayout('three')]];
  const draw=()=>{const s=$('#action-search').value.toLowerCase();$('#actions').innerHTML=entries.filter(e=>e[0].toLowerCase().includes(s)).map(e=>`<button class="action" data-i="${entries.indexOf(e)}">${esc(e[0])}</button>`).join('');$$('#actions .action').forEach(b=>b.onclick=()=>{$('#dialog').close();entries[Number(b.dataset.i)][1]();});};
  $('#action-search').oninput=draw;draw();$('#action-search').focus();
}
function stepProbe(d){const z=focusZone();if(!z)return;const zz=program.zones.get(z);const n=zz?(zz.kind==='fold'?zz.states.length-1:zz.count):1;probe[z]=Math.max(0,Math.min(n-1,(probe[z]||0)+d));renderAll(true);}
function applySource(){
  try{const next=M.read(draft);compileDoc(next);dirty=false;commit(next,'Source checked and applied in one transaction.');}
  catch(e){dirty=true;status('Draft error · '+e.message,true);updateDirtyUI();}
}

/* ---------- host chrome ---------- */
$('#close-dialog').onclick=()=>$('#dialog').close();
$('#undo').onclick=()=>undo();$('#redo').onclick=()=>undo(true);$('#help').onclick=actions;
$('#layouts').onclick=layoutDialog;$('#recover').onclick=()=>applyLayout('three');
$('#casesel').innerHTML=Cases.CASES.map(c=>`<option value="${c.key}">${esc(c.title)}</option>`).join('');
$('#casesel').onchange=e=>loadCase(e.target.value);
$('#export').onclick=()=>{const text=M.print(ast)+'\n',fallback=()=>dialog('Copy the Lisp',`<p>Select all and copy.</p><pre>${esc(text)}</pre>`);try{navigator.clipboard.writeText(text).then(()=>status('Copied the applied Lisp. Positions and collapsed zones are layout, not Lisp.'),fallback);}catch(e){fallback();}};
document.addEventListener('keydown',e=>{
  const text=/INPUT|TEXTAREA|SELECT/.test(e.target.tagName);
  if((e.metaKey||e.ctrlKey)&&e.key==='Enter'&&e.target.classList?.contains('doc-src')){e.preventDefault();applySource();return;}
  if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==='k'){e.preventDefault();$('.ol-search')?.focus();return;}
  if(text||$('#dialog').open)return;
  if(!e.target.closest?.('.app')&&e.target!==document.body)return;
  if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==='z'){e.preventDefault();undo(e.shiftKey);return;}
  if(e.metaKey||e.ctrlKey||e.altKey)return;
  const key=e.key.toLowerCase();
  if(key==='r'){e.preventDefault();wrapInLoop(e.shiftKey?'fold':'for');}
  else if(key==='l'){e.preventDefault();makeLocalFn();}
  else if(key==='m'){e.preventDefault();makeMacroDialog();}
  else if(key==='b'){const id=[...selection][0];if(id)toggleBypass(id);}
  else if(key==='n'){const id=[...selection][0];if(id){e.preventDefault();requestAnimationFrame(()=>document.querySelector('.ibody .notearea')?.focus());}}
  else if(key==='f')extractDialog();else if(key==='a'){e.preventDefault();openPalette(null,null,view.root);}
  else if(key==='c'){const id=[...selection][0];const n=view?.all.get(id);if(n?.kind==='zone'){meta.collapsed[id]=!meta.collapsed[id];renderAll();}}
  else if(key===']'||key==='['){e.preventDefault();stepProbe(key===']'?1:-1);}
  else if(key==='delete'||key==='backspace'){e.preventDefault();deleteSelected();}
  else if(key==='escape'){if(returnScope)returnToCall();else if(selection.size){selection=new Set();piece=null;renderAll();}}
  else if(key==='/'){e.preventDefault();$('.ol-search')?.focus();}
  else if(key==='?')actions();
});

/* ---------- page: case gallery and ambiguity register ---------- */
function plispOf(c){
  const a=M.read(c.lisp),name=c.key;
  const kept=M.print(['workspace',a[1],...a.slice(2).filter(f=>!(f[0]==='graph'&&f[3]==='editor'&&c.key!=='variations'))]);
  return `; sketches/${name}/sketch.rays: the only authored file. dune build checks it and links sketches/${name}/main.exe.\n${kept}\n\n; generated into sketches/dune.rays.inc by rays-plisp dune sketches\n(subdir ${name}\n (rule (target main.ml) (deps sketch.rays)\n  (action (with-stdout-to %{target} (run %{bin:rays-plisp} ml sketch.rays))))\n (executable (name main) (modules main) (libraries rays_editor)))`;
}
function renderGallery(){
  const host=$('#gallery');if(!host)return;
  const scenes={};
  host.innerHTML=Cases.CASES.map(c=>{try{const p=M.compile(withShell(c.lisp)),sc=[...p.cache.values()].find(v=>v.t==='scene');scenes[c.key]=sc?sc.d.items:[];}catch(e){scenes[c.key]=[];}
    return `<article class="case"><div class="cthumb"><canvas data-thumb="${c.key}" width="120" height="120" aria-hidden="true"></canvas></div><div class="cbody"><span class="eyebrow">${esc(c.tag)}</span><h3>${esc(c.title)}</h3><p>${esc(c.teaches)}</p><div class="cbtns"><button class="primary" data-open-case="${c.key}">Open in the studio</button><button data-ocaml="${c.key}">.rays file</button></div></div></article>`;}).join('');
  requestAnimationFrame(()=>host.querySelectorAll('canvas[data-thumb]').forEach(cv=>drawScene(cv,scenes[cv.dataset.thumb],{fitKey:'thumb'})));
  host.querySelectorAll('[data-open-case]').forEach(b=>b.onclick=()=>{loadCase(b.dataset.openCase);$('.app').scrollIntoView({behavior:'smooth',block:'start'});});
  host.querySelectorAll('[data-ocaml]').forEach(b=>b.onclick=()=>{const c=Cases.CASES.find(c=>c.key===b.dataset.ocaml);dialog(c.title+' · as a .rays sketch',`<p>A sketch is one <code>.rays</code> file with no OCaml wrapper. <code>dune build</code> checks it against the catalog, reports errors at lines in the file, and links a native program. Save in the running sketch writes the file back, and editing the file reloads the window. <b>Proposed</b> (plan W11): today’s <code>[%flow]</code> takes one graph inside OCaml.</p><pre class="lisp">${hl(plispOf(c))}</pre>`);});
}
function renderRegister(){
  const host=$('#register');if(!host)return;
  const R=window.Register||[];let filter='all';
  const draw=()=>{const rows=R.filter(r=>filter==='all'||r.area===filter||r.status===filter);
    host.querySelector('.rlist').innerHTML=rows.map(r=>`<details class="amb ${r.status}"><summary><span class="aid">${esc(r.id)}</span><span class="aq">${esc(r.q)}</span><span class="ast">${r.status==='decided'?'proposed rule':'open'}</span></summary><div class="abody"><p><b>Why it is ambiguous.</b> ${esc(r.why)}</p><p><b>${r.status==='decided'?'Proposed rule':'Options'}.</b> ${esc(r.rule)}</p>${r.study?`<p class="hint">In the study: ${esc(r.study)}</p>`:''}</div></details>`).join('');
    host.querySelector('.rcount').textContent=`${rows.length} of ${R.length}`;};
  const areas=[...new Set(R.map(r=>r.area))];
  host.querySelector('.rfilter').innerHTML=['all',...areas,'open'].map(a=>`<button data-f="${a}" aria-pressed="${a==='all'}">${esc(a)}</button>`).join('');
  host.querySelector('.rfilter').onclick=e=>{const b=e.target.closest('[data-f]');if(!b)return;filter=b.dataset.f;host.querySelectorAll('.rfilter button').forEach(x=>x.setAttribute('aria-pressed',x===b));draw();};
  draw();
}
loadCase('bloom',false);renderGallery();renderRegister();
status('Checked · every context valid. Drag across a loop’s strip, or click a petal in the viewport.');
