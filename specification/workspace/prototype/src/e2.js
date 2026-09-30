/* ---------- layout: every scope lays out its own nodes; zones nest ---------- */
const expanded=n=>n.kind==='zone'&&!meta.collapsed[n.id];
const railRows=n=>n.inner?n.inner.rail.length:0;
const hasStrip=n=>n.kind==='zone'&&n.zkind!=='let*';
function nodeSize(n){
  if(n.kind==='param')return {w:NW,h:HH+n.rows.length*RH+FH};
  if(n.kind==='return')return {w:NW-40,h:HH+RH};
  if(n.kind==='zone'){
    if(!expanded(n))return {w:NW,h:HH+Math.max(1,railRows(n))*RH+FH,collapsed:true};
    const L=layoutScope(n.inner),bodyH=Math.max(railRows(n)*RH+8,L.h,RH+14);
    return {w:RAILW+PAD+Math.max(L.w,72)+PAD+YW,h:HH+(hasStrip(n)?STRIP:0)+bodyH+(n.zkind==='fold'||n.zkind==='scan'?22:10),L};
  }
  const outs=outRowsOf(n);n._outs=outs;n._outTop=HH+(n.note?RH:0)+n.rows.length*RH;
  const lens=n.macro&&meta.expanded?.[n.id]?macroLens(n):null;n._lens=lens;
  return {w:lens?Math.max(NW,LENSW):NW,h:HH+(n.note?RH:0)+n.rows.length*RH+outs.length*RH+FH+(lens?lens.h:0)};
}
const LENSW=400;
/* output rows: destructured names, or one per record field */
function outRowsOf(n){
  if(n.patNames)return n.patNames.map(nm=>({label:nm,src:nm,type:program.types.get(n.scope.id+'/'+nm),id:n.scope.id+'/'+nm}));
  const t=nodeType(n);const fs=t&&t.startsWith('rec{')?M.recFields(t):null;
  return fs?fs.map(([f,ft])=>({label:f,src:n.name+'.'+f,type:ft,field:f})):[];
}
/* macro lens: the expansion, one step at a time */
function macroLens(n){
  const steps=[n.expr];try{const st={n:0,size:0};let cur=n.expr;for(let i=0;i<12;i++){const nx=M.expandOnce(program,cur,st);if(nx===cur)break;steps.push(nx);cur=nx;}}catch(e){return {steps,err:e.message,h:3*RH};}
  const k=Math.min(meta.lensStep?.[n.id]??steps.length-1,steps.length-1);
  const text=M.print(steps[k]),lines=Math.min(16,text.split('\n').length);
  return {steps,k,text,h:RH+10+lines*15+RH};
}
function layoutScope(S){
  const items=[];
  if(S.isRoot)S.params.forEach(p=>items.push({n:p,deps:[]}));
  S.nodes.forEach(n=>items.push({n,deps:[...M.freeSymbols(n.expr)].filter(s=>S.names.has(s))}));
  if(S.isRoot){const ret={id:S.id+'/@return',name:'return',kind:'return',rows:[{label:'result',key:{result:1},type:CTXT[curForm()[3]],expr:S.result?.link||S.result?.expr,sock:true}],scope:S};S.ret=ret;items.push({n:ret,deps:S.result?.link?[S.result.link]:S.result?.node?['@result']:[]});}
  const level=new Map(),byName=new Map(items.map(it=>[it.n.name,it]));
  const lv=it=>{if(level.has(it.n.id))return level.get(it.n.id);level.set(it.n.id,0);let l=S.isRoot&&it.n.kind!=='param'&&S.params.length?1:0;it.deps.forEach(d=>{const o=byName.get(d);if(o)l=Math.max(l,lv(o)+1);});level.set(it.n.id,l);return l;};
  items.forEach(lv);
  const cols=[];items.forEach(it=>{const l=level.get(it.n.id);(cols[l]??=[]).push(it);});
  const pos=new Map();let x=12,W=0,H=0;
  cols.forEach(col=>{if(!col)return;let y=12,cw=0;col.forEach(it=>{const sz=nodeSize(it.n);const u=meta.pos[it.n.id];const px=u?u.x:x,py=u?u.y:y;pos.set(it.n.id,{x:px,y:py,...sz,n:it.n});y+=sz.h+18;cw=Math.max(cw,sz.w);W=Math.max(W,px+sz.w);H=Math.max(H,py+sz.h);});x+=cw+GAP;});
  return {w:W+12,h:H+12,pos};
}
/* absolute coordinates for everything drawn */
function place(L,ox,oy,out){
  L.pos.forEach((p,id)=>{const a={...p,x:ox+p.x,y:oy+p.y};out.set(id,a);if(p.L)place(p.L,a.x+RAILW+PAD,a.y+HH+(hasStrip(p.n)?STRIP:0)+4,out);});
  return out;
}
const railY=(a,j)=>a.y+HH+(hasStrip(a.n)?STRIP:0)+4+j*RH+12;
function srcPoint(S,name,abs){
  const base=String(name).split('.')[0];
  for(let s=S;s;s=s.parent){
    const e=s.names.get(base);if(!e)continue;
    if(e.param){const a=abs.get(e.id);return a&&{x:a.x+a.w,y:a.y+12};}
    if(e.node){const n=e.node,a=abs.get(n.id);if(!a)return null;
      const j=(n._outs||[]).findIndex(o=>o.src===name||(e.field&&o.src===e.field));
      if(j>=0&&!a.collapsed)return {x:a.x+a.w,y:a.y+n._outTop+j*RH+12};
      return {x:a.x+a.w,y:a.y+12};}
    if(e.rail){const o=s.owner,a=abs.get(o.id);if(!a||a.collapsed)return null;const j=s.rail.findIndex(r=>(r.names||[r.name]).includes(base));return {x:a.x+RAILW,y:railY(a,j)};}
  }
  return null;
}
function wirePath(a,b){if(b.x>=a.x+10){const mid=Math.max(a.x+14,Math.min(b.x-14,(a.x+b.x)/2));return `M ${a.x} ${a.y} H ${mid} V ${b.y} H ${b.x}`;}
  const dy=b.y>a.y?1:-1,ymid=(a.y+b.y)/2;return `M ${a.x} ${a.y} H ${a.x+12} V ${ymid} H ${b.x-12} V ${b.y} H ${b.x}`;}

