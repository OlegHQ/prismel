// Optional browser QA. Usage: node browser-check.cjs /absolute/path/to/playwright [chrome-executable]
const assert=require('node:assert/strict'),path=require('node:path');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.argv[2]||'playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.argv[3]?{executablePath:process.argv[3]}:{})});
 const page=await browser.newPage({viewport:{width:1440,height:1100}}),errors=[];
 page.on('pageerror',e=>errors.push(e.message));
 await page.goto(pathToFileURL(path.join(__dirname,'index.html')).href);
 const state=()=>page.evaluate(()=>({source:Workspace.print(ast),geometry:program.cache.get('geometry').data,accent:program.cache.get('accent').data,editor:program.cache.get('editor').data,selected:[...selection],scope,dirty}));
 assert.equal(await page.locator('.node').count(),5);
 await page.locator('.node[data-node="size"]').click();await page.locator('#expression').fill('0.9');await page.locator('#expression-form button').click();assert.equal((await state()).geometry.radius,.9);
 await page.locator('[data-view="list"]').click();assert.equal(await page.locator('.list-row.selected strong').textContent(),'size');
 await page.locator('[data-view="text"]').click();assert.ok((await page.locator('#source').inputValue()).includes('size 0.9'));
 const valid=await page.locator('#source').inputValue();await page.locator('#source').fill(valid.replace('size 0.9','size "oops"'));await page.locator('#apply').click();assert.match(await page.locator('#status').textContent(),/expected float/);assert.equal((await state()).geometry.radius,.9);assert.equal((await state()).dirty,true);
 await page.locator('#source').fill(valid.replace('size 0.9','size 0.8'));await page.locator('#apply').click();assert.equal((await state()).geometry.radius,.8);
 await page.locator('#undo').click();assert.equal((await state()).geometry.radius,.9);await page.locator('#redo').click();assert.equal((await state()).geometry.radius,.8);
 await page.locator('[data-view="graph"]').click();await page.locator('.node[data-node="flower"]').click();await page.locator('.arg-form[data-arg="0"] input').fill('0.6');await page.locator('.arg-form[data-arg="0"] button').click();assert.equal((await state()).geometry.radius,.6);await page.locator('.connection[data-arg="0"]').selectOption('size');assert.equal((await state()).geometry.radius,.8);
 await page.locator('.node[data-node="flower"]').dblclick();assert.equal((await state()).scope,'bloom');assert.match(await page.locator('#scope-info').textContent(),/geometry\/flower/);assert.match(await page.locator('.node[data-node="ring"] .node-value').textContent(),/12 petals/);
 await page.locator('.node[data-node="disc"]').click();await page.locator('#expression').fill('(sop/disc (* radius 0.5))');await page.locator('#expression-form button').click();assert.equal((await state()).geometry.radius,.4);assert.equal((await state()).accent.radius,.175);
 await page.locator('#return').click();assert.equal((await state()).scope,'geometry');assert.deepEqual((await state()).selected,['flower']);
 await page.locator('#unique').click();assert.ok((await state()).source.includes('bloom_copy'));await page.locator('#undo').click();assert.ok(!(await state()).source.includes('bloom_copy'));
 await page.locator('.node[data-node="size"]').click();await page.locator('.node[data-node="petals"]').click({modifiers:['Shift']});await page.locator('.node[data-node="flower"]').click({modifiers:['Shift']});
 const before=(await state()).geometry;await page.locator('#group').click();assert.equal(await page.locator('.group-frame').count(),1);await page.locator('#extract').click();await page.locator('#function-name').fill('study_flower');await page.locator('#confirm-extract').click();assert.ok((await state()).source.includes('defn study_flower'));assert.deepEqual((await state()).geometry,before);await page.locator('#undo').click();assert.ok(!(await state()).source.includes('defn study_flower'));
 await page.locator('[data-scope="settings"]').click();await page.locator('.node[data-node="exposure"]').click();await page.locator('#inspect-macro').click();assert.match(await page.locator('#dialog-body').textContent(),/\(\+ 0.5 0.5\)/);await page.locator('#close-dialog').click();
 await page.locator('[data-scope="editor"]').click();await page.locator('#layout-options').click();await page.locator('[data-layout="single"]').click();assert.equal((await state()).editor.panel.kind,'viewport');assert.equal(await page.locator('.shell-preview .shell-panel').count(),1);
 await page.locator('[data-layout="floating"]').click();assert.equal((await state()).editor.panel.children[1].kind,'floating');await page.locator('#close-dialog').click();await page.locator('#recover').click();assert.equal((await state()).editor.panel.children.length,2);assert.equal((await state()).editor.panel.axis,'vertical');
 await page.locator('[data-view="text"]').click();const saved=await page.locator('#source').inputValue();await page.locator('#source').fill(saved+'(');await page.locator('#recover').click();assert.equal((await state()).dirty,true);assert.match(await page.locator('#status').textContent(),/Unapplied Lisp draft/);await page.locator('#discard').click();
 await page.locator('#help').click();await page.locator('#action-search').fill('List');assert.equal(await page.locator('#actions button').count(),1);await page.locator('#actions button').click();assert.equal(await page.locator('#list-view').isVisible(),true);
 const download=page.waitForEvent('download');await page.locator('#export').click();assert.equal((await download).suggestedFilename(),'bloom-studio.flow.lisp');
 // Fresh page for keyboard traversal, source-shortcut isolation, and responsive overflow.
 const small=await browser.newPage({viewport:{width:760,height:1000}});small.on('pageerror',e=>errors.push(e.message));await small.goto(pathToFileURL(path.join(__dirname,'index.html')).href);
 await small.keyboard.press('Tab');assert.ok(await small.evaluate(()=>document.activeElement.tagName==='A'));
 await small.locator('[data-view="text"]').click();await small.locator('#source').focus();await small.keyboard.press('g');assert.equal(await small.locator('#text-view').isVisible(),true);
 assert.equal(await small.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true);
 await small.setViewportSize({width:390,height:844});assert.equal(await small.evaluate(()=>document.documentElement.scrollWidth<=window.innerWidth),true);
 // Inspect local proposal links without leaving the unsaved editor page.
 const proposal=await browser.newPage();await proposal.goto(pathToFileURL(path.join(__dirname,'proposal.html')).href);assert.match(await proposal.title(),/proposal/);assert.equal(await proposal.locator('h2').count(),5);
 const fs=require('node:fs');for(const href of await proposal.locator('a[href]').evaluateAll(as=>as.map(a=>a.getAttribute('href')))){if(!/^https?:/.test(href)&&!href.startsWith('#'))assert.ok(fs.existsSync(path.resolve(__dirname,decodeURIComponent(href))),href);}
 assert.deepEqual(errors,[]);console.log('Browser checks passed: views, drafts, undo/redo, caller preview, shared edits, uniqueness, grouping, extraction, macros, layouts, recovery, actions, export, keyboard, responsive widths and proposal links.');await browser.close();
})().catch(e=>{console.error(e);process.exit(1);});
