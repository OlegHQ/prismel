// Standalone design-artifact check. Run with Node; not part of Dune or native product.
const assert = require('node:assert/strict');
const M = require('./model.js');
let checks=0;
function check(name,fn){fn();checks++;console.log('✓ '+name);}
const build=s=>M.compile(M.read(s));
const workspace=body=>`(workspace test ${body})`;
check('initial document evaluates all six roots and two independent function calls',()=>{
 const p=build(M.initial);assert.equal(p.graphs.size,6);assert.equal(p.cache.get('geometry').data.count,12);assert.equal(p.cache.get('accent').data.count,7);assert.equal(p.cache.get('settings').data.exposure,1);assert.equal(p.cache.get('editor').data.panel.kind,'split');
});
check('canonical source round trip preserves results',()=>{const a=build(M.initial),b=build(M.print(a.ast));assert.deepEqual([...a.cache],[...b.cache]);assert.equal(M.print(b.ast),M.print(a.ast));});
check('shared definition edit changes both calls and unique copy isolates one',()=>{
 const ast=M.read(M.initial),fn=ast.find(f=>f?.[1]==='bloom');M.body(fn)[1][1]=['sop/disc',['*','radius',0.5]];let p=M.compile(ast);assert.equal(p.cache.get('geometry').data.radius,.35);assert.equal(p.cache.get('accent').data.radius,.175);
 const copy=M.clone(fn);copy[1]='unique';M.body(copy)[1][1]=['sop/disc',1];ast.splice(2,0,copy);M.body(ast.find(f=>f?.[1]==='accent'))[1][1][0]='unique';p=M.compile(ast);assert.equal(p.cache.get('geometry').data.radius,.35);assert.equal(p.cache.get('accent').data.radius,1);
});
check('a value function can serve SOP and settings contexts',()=>{const p=build(M.initial.replace('(twice 0.5)','(half 3.0)'));assert.equal(p.cache.get('settings').data.exposure,1.5);assert.equal(p.cache.get('geometry').data.twist,.4);});
check('macro parameters remain authored while expansion evaluates',()=>{const p=build(M.initial);assert.equal(p.macros.get('twice')[3][0],'+');assert.equal(p.cache.get('settings').data.exposure,1);assert.throws(()=>build(M.initial.replace('(+ x x)','(let* [x 1] x)')),/binding macros/);assert.throws(()=>build(M.initial.replace('(+ x x)','(+ x hidden)')),/Free macro/);});
check('type, arity, context, unbound and reserved names reject',()=>{
 assert.throws(()=>build(M.initial.replace('(bloom size petals)','(bloom size "many")')),/expected int/);
 assert.throws(()=>build(M.initial.replace('(half 0.8)','(half 0.8 1)')),/expects 1/);
 assert.throws(()=>build(M.initial.replace('(half 0.8)','(ui/graph)')),/cannot run in sop/);
 assert.throws(()=>build(M.initial.replace('(half 0.8)','missing')),/Unbound name/);
 assert.throws(()=>build(M.initial.replace('defn half','defn ref')),/reserved/);
});
check('graph cycles and function recursion reject before activation',()=>{
 assert.throws(()=>build(workspace('(graph a :context value (ref b)) (graph b :context value (ref a))')),/Graph cycle/);
 assert.throws(()=>build(workspace('(defn loop :context value [(x : float)] (loop x)) (graph a :context value 1)')),/Recursive call/);
});
check('unused functions are checked and cannot capture document graphs',()=>{
 assert.throws(()=>build(workspace('(defn bad :context value [] (wat 1)) (graph a :context value 1)')),/Unknown operator/);
 assert.throws(()=>build(workspace('(defn bad :context value [] (ref a)) (graph a :context value 1)')),/cannot capture/);
});
check('runtime checks reject division by zero and bounded geometry violations',()=>{
 assert.throws(()=>build(M.initial.replace('(half 0.8)','(/ 1 0)')),/Division by zero/);
 assert.throws(()=>build(M.initial.replace('petals 12','petals 100')),/Count must/);
 assert.throws(()=>build(M.initial.replace('size 0.7','size -1')),/Radius must/);
});
check('reader validates malformed input, depth and size',()=>{
 assert.throws(()=>M.read('(foo]'),/Unexpected/);assert.throws(()=>M.read('(foo'),/Missing/);assert.throws(()=>M.read('x y'),/one workspace/);assert.throws(()=>M.read('('.repeat(82)),/Nesting/);assert.throws(()=>M.read(' '.repeat(60001)),/limit/);
});
check('strings, comments and square-bracket bindings survive canonical printing',()=>{const x=M.read('(let* [label "a \\"quote\\" ; text"] label)'.replaceAll('\\"','\\"'));assert.equal(M.print(M.read(M.print(x))),M.print(x));assert.equal(M.read('; comment\n42'),42);});
console.log(`${checks} model checks passed.`);