/* ---------- rendering ---------- */
function tokHTML(e,sub=[]){
  const d=`data-sub='${JSON.stringify(sub)}'`;
  if(M.isNum(e))return `<span class="tnum" ${d}>${esc(M.atom(e))}</span>`;
  if(M.isStr(e))return `<span class="tstr">${esc(JSON.stringify(e.text))}</span>`;
  if(typeof e==='string')return `<span class="tsym">${esc(e)}</span>`;
  if(!isL(e))return esc(String(e));
  if(e.vector)return '['+[...e].map((x,i)=>tokHTML(x,[...sub,i])).join(' ')+']';
  if(M.isMap(e))return '{'+[...e].map((x,i)=>i%2===0?`<span class="tkw">${esc(x)}</span>`:tokHTML(x,[...sub,i])).join(' ')+'}';
  if(isFn(e))return `(<b>fn</b> [${esc([...e[1]].map(p=>M.print(p)).join(' '))}] ${tokHTML(e[2],[...sub,2])})`;
  if(isZone(e)){const vs=M.zoneVars(e);return `(<b>${e[0]}</b> [${vs.map(v=>`${esc(M.patKey(v.name))} ${tokHTML(v.expr,[...sub,...v.at])}`).join(' ')}] …)`;}
  return '(<b>'+esc(e[0])+'</b>'+e.slice(1).map((x,i)=>' '+(M.isKw(x)?`<span class="tkw">${esc(x)}</span>`:tokHTML(x,[...sub,i+1]))).join('')+')';
}
function chipHTML(n,row,e,ri){
  const data=`data-id="${esc(n.id)}" data-key='${JSON.stringify(row.key)}'`;
  const g=isZone(e)?(ZONE_GLYPH[e[0]]):isScope(e)?'let':M.isMap(e)?'{}':program.macros.has(e[0])?'◆':'ƒ';
  const txt=M.print(e).replace(/\s+/g,' ');
  return `<span class="aval chip${isZone(e)?' zchip z-'+e[0]:''}${program.macros.has(e[0])?' mchip':''}" ${data} title="${esc(txt)} · click ƒ to unfold into its own node"><b class="fbtn" ${data} data-unfold="1" data-sub='[]'>${g==='ƒ'?'ƒ':`<i>${esc(g)}</i>`}</b><span class="ctext" ${data}>${tokHTML(e)}</span></span>`;
}
function rowValHTML(n,row,S){
  const e=row.expr,data=`data-id="${esc(n.id)}" data-key='${JSON.stringify(row.key)}'`;
  if(editing&&editing.id===n.id&&JSON.stringify(editing.key)===JSON.stringify(row.key))return `<input class="aedit" ${data} value="${esc(e===undefined?M.print(row.def??''):M.print(e))}" spellcheck="false" aria-label="Edit ${esc(row.label)}">`;
  if(row.add)return row.addField?`<span class="aval ghost" ${data} data-edit="1" title="Type a name and a value, for example: size 0.5">name value…</span>`:`<span class="aval ghost${n.expr?.[0]==='list'||n.expr?.[0]==='str'?' addone':''}" ${data} ${n.expr?.[0]==='list'||n.expr?.[0]==='str'?'data-add="1"':''}>${n.expr?.[0]==='list'?'click to extend · or drop a wire':n.expr?.[0]==='str'?'click for a text part · or drop a wire':'drag a '+esc(tname(row.type))+' here'}</span>`;
  if(e===undefined){
    if(row.def===undefined)return `<span class="aval ghost" ${data}>—</span>`;
    const d=row.def;
    if(M.isNum(d)||typeof d==='number')return `<span class="aval num ghost tc-${tc(row.type)}" ${data} data-sub='[]' data-def="1" title="Default. Drag to override.">${esc(M.atom(d))}</span>`;
    if(Array.isArray(d))return `<span class="aval vecv ghost" ${data}>[${d.map((x,i)=>`<span class="tnum" data-sub='[${i}]' data-def="1">${esc(M.atom(x))}</span>`).join(' ')}]</span>`;
    return `<span class="aval ghost" ${data} data-edit="1">${esc(typeof d==='string'?d||'""':M.print(d))}</span>`;
  }
  if(typeof e==='string'&&!M.isKw(e)&&resolvableFrom(S,e))return `<span class="aval conn tc-${tc(typeOfName(S,e))}" ${data} data-goto="${esc(e)}">${typeOfName(S,e)==='fn'?'λ ':''}${esc(e)}</span>`;
  if(typeof e==='string'&&!M.isKw(e)&&(program.defs.has(e)||M.isOpName?.(e)||M.OPS[e])&&row.type==='fn')return `<span class="aval conn fnref" ${data} title="${esc(e)} passed as a function">λ ${esc(e)}</span>`;
  if(M.isNum(e))return `<span class="aval num tc-${tc(row.type==='int'||M.numOf(e)%1===0&&!M.isNum(e.float)&&typeof e==='number'?'int':'float')}" ${data} data-sub='[]' title="Drag to change · Shift for fine steps · click to type">${esc(M.atom(e))}</span>`;
  if(M.isStr(e)){const hex=/^#[0-9a-f]{6}$/i.test(e.text);const grp=row.kwType==='group'||row.kwType==='groupref';
    return `<span class="aval txt${grp?' grp':''}" ${data} data-edit="1">${hex?`<i class="swatch" style="background:${esc(e.text)}"></i>`:''}${grp?'<i class="gicon">▦</i>':''}${esc(e.text)}${grp&&row.kwType==='groupref'&&!groupMade(e.text)?' <em class="warn" title="No node upstream creates this group">?</em>':''}</span>`;}
  if(e&&e.vector)return `<span class="aval vecv" ${data}>[${e.map((x,i)=>M.isNum(x)?`<span class="tnum" data-sub='[${i}]'>${esc(M.atom(x))}</span>`:typeof x==='string'?`<span class="tsym">${esc(x)}</span>`:`<span class="tex" title="${esc(M.print(x))}">ƒ</span>`).join(' ')}]</span>`;
  if(isL(e))return chipHTML(n,row,e);
  return `<span class="aval" ${data} data-edit="1">${esc(M.print(e))}</span>`;
}
function resolvableFrom(S,name){name=String(name).split('.')[0];for(let s=S;s;s=s.parent)if(s.names.has(name))return true;return M.paramsOf(curForm()).some(p=>p[0]===name);}
let groupSet=new Set();
function groupMade(name){return groupSet.has(name);}
function spark(vals,sel){
  const nums=vals.map(v=>v&&(v.t==='float'||v.t==='int')?v.d:v&&v.t==='bool'?(v.d?1:0):null);if(nums.length<2||nums.some(x=>x===null))return '';
  const lo=Math.min(...nums),hi=Math.max(...nums),w=64,h=12,sx=i=>i/(nums.length-1)*w,sy=v=>hi===lo?h/2:h-(v-lo)/(hi-lo)*h;
  const d=nums.map((v,i)=>(i?'L':'M')+sx(i).toFixed(1)+' '+sy(v).toFixed(1)).join(' ');
  const k=Math.min(sel,nums.length-1);
  return `<svg class="spark" width="${w}" height="${h+2}" viewBox="0 -1 ${w} ${h+2}" aria-hidden="true"><path d="${d}"/><circle cx="${sx(k)}" cy="${sy(nums[k])}" r="2.2"/></svg>`;
}
function geoThumb(g,size=22,hi){
  if(!g||!g.prims)return '';const b=M.bbox(g);if(!isFinite(b.x0))return `<svg width="${size}" height="${size}"></svg>`;
  const s=Math.max(b.x1-b.x0,b.y1-b.y0)||1,f=(size-4)/s,ox=2+((size-4)-(b.x1-b.x0)*f)/2,oy=2+((size-4)-(b.y1-b.y0)*f)/2;
  const P=pt=>`${(ox+(pt[0]-b.x0)*f).toFixed(1)},${(size-oy-(pt[1]-b.y0)*f).toFixed(1)}`;
  const body=g.prims.slice(0,300).map(p=>p.point||p.pts.length===1?`<circle cx="${P(p.pts[0]).split(',')[0]}" cy="${P(p.pts[0]).split(',')[1]}" r="0.8"/>`:`<${p.closed?'polygon':'polyline'} points="${p.pts.map(P).join(' ')}"/>`).join('');
  return `<svg class="thumb${hi?' on':''}" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" aria-hidden="true">${body}</svg>`;
}
function stripHTML(n){
  const z=program.zones.get(n.id),chain=zoneChain(n.scope),outer=chain.map(c=>probe[c]||0);
  if(!z)return `<div class="zstrip" data-zone="${esc(n.id)}"><span class="zread">not evaluated · ${n.scope.owner?'an enclosing branch or loop did not run':'no calls'}</span></div>`;
  const pick=a=>n.zkind==='fn'?a:a.filter(r=>r.it.length===outer.length+1&&outer.every((k,i)=>r.it[i]===k));
  const items=n.zkind==='fold'?pick(z.states).filter(s=>s.it[s.it.length-1]>=0):pick(z.items);
  const cnt=items.length,k=Math.min(probe[n.id]||0,Math.max(0,cnt-1));
  const iv=n.inner.rail.find(r=>r.role==='iter'||r.role==='param'),vals=iv?(n.zkind==='fn'?(program.records.get(n.id+'/:'+iv.name)||[]).map(r=>r.v):seriesOf(n.id+'/:'+iv.name,[...chain,n.id])):null;
  const cur=vals&&vals[k]?describe(vals[k]):k;
  const label=n.zkind==='fn'?`call ${k+1} of ${cnt}`:n.zkind==='fold'?`after step ${k+1} of ${cnt}`:n.zkind==='sum'?`term ${k+1} of ${cnt} · Σ ${describe(recordAt(n.id,chain))}`:`${k+1} of ${cnt}`;
  const frac=cnt>1?k/(cnt-1):0,ticks=cnt>1&&cnt<=48?`background-size:calc(100% / ${cnt-1}) 100%`:'';
  return `<div class="zstrip zsel" data-zone="${esc(n.id)}"><button class="zstep" data-zstep="-1" data-zone="${esc(n.id)}" aria-label="Previous ${n.zkind==='fn'?'call':'iteration'}"${k<=0?' disabled':''}>‹</button><div class="ztrack${ticks?' ticked':''}" data-zone="${esc(n.id)}" data-cnt="${cnt}" role="slider" tabindex="0" aria-label="${n.zkind==='fn'?'Call':'Iteration'}" aria-valuemin="1" aria-valuemax="${cnt}" aria-valuenow="${k+1}" style="${ticks}"><i class="zfill" style="width:${frac*100}%"></i><i class="zthumb" style="left:${frac*100}%"></i></div><button class="zstep" data-zstep="1" data-zone="${esc(n.id)}" aria-label="Next ${n.zkind==='fn'?'call':'iteration'}"${k>=cnt-1?' disabled':''}>›</button><span class="zread">${iv?`<b>${esc(iv.name)} = ${esc(cur)}</b> · `:''}${esc(label)}</span></div>`;
}
const expandedWidth=n=>{const L=layoutScope(n.inner);return RAILW+PAD+Math.max(L.w,72)+PAD+YW;};
function nodeFoot(n,S){
  const chain=zoneChain(S),v=recordAt(n.id,chain),recs=program.records.get(n.id)||[],t=nodeType(n);
  let h=`<span class="fv">${v?esc(describe(v)):chain.length&&recs.length?'<em>not run here</em>':esc(tname(t))}</span>`;
  if(chain.length){
    const ser=seriesOf(n.id,chain);if(ser&&ser.length>1)h+=spark(ser,probe[chain[chain.length-1]]||0);
    if(n.expr&&isL(n.expr)&&n.expr[0]==='if'&&typeof n.expr[1]==='string'){const cs=seriesOf(n.scope.id+'/'+n.expr[1],chain)||[];const a=cs.filter(x=>x?.d).length;if(cs.length)h+=`<span class="fb">then ${a} · else ${cs.length-a}</span>`;}
    if(!variesIn(n))h+=`<button class="inv" data-hoist="${esc(n.id)}" title="The same in every iteration. Click to move it out of the loop; the result is identical.">↥ same each time</button>`;
    else h+=`<span class="fb">×${recs.length}</span>`;
  }
  if(isL(n.expr)&&n.expr[0]==='filter'&&v?.d){const src=n.expr[2],sv=typeof src==='string'?recordAt(n.scope.id+'/'+src,chain):null;if(sv?.d)h+=`<span class="fb">kept ${v.d.length} of ${sv.d.length}</span>`;}
  if(n.bypass)h+=`<span class="fb byp">bypassed</span>`;
  return h;
}
function nodeHTML(n,a,S){
  const sel=selection.has(n.id),t=nodeType(n),cls=tc(t);
  if(n.kind==='return'){
    const e=n.rows[0].expr;
    return `<div class="node return${sel?' selected':''}" data-id="${esc(n.id)}" style="left:${a.x}px;top:${a.y}px;width:${a.w}px"><div class="ntitle" data-id="${esc(n.id)}"><span class="nname">return</span><span class="nop">${esc(tname(n.rows[0].type))}</span></div><div class="arow" data-id="${esc(n.id)}" data-key='{"result":1}' data-type="${esc(n.rows[0].type)}"><i class="sock in tc-${tc(n.rows[0].type)}${e!==undefined?' on':''}" data-id="${esc(n.id)}" data-key='{"result":1}'></i><span class="alabel">result</span><span class="aval ${typeof e==='string'?'conn':''}">${esc(typeof e==='string'?e:e===undefined?'—':'@result')}</span></div></div>`;
  }
  const rows=n.rows.map((row,i)=>{
    const ps=piece&&piece.id===n.id&&JSON.stringify(piece.key)===JSON.stringify(row.key);
    const on=row.expr!==undefined&&[...M.freeSymbols(row.expr??0)].some(s=>resolvableFrom(S,s));
    return `<div class="arow${ps?' psel':''}${row.add?' addrow':''}" data-id="${esc(n.id)}" data-key='${JSON.stringify(row.key)}' data-type="${esc(row.type||'')}">${row.sock?`<i class="sock in tc-${tc(row.type)}${on?' on':''}" data-id="${esc(n.id)}" data-key='${JSON.stringify(row.key)}'></i>`:''}<span class="alabel${row.hole?' holel':''}" data-id="${esc(n.id)}" data-key='${JSON.stringify(row.key)}'>${esc(row.label)}</span>${row.binder&&typeof row.expr==='string'?`<span class="aval binder" data-id="${esc(n.id)}" data-key='${JSON.stringify(row.key)}' data-edit="1" title="A name you choose: the macro binds it, and the other holes can use it">${esc(row.expr)}</span>`:rowValHTML(n,row,S)}${row.item&&row.key.pos>0?`<button class="mv" data-up="${esc(n.id)}" data-pos="${row.key.pos}" title="Move up">↑</button>`:''}</div>`;
  }).join('');
  const fi=foldInfo(n);
  const title=n.kind==='param'?'input':n.pattern?(M.isMap(n.pattern)?'split record':'split list'):headLabel(n.expr),fn=isL(n.expr)&&program.defs.has(n.expr[0]),mac=isL(n.expr)&&program.macros.has(n.expr[0]);
  const nm=(mac?'<span class="mglyph">◆</span>':'')+(n.synthetic?'<i>result</i>':esc(n.name));
  const canBypass=!n.synthetic&&!mac&&n.kind==='node'&&isL(n.expr)&&!n.expr.vector&&!M.isMap(n.expr)&&!['list','fn','values','cond','case','str','if','get','assoc'].includes(n.expr[0]);
  const note=n.note?`<div class="nnote" data-note="${esc(n.id)}" title="${esc(n.note)}">✎ ${esc(n.note)}</div>`:'';
  const outs=(n._outs||[]).map(o=>{const ov=o.id?recordAt(o.id,zoneChain(S)):(()=>{const w=recordAt(n.id,zoneChain(S));return w?.d&&o.field?{t:o.type,d:w.d[o.field]}:null;})();
    return `<div class="orow"><span class="olab">${esc(o.label)}</span><span class="oval">${ov?esc(describe(ov)):esc(tname(o.type))}</span><i class="sock out tc-${tc(o.type)}${o.type&&o.type.startsWith('list:')?' multi':''}" data-src="${esc(o.src)}" data-sid="${esc(S.id)}" data-role="node" title="${esc(o.src)}"></i></div>`;}).join('');
  const L=n._lens,lens=L?`<div class="mlens"><div class="lsteps">${L.steps.map((_,i)=>`<button class="lstep${i===L.k?' on':''}" data-lens="${esc(n.id)}" data-step="${i}">${i===0?'call':i}</button>`).join('')}<span class="lread">${L.err?esc(L.err):L.k===0?'as written':`after ${L.k} expansion step${L.k>1?'s':''}`}</span></div><pre class="lcode">${hl(L.text||'')}</pre><div class="lbtns"><button data-inline="${esc(n.id)}">Replace call with expansion</button><button data-macro-src="${esc(n.macro)}">Template</button></div></div>`:'';
  return `<div class="node ${n.kind}${fn?' function':''}${mac?' macro':''}${n.bypass?' bypassed':''}${sel?' selected':''}${n.synthetic?' synth':''}" data-id="${esc(n.id)}" tabindex="0" style="left:${a.x}px;top:${a.y}px;width:${a.w}px" aria-label="${esc(n.name)} ${esc(title)}">
    <div class="ntitle" data-id="${esc(n.id)}">${canBypass?`<button class="bflag${n.bypass?' on':''}" data-bypass="${esc(n.id)}" title="${n.bypass?'Bypassed: click to run it again':'Bypass: pass the first input through'}" aria-pressed="${!!n.bypass}">B</button>`:''}<span class="nname">${nm}</span><span class="nop">${esc(title)}${fn?' ›':''}</span>${mac?`<button class="lensbtn${L?' on':''}" data-lens-toggle="${esc(n.id)}" title="Show the expansion">⤵</button>`:''}${fi?`<button class="foldbtn" data-fold="${esc(n.id)}" title="Fold into ${esc(fi.consumer.name)} as an expression">ƒ</button>`:''}<i class="sock out tc-${cls}${t&&t.startsWith('list:')?' multi':''}" data-src="${esc(n.name)}" data-sid="${esc(S.id)}" data-role="node"></i></div>
    ${note}${rows}${outs}<div class="nfoot tc-${cls}">${nodeFoot(n,S)}</div>${lens}</div>`;
}
function zoneHTML(n,a,S){
  const sel=selection.has(n.id),t=nodeType(n),z=program.zones.get(n.id),cls=tc(t);
  const fi=foldInfo(n);
  const head=`<div class="ztitle" data-id="${esc(n.id)}"><button class="ztog" data-toggle="${esc(n.id)}" aria-label="${a.collapsed?'Expand':'Collapse'} ${esc(n.name)}" aria-expanded="${!a.collapsed}">${a.collapsed?'▸':'▾'}</button><span class="zglyph">${esc(ZONE_GLYPH[n.zkind])}</span><span class="nname">${n.synthetic?'<i>result</i>':esc(n.name)}</span><span class="nop">${esc(n.zkind==='let*'?n.inner.nodes.length+' bindings':n.zkind==='fn'?(z?z.count+' call'+(z.count===1?'':'s'):'no calls')+' · '+n.inner.rail.filter(r=>r.role==='param').map(r=>r.name).join(' ')+' → '+tname(program.types.get(n.id+'/@result')||z?.bodyType):(z?z.count+'×':'')+' '+tname(t))}</span>${fi?`<button class="foldbtn" data-fold="${esc(n.id)}" title="Fold into ${esc(fi.consumer.name)}">ƒ</button>`:''}<i class="sock out tc-${cls}${t&&t.startsWith('list:')?' multi':''}" data-src="${esc(n.name)}" data-sid="${esc(S.id)}" data-role="node"></i></div>`;
  const railRow=(r,j,collapsed)=>{
    const key=r.key?JSON.stringify(r.key):'';
    const lab=r.role==='capture'?`<span class="rname">${esc(r.name)}</span><span class="rnote" title="Captured from outside: the same value ${n.zkind==='fn'?'in every call':'in every iteration'}">${n.zkind==='fn'?'captured':'same for all'}</span>`:`<span class="rname">${esc(r.name)}</span><span class="rrole">${r.role==='acc'?'⟲ from':r.role==='param'?'param':'∈'}</span>`;
    const valRow={label:r.name,key:r.key,type:r.role==='acc'?null:'list:any',expr:r.expr,sock:true};
    const it=r.role!=='capture'?recordAt(n.id+'/:'+(r.names?.length===1?r.names[0]:r.name),[...zoneChain(S),n.id]):null;
    const val=r.role==='capture'?'':r.role==='param'?`<span class="aval ghost pval">${it?esc(describe(it)):esc(tname(program.types.get(n.id+'/:'+r.name)))}</span>`:rowValHTML(n,valRow,S);
    const on=r.role==='capture'||[...M.freeSymbols(r.expr??0)].some(s=>resolvableFrom(S,s));
    return `<div class="rrow ${r.role}" data-id="${esc(n.id)}" ${key?`data-key='${key}'`:''} data-rail="${esc(r.name)}">${r.role==='param'?'':`<i class="sock in${on?' on':''} tc-${tc(r.role==='capture'?typeOfName(S,r.name):r.role==='acc'?program.types.get(n.id+'/:'+r.name):'int')}" data-id="${esc(n.id)}" ${key?`data-key='${key}'`:''}></i>`}${lab}${val}${collapsed?'':`<i class="sock out src tc-${tc(program.types.get(n.id+'/:'+r.name)||typeOfName(S,r.name))}" data-src="${esc(r.name)}" data-sid="${esc(n.inner.id)}" data-role="${r.role}" title="${esc(r.name)}${it?' = '+esc(describe(it)):''}"></i>`}</div>`;
  };
  if(a.collapsed){
    return `<div class="node zone-card z-${n.zkind.replace('*','')}${sel?' selected':''}" data-id="${esc(n.id)}" tabindex="0" style="left:${a.x}px;top:${a.y}px;width:${a.w}px">${head}${n.inner.rail.map((r,j)=>railRow(r,j,true)).join('')||'<div class="rrow"><span class="rnote">no inputs</span></div>'}<div class="nfoot tc-${cls}">${esc(describe(recordAt(n.id,zoneChain(S))))}${z?` · ${z.count} iterations`:''}</div></div>`;
  }
  const res=n.inner.result,yl={for:'collect',scan:'collect',fold:'next',sum:'add','let*':'result',fn:'return'}[n.zkind];
  const ytxt=res?.link?esc(res.link):res?.node?'':M.isNum(res?.expr)||M.isStr(res?.expr)?esc(M.print(res.expr)):res?.expr?.vector?esc(M.print(res.expr)):'';
  const yieldRow=`<div class="yrow" data-id="${esc(n.id)}" data-yield="1" style="left:${a.w-YW}px;top:${HH+(hasStrip(n)?STRIP:0)+4}px;width:${YW}px"><i class="sock in on tc-${tc(program.types.get(n.id+'/@yield')||nodeType(res?.node||{}))}" data-id="${esc(n.id)}" data-yield="1"></i><span class="rname">${yl}</span><span class="aval ${res?.link?'conn':''}">${ytxt}</span></div>`;
  return `<div class="zone-fg k-${n.zkind.replace('*','')}${sel?' selected':''}" data-id="${esc(n.id)}" style="left:${a.x}px;top:${a.y}px;width:${a.w}px;height:${a.h}px">${head}${hasStrip(n)?stripHTML(n):''}<div class="rail" style="top:${HH+(hasStrip(n)?STRIP:0)+4}px;width:${RAILW}px">${n.inner.rail.map((r,j)=>railRow(r,j,false)).join('')}</div>${yieldRow}<span class="zkindnote">${esc(ZONE_LABEL[n.zkind])}</span></div>`;
}
function renderGraph(g){
  const canvas=g.querySelector('.gcanvas');
  try{view=buildView();}catch(e){canvas.innerHTML=`<p class="empty">${esc(e.message)}</p>`;return;}
  const L=layoutScope(view.root),abs=place(L,0,0,new Map());
  view.abs=abs;
  groupSet=new Set();(function walk(S){S.nodes.forEach(n=>{(n.rows||[]).forEach(r=>{if(r.kwType==='group'&&M.isStr(r.expr))groupSet.add(r.expr.text);});if(n.inner)walk(n.inner);});})(view.root);
  let bg='',fg='',wires='';
  const W=L.w+40,H=L.h+40;
  const wire=(p,q,t,dashed,extra='')=>{if(p&&q)wires+=`<path class="wire w-${tc(t)}${dashed?' dashed':''}${extra}" d="${wirePath(p,q)}"/>`;};
  const groupProducers=new Map(),groupUsers=[];
  (function draw(S){
    const nodesHere=[...(S.isRoot?S.params:[]),...S.nodes,...(S.isRoot&&S.ret?[S.ret]:[])];
    nodesHere.forEach(n=>{
      const a=abs.get(n.id);if(!a)return;
      if(n.kind==='zone'){
        if(!a.collapsed)bg+=`<div class="zone-bg z-${n.zkind.replace('*','')}${selection.has(n.id)?' selected':''}" data-scope="${esc(n.inner.id)}" data-zone="${esc(n.id)}" style="left:${a.x}px;top:${a.y}px;width:${a.w}px;height:${a.h}px"></div>`;
        fg+=zoneHTML(n,a,S);
        n.inner.rail.forEach((r,j)=>{const q={x:a.x,y:a.collapsed?a.y+HH+j*RH+12:railY(a,j)};
          if(r.role==='capture')wire(srcPoint(S,r.name,abs),q,typeOfName(S,r.name),false);
          else if(r.expr!==undefined)[...refsOf(r.expr)].forEach(s=>wire(srcPoint(S,s,abs),q,typeOfName(S,s),typeof r.expr!=='string'));});
        if(!a.collapsed){
          draw(n.inner);
          const res=n.inner.result,yq={x:a.x+a.w-YW,y:railY(a,0)};
          if(res?.link)wire(srcPoint(n.inner,res.link,abs),yq,typeOfName(n.inner,res.link),false);
          else if(res?.node){const b=abs.get(res.node.id);if(b)wire({x:b.x+b.w,y:b.y+12},yq,nodeType(res.node),false);}
          else if(isL(res?.expr))[...refsOf(res.expr)].forEach(s=>wire(srcPoint(n.inner,s,abs),yq,typeOfName(n.inner,s),true));
          if(n.zkind==='fold'||n.zkind==='scan'){const j=n.inner.rail.findIndex(r=>r.role==='acc'),x1=a.x+a.w-YW/2,x0=a.x+RAILW-8,yb=a.y+a.h-9,ya=railY(a,j);
            wires+=`<path class="feedback" d="M ${x1} ${yq.y+10} V ${yb} H ${x0} V ${ya+8}"/><text class="fbl" x="${(x0+x1)/2}" y="${yb-4}">⟲ next becomes ${esc(n.inner.rail[j]?.name||'acc')}</text>`;}
        }
        return;
      }
      fg+=nodeHTML(n,a,S);
      (n.rows||[]).forEach((row,i)=>{
        if(row.expr===undefined||(row.kwType==='group'||row.kwType==='groupref')&&M.isStr(row.expr)){if(row.kwType==='group'&&M.isStr(row.expr))groupProducers.set(row.expr.text,{x:a.x+a.w,y:a.y+HH+i*RH+12});if(row.kwType==='groupref'&&M.isStr(row.expr))groupUsers.push({name:row.expr.text,q:{x:a.x,y:a.y+HH+i*RH+12}});return;}
        const q={x:a.x,y:a.y+HH+i*RH+12};
        if(n.kind==='return'){if(S.result?.link)wire(srcPoint(S,S.result.link,abs),q,nodeType(S.names.get(S.result.link).node||{}),false);else if(S.result?.node){const b=abs.get(S.result.node.id);if(b)wire({x:b.x+b.w,y:b.y+12},q,nodeType(S.result.node),false);}return;}
        [...refsOf(row.expr)].forEach(s=>wire(srcPoint(S,s,abs),q,typeOfName(S,s),typeof row.expr!=='string'||String(s).includes('.')&&false,(isL(row.expr)&&row.expr[0]!=='fn'&&String(s)===String(row.expr[0]))||typeOfName(S,s)==='fn'?' fnw':''));
      });
    });
  })(view.root);
  groupUsers.forEach(u=>{const p=groupProducers.get(u.name);if(p)wires+=`<path class="glink" d="M ${p.x} ${p.y} C ${p.x+60} ${p.y}, ${u.q.x-60} ${u.q.y}, ${u.q.x} ${u.q.y}"/><text class="gll" x="${(p.x+u.q.x)/2}" y="${(p.y+u.q.y)/2-4}">▦ ${esc(u.name)}</text>`;});
  canvas.style.width=W+'px';canvas.style.height=H+'px';
  canvas.innerHTML=`${bg}<svg class="wires" width="${W}" height="${H}" aria-hidden="true">${wires}<path class="wire tmpw" d="" hidden/></svg>${fg}`;
  if(editing){const inp=canvas.querySelector('.aedit');if(inp&&!inp.dataset.focused){inp.dataset.focused='1';inp.focus();inp.select();}}
}

