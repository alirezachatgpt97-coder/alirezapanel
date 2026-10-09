/* DOM/controller harness, not a substitute for real browser layout QA. */
const vm=require('node:vm'),fs=require('node:fs'),assert=require('node:assert/strict');
class Element{
 constructor(tag){this.tagName=tag;this.children=[];this.attributes={};this.value='';this.checked=false;this.dataset={};this.textContent='';this.isConnected=true;this.options=[];this.listeners={}}
 append(...items){for(const x of items){this.children.push(x);if(x&&typeof x==='object')x.parentElement=this}}
 replaceChildren(...items){this.children=[];this.append(...items)}
 setAttribute(k,v){this.attributes[k]=v}getAttribute(k){return this.attributes[k]}
 add(o){this.options.push(o);if(!this.value)this.value=o.value}
 addEventListener(k,fn){this.listeners[k]=fn}
 remove(){this.isConnected=false}showModal(){this.open=true}close(){this.open=false;this.listeners.close?.()}
}
async function test(lang){
 const main=new Element('main'),workspace=new Element('section'),body=new Element('body');
 const nav=new Element('aside');nav.__vue__={tabs:[{key:'/base/logout'}]};const requests=[];
 const c={window:{ALIREZA:{base:'/base/'}},location:{pathname:'/base/panel/content'},PERMS:{superAdmin:true},
  document:{documentElement:{lang,dir:lang==='fa'?'rtl':'ltr',setAttribute:()=>{}},body,
   querySelector:s=>s==='.bo-content'?main:s==='.bo-rail'?nav:null,
   getElementById:id=>id==='alireza-content'?workspace:null,createElement:t=>new Element(t),
   createTextNode:text=>({textContent:text}),addEventListener:()=>{}},
  Option:function(text,value){this.text=text;this.value=value},console,
  fetch:async(url,options)=>{requests.push({url,options});let data=url.endsWith('nodes/list')?{nodes:[{id:'edge',name:'Edge'}]}:
    url.includes('features/policy')?{policy_version:2,domains:['example.com']}:
    {success:true,obj:[{protocol:'vless',settings:JSON.stringify({clients:[{email:'client-one'}]})}]};
    return{ok:true,status:200,json:async()=>data,text:async()=>JSON.stringify(data)}},
  alert:()=>{},URLSearchParams,FormData:class{},setTimeout,clearTimeout,Map,Set};
 vm.createContext(c);vm.runInContext(fs.readFileSync(process.argv[2]+'/features.js','utf8'),c);
 await new Promise(r=>setTimeout(r,5));assert.equal(workspace.children[3].children.length,1);
 assert.ok(nav.__vue__.tabs.some(t=>t.key==='/base/panel/content'));
 const controls=workspace.children[1],select=controls.children[0].children[0];assert.equal(select.options.length,2);
 select.value='edge';await select.onchange();const grid=workspace.children[3];
 await grid.children[0].children[2].onclick();const dialog=body.children.at(-1);assert.equal(dialog.open,true);
 // Server choice after opening a dialog must not change the write's destination.
 select.value='local';await select.onchange();
 await dialog.children.at(-2).onclick();
 const writes=requests.filter(r=>r.url.includes('/features/policy')&&r.options?.body&&!JSON.parse(r.options.body).read);
 assert.equal(writes.length,1);assert.equal(writes[0].url,'/base/_alireza/remote/edge/_alireza/features/policy');
 const search=controls.children[1];search.value='absent';search.oninput();assert.equal(grid.children.length,0);
 console.log('DOM/control harness passed:',lang);
}
(async()=>{await test('en-US');await test('fa')})().catch(e=>{console.error(e);process.exit(1)});