/* ---------- graph pointer interaction ---------- */
function canvasPoint(g,e){const r=g.querySelector('.gcanvas').getBoundingClientRect();return {x:e.clientX-r.left,y:e.clientY-r.top};}
function setSel(ids,pc=null){
  const same=selection.size===ids.size&&[...ids].every(n=>selection.has(n))&&JSON.stringify(piece)===JSON.stringify(pc);
  selection=ids;piece=pc;if(!same)renderAll();return !same;
}
function selectNode(id,multi,pc=null){if(multi){const s=new Set(selection);s.has(id)?s.delete(id):s.add(id);setSel(s,null);}else setSel(new Set([id]),pc);}
const keyOf=el=>el?.dataset.key?JSON.parse(el.dataset.key):null;
function scopeAt(g,e){const els=document.elementsFromPoint(e.clientX,e.clientY);const z=els.find(x=>x.classList?.contains('zone-bg'));
  if(!z)return {S:view.root,origin:{x:0,y:0}};const n=view.all.get(z.dataset.zone),a=view.abs.get(n.id);return {S:n.inner,origin:{x:a.x+RAILW+PAD,y:a.y+HH+(hasStrip(n)?STRIP:0)+4}};}
function visibleFrom(S,name){name=String(name).split('.')[0];for(let s=S;s;s=s.parent)if(s.names.has(name))return true;return M.paramsOf(curForm()).some(p=>p[0]===name);}
function targetScope(el){const id=el.dataset.id;if(!id)return null;const n=view.all.get(id);if(!n)return id.endsWith('/@return')?view.root:null;
  if(el.classList.contains('rrow')||el.closest('.rrow'))return n.scope; // outer socket of a rail row lives in the zone's parent scope
  if(el.dataset.yield||el.closest('.yrow'))return n.inner;return n.scope;}
function initGraph(g){
  let drag=null;
  g.addEventListener('pointerdown',e=>{
    if(e.button!==0)return;const t=e.target;
    if(t.closest('.aedit'))return;
    if(t.closest('.foldbtn')){fold(t.closest('.foldbtn').dataset.fold);e.preventDefault();return;}
    if(t.closest('[data-unfold]')){const b=t.closest('[data-unfold]');unfold(b.dataset.id,keyOf(b),JSON.parse(b.dataset.sub||'[]'));e.preventDefault();return;}
    if(t.closest('[data-toggle]')){const id=t.closest('[data-toggle]').dataset.toggle;meta.collapsed[id]=!meta.collapsed[id];renderAll();e.preventDefault();return;}
    if(t.closest('[data-hoist]')){hoist(t.closest('[data-hoist]').dataset.hoist);e.preventDefault();return;}
    const bt=t.closest('[data-bypass]');if(bt){toggleBypass(bt.dataset.bypass);e.preventDefault();return;}
    const lt=t.closest('[data-lens-toggle]');if(lt){const id=lt.dataset.lensToggle;meta.expanded={...(meta.expanded||{}),[id]:!meta.expanded?.[id]};renderAll();e.preventDefault();return;}
    const ls=t.closest('[data-lens]');if(ls){meta.lensStep={...(meta.lensStep||{}),[ls.dataset.lens]:Number(ls.dataset.step)};renderAll(true);e.preventDefault();return;}
    const il=t.closest('[data-inline]');if(il){inlineMacro(il.dataset.inline);e.preventDefault();return;}
    const msrc=t.closest('[data-macro-src]');if(msrc){macroDialog(msrc.dataset.macroSrc);e.preventDefault();return;}
    const up=t.closest('[data-up]');if(up){moveItem(up.dataset.up,Number(up.dataset.pos));e.preventDefault();return;}
    const ad=t.closest('[data-add]');if(ad){addItem(ad.dataset.id);e.preventDefault();return;}
    const nt=t.closest('[data-note]');if(nt){setSel(new Set([nt.dataset.note]));requestAnimationFrame(()=>document.querySelector('.ibody .notearea')?.focus());e.preventDefault();return;}
    const zs=t.closest('[data-zstep]');if(zs){e.preventDefault();stepZone(zs.dataset.zone,Number(zs.dataset.zstep));return;}
    const track=t.closest('.ztrack');
    if(track){e.preventDefault();g.setPointerCapture(e.pointerId);drag={kind:'probe',zone:track.dataset.zone};probeFrom(track,e);if(!selection.has(track.dataset.zone))setSel(new Set([track.dataset.zone]));return;}
    if(t.closest('.zstrip'))return;
    const out=t.closest('.sock.out');
    if(out){e.preventDefault();g.setPointerCapture(e.pointerId);const S=findScope(out.dataset.sid);drag={kind:'wire',src:out.dataset.src,S,role:out.dataset.role,from:out};g.classList.add('wiring');markTargets(g,drag);return;}
    const sin=t.closest('.sock.in');
    if(sin){e.preventDefault();const id=sin.dataset.id,n=view.all.get(id),key=keyOf(sin);
      if(!n||!key){status(sin.dataset.yield?'Drag an inner output onto collect to change what each iteration yields.':'Captured names come from inside the loop. Use them there, or connect something else.');return;}
      const row=(n.rows||[]).find(r=>JSON.stringify(r.key)===JSON.stringify(key));
      const cur=key.bv?getArg(n.expr,key):row?.expr;
      if(typeof cur==='string'&&visibleFrom(n.scope,cur))disconnect(id,key,row||{type:null,label:'collection'});
      return;}
    const num=t.closest('.num,.tnum');
    if(num&&!t.closest('.fbtn')){
      const holder=num.closest('[data-key]'),id=holder.dataset.id,key=keyOf(holder),sub=JSON.parse(num.dataset.sub||'[]');
      const row=view.all.get(id)?.rows?.find(r=>JSON.stringify(r.key)===JSON.stringify(key)),rt=row?.type;
      const v0=Number(num.textContent),isInt=rt==='int'||(!num.textContent.includes('.')&&!['float','vec3','color'].includes(rt));
      if(!selection.has(id)||JSON.stringify(piece?.key)!==JSON.stringify(key))setSel(new Set([id]),{id,key});
      e.preventDefault();g.setPointerCapture(e.pointerId);
      drag={kind:'scrub',id,key,sub,x0:e.clientX,v0,moved:false,pre:snapshot(),int:isInt,def:!!num.dataset.def};return;}
    const val=t.closest('.aval');
    if(val&&!val.classList.contains('conn')&&val.dataset.id){const id=val.dataset.id,key=keyOf(val);setSel(new Set([id]),{id,key});drag={kind:'edit',id,key};return;}
    if(val&&val.classList.contains('conn')){const n=view.all.get(val.dataset.id);const s=n&&resolveNodeId(n.scope,val.dataset.goto);if(s)setSel(new Set([s]));return;}
    const lab=t.closest('.alabel');if(lab){setSel(new Set([lab.dataset.id]),{id:lab.dataset.id,key:keyOf(lab)});return;}
    const node=t.closest('.node,.zone-fg');
    if(node){
      const id=node.dataset.id;if(e.shiftKey){selectNode(id,true);return;}
      if(!selection.has(id)||selection.size===1)setSel(new Set([id]),null);
      if(!t.closest('.ntitle,.ztitle'))return;
      e.preventDefault();g.setPointerCapture(e.pointerId);
      const ids=[...selection].filter(x=>view.abs.has(x)),start=canvasPoint(g,e);
      drag={kind:'move',ids,start,orig:new Map(ids.map(x=>[x,{...layoutRel(x)}])),moved:false,pre:snapshot()};return;}
    setSel(new Set(),null);
  });
  g.addEventListener('pointermove',e=>{
    if(!drag)return;
    if(drag.kind==='probe'){const s=g.querySelector(`.ztrack[data-zone="${CSS.escape(drag.zone)}"]`);if(s)probeFrom(s,e);return;}
    if(drag.kind==='wire'){const p=canvasPoint(g,e),r=drag.from.getBoundingClientRect(),c=g.querySelector('.gcanvas').getBoundingClientRect(),a={x:r.left-c.left+r.width/2,y:r.top-c.top+r.height/2},tmp=g.querySelector('.tmpw');if(tmp){tmp.removeAttribute('hidden');tmp.setAttribute('d',wirePath(a,p));tmp.setAttribute('class','wire tmpw w-'+tc(typeOfName(drag.S,drag.src)));}return;}
    if(drag.kind==='move'){const p=canvasPoint(g,e),dx=p.x-drag.start.x,dy=p.y-drag.start.y;if(!drag.moved&&Math.hypot(dx,dy)<4)return;drag.moved=true;
      const m=structuredClone(meta);drag.ids.forEach(n=>{const o=drag.orig.get(n);m.pos[n]={x:Math.max(0,Math.round((o.x+dx)/8)*8),y:Math.max(0,Math.round((o.y+dy)/8)*8)};});meta=m;renderAll(true);return;}
    if(drag.kind==='scrub'){const dx=e.clientX-drag.x0;if(!drag.moved&&Math.abs(dx)<4)return;drag.moved=true;
      const step=drag.int?1/6:(e.shiftKey?0.001:0.01),raw=drag.v0+dx*step,v=drag.int?Math.round(raw):Math.round(raw*1000)/1000;
      const n=view.all.get(drag.id);
      if(drag.key.param){liveEdit(f=>{const p=M.paramsOf(f).find(p=>p[0]===drag.key.param);p[3]=v;});}
      else if(drag.def){const row=n.rows.find(r=>JSON.stringify(r.key)===JSON.stringify(drag.key));const base=M.clone(Array.isArray(row.def)?M.vec(row.def.slice()):row.def);editRow(drag.id,drag.key,null,drag.sub.length?setSub(base,drag.sub,v):v,'',true);drag.def=false;}
      else editRow(drag.id,drag.key,drag.sub,drag.int?v:M.mkNum(v,!drag.int),'',true);
      const inLoop=n&&zoneChain(n.scope).length;status(`${n?.name||''} = ${v}${inLoop?' · a change inside a loop applies to every iteration':''}`);}
  });
  const finish=e=>{
    if(!drag)return;const d=drag;drag=null;g.classList.remove('wiring');g.querySelectorAll('.ok').forEach(x=>x.classList.remove('ok'));
    if(d.kind==='probe')return;
    if(d.kind==='wire'){
      g.querySelector('.tmpw')?.setAttribute('hidden','');
      const el=document.elementFromPoint(e.clientX,e.clientY),row=el?.closest('.arow,.rrow,.yrow');
      if(row){const T=targetScope(row);const id=row.dataset.id,key=keyOf(row);
        if(T&&!visibleFrom(T,d.src)){status(`${d.src} lives inside a loop or scope and is not visible here. Values leave a loop only through its result.`,true);return;}
        if(row.dataset.yield){const n=view.all.get(id);mutate(f=>{const r=scopeRef(f,[...n.loc.path,n.loc.name]),s=r.get();if(isScope(s))s[2]=d.src;else{const b=uniqueName(f,'body');r.set(['let*',M.vec([b,s]),d.src]);}},`${n.name} now yields ${d.src} each iteration.`);return;}
        if(row.classList.contains('rrow')&&!key){status('That is a captured name; it follows its source automatically.');return;}
        const want=row.dataset.type,have=typeOfName(T||view.root,d.src);
        if(id.endsWith('/@return')||!want||ok(have,want)||key?.bv)connect(d.src,id,key||{result:1},d.role);
        else status(`${d.src} is ${tname(have)}; this input takes ${tname(want)}.`,true);}
      else if(el&&el.closest('.gcanvas')&&!el.closest('.node,.zone-fg')){const {S,origin}=scopeAt(g,e);const p=canvasPoint(g,e);openPalette({x:p.x-origin.x,y:p.y-origin.y},d.src,S);}
      return;}
    if(d.kind==='move'){if(d.moved){past.push(d.pre);if(past.length>80)past.shift();future=[];status('Moved '+d.ids.map(i=>i.split('/').pop()).join(', ')+'. Positions are layout, never Lisp.');renderAll();}return;}
    if(d.kind==='scrub'){if(d.moved){past.push(d.pre);if(past.length>80)past.shift();future=[];renderAll();}else{editing={id:d.id,key:d.key};renderAll();}return;}
    if(d.kind==='edit'){editing={id:d.id,key:d.key};renderAll();}
  };
  g.addEventListener('pointerup',finish);
  g.addEventListener('pointercancel',()=>{drag=null;g.classList.remove('wiring');});
  g.addEventListener('dblclick',e=>{
    const zt=e.target.closest('.ztitle');if(zt){const id=zt.dataset.id;meta.collapsed[id]=!meta.collapsed[id];renderAll();return;}
    const nd=e.target.closest('.node');if(nd){const n=view.all.get(nd.dataset.id);if(n&&isL(n.expr)&&program.defs.has(n.expr[0]))enterFunction(n.id);return;}
    if(e.target.closest('.gcanvas')&&!e.target.closest('.zone-fg')){const {S,origin}=scopeAt(g,e),p=canvasPoint(g,e);openPalette({x:p.x-origin.x,y:p.y-origin.y},null,S);}
  });
  g.addEventListener('keydown',e=>{
    const tr=e.target.closest?.('.ztrack');if(tr&&(e.key==='ArrowLeft'||e.key==='ArrowRight'||e.key==='Home'||e.key==='End')){e.preventDefault();const cnt=Number(tr.dataset.cnt)||1,z=tr.dataset.zone;probe[z]=e.key==='Home'?0:e.key==='End'?cnt-1:Math.max(0,Math.min(cnt-1,(probe[z]||0)+(e.key==='ArrowLeft'?-1:1)));renderAll(true);requestAnimationFrame(()=>document.querySelector(`.ztrack[data-zone="${CSS.escape(z)}"]`)?.focus());return;}
    const inp=e.target.closest?.('.aedit');
    if(inp){if(e.key==='Enter'){e.preventDefault();const ed=editing;editing=null;if(!setRowText(ed.id,ed.key,inp.value))editing=ed,renderAll();}
      else if(e.key==='Escape'){e.preventDefault();editing=null;renderAll();g.focus();}return;}
    if(e.key==='Enter'){const nn=e.target.closest?.('.node');const n=nn&&view.all.get(nn.dataset.id);if(n&&isL(n.expr)&&program.defs.has(n.expr[0])){e.preventDefault();enterFunction(n.id);}}
  });
  g.addEventListener('focusout',e=>{const inp=e.target.closest?.('.aedit');if(inp&&editing&&!drag){const ed=editing;editing=null;const n=view.all.get(ed.id);const row=n?.rows?.find(r=>JSON.stringify(r.key)===JSON.stringify(ed.key));const cur=ed.key.bv?getArg(n.expr,ed.key):ed.key.param?n.rows[0].expr:row?.expr;if(cur===undefined?inp.value.trim()!==M.print(row?.def??''):inp.value!==M.print(cur))setRowText(ed.id,ed.key,inp.value);else renderAll();}});
  g.addEventListener('dragover',e=>{if(e.dataTransfer.types.includes('text/x-prismel'))e.preventDefault();});
  g.addEventListener('drop',e=>{const key=e.dataTransfer.getData('text/x-prismel');if(!key)return;e.preventDefault();const entry=catalog().find(c=>c.key===key);if(!entry){status('That item cannot be placed in this context.',true);return;}const {S,origin}=scopeAt(g,e),p=canvasPoint(g,e);addNode(entry,{x:p.x-origin.x,y:p.y-origin.y},null,S);});
}
function layoutRel(id){ // position relative to the node's scope origin
  const a=view.abs.get(id),n=view.all.get(id)||{scope:view.root};const o=n.scope?.owner?view.abs.get(n.scope.owner.id):null;
  return o?{x:a.x-(o.x+RAILW+PAD),y:a.y-(o.y+HH+(hasStrip(n.scope.owner)?STRIP:0)+4)}:{x:a.x,y:a.y};
}
function findScope(id){let f=null;(function w(S){if(S.id===id)f=S;S.nodes.forEach(n=>n.inner&&w(n.inner));})(view.root);return f||view.root;}
function resolveNodeId(S,name){for(let s=S;s;s=s.parent){const e=s.names.get(name);if(!e)continue;if(e.node)return e.node.id;if(e.param)return e.id;if(e.rail)return s.owner.id;}return null;}
function probeFrom(track,e){
  const cnt=Number(track.dataset.cnt)||0;if(cnt<1)return;const r=track.getBoundingClientRect();
  const k=Math.max(0,Math.min(cnt-1,Math.round((e.clientX-r.left)/Math.max(1,r.width)*(cnt-1))));
  if(probe[track.dataset.zone]!==k){probe[track.dataset.zone]=k;renderAll(true);}
}
function stepZone(zone,d){const tr=document.querySelector(`.ztrack[data-zone="${CSS.escape(zone)}"]`),cnt=Number(tr?.dataset.cnt)||0;if(!cnt)return;probe[zone]=Math.max(0,Math.min(cnt-1,(probe[zone]||0)+d));if(!selection.has(zone))selection=new Set([zone]);renderAll(true);}
function markTargets(g,d){const t=typeOfName(d.S,d.src);g.querySelectorAll('.arow,.rrow[data-key],.yrow').forEach(r=>{const T=targetScope(r);if(!T||!visibleFrom(T,d.src))return;if(r.dataset.id&&r.dataset.id.startsWith(d.S.id+'/'+d.src))return;if(r.classList.contains('yrow')||r.classList.contains('rrow')||!r.dataset.type||ok(t,r.dataset.type))r.classList.add('ok');});}

/* ---------- add palette ---------- */
function openPalette(at,src,S=view.root){
  const type=src?typeOfName(S,src):null;
  const all=catalog().filter(c=>!src||c.make||(c.op&&[...c.op.pos.map(p=>p[1]),c.op.rest,...c.op.kw.map(k=>k[1])].some(t=>t&&ok(type,t)))||(c.def&&M.paramsOf(c.def).some(p=>ok(type,p[2]))));
  dialog(src?`Add a node fed by ${src}`:`Add a node${S.owner?' inside '+S.owner.name:''}`,`<label for="pal-q">Search operators, loops, functions and graphs</label><input id="pal-q" autocomplete="off" placeholder="circle, for, fold, Σ, ref…"><div id="pal-list" role="listbox"></div><p class="hint">${src?`Listing nodes that take a ${esc(tname(type))}. The new node is wired to ${esc(src)}.`:S.owner?`The node goes inside ${esc(S.owner.name)}, so it runs once per iteration.`:'Double-click inside a loop to add a node that runs once per iteration.'}</p>`);
  const q=$('#pal-q'),list=$('#pal-list');let items=[],cur=0;
  const draw=()=>{const s=q.value.trim().toLowerCase();items=all.filter(c=>!s||c.title.toLowerCase().includes(s)||c.sub.toLowerCase().includes(s));cur=Math.min(cur,Math.max(0,items.length-1));
    list.innerHTML=items.slice(0,60).map((c,i)=>`<button class="action pal${i===cur?' cur':''}" data-i="${i}"><b>${esc(c.title)}</b><span>${esc(c.sub)}</span></button>`).join('')||'<p class="hint">Nothing matches.</p>';
    list.querySelectorAll('.pal').forEach(b=>b.onclick=()=>pick(items[Number(b.dataset.i)]));};
  const pick=c=>{if(!c)return;$('#dialog').close();addNode(c,at,src,S);};
  q.oninput=()=>{cur=0;draw();};
  q.onkeydown=e=>{if(e.key==='ArrowDown'){e.preventDefault();cur=Math.min(items.length-1,cur+1);draw();}else if(e.key==='ArrowUp'){e.preventDefault();cur=Math.max(0,cur-1);draw();}else if(e.key==='Enter'){e.preventDefault();pick(items[cur]);}};
  draw();q.focus();
}

/* list and text parts: extend by one (continuing a numeric step) or move up */
function addItem(id){const n=nodeById(id);if(!n)return;
  mutate(f=>{const e=M.clone(getNodeExpr(f,n.loc)),{pos}=M.callArgs(e),vals=pos.map(p=>p.v);let v;
    if(e[0]==='str')v=M.str(' ');else{const a=vals[vals.length-1],b=vals[vals.length-2];v=M.isNum(a)&&M.isNum(b)?M.mkNum(Math.round((2*M.numOf(a)-M.numOf(b))*1000)/1000,!Number.isInteger(M.numOf(a))):a!==undefined?M.clone(a):0;}
    e.push(v);setNodeExpr(f,n.loc,e);},`${n.name} has ${M.callArgs(n.expr).pos.length+1} ${n.expr[0]==='str'?'parts':'items'}${n.expr[0]==='list'?'; the new one continues the step':''}.`);}
function moveItem(id,p){const n=nodeById(id);if(!n||p<1)return;
  mutate(f=>{const e=M.clone(getNodeExpr(f,n.loc)),{pos}=M.callArgs(e),i=pos[p].idx,j=pos[p-1].idx;[e[i],e[j]]=[e[j],e[i]];setNodeExpr(f,n.loc,e);},`Moved item ${p} of ${n.name} up.`);}
