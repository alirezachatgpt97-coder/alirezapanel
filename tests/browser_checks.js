/* Optional real Chromium checks, launched by native_integration.py.
   Requires Playwright and a working Chromium. No production URLs are used. */
const {chromium}=require('playwright');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const [base,output,id]=process.argv.slice(2);
(async()=>{
 const browser=await chromium.launch({headless:true,
   ...(process.env.CHROMIUM_EXECUTABLE?{executablePath:process.env.CHROMIUM_EXECUTABLE}:{}),
   args:process.env.CHROMIUM_ARGS?JSON.parse(process.env.CHROMIUM_ARGS):['--no-sandbox','--disable-dev-shm-usage']});
 const results=[];
 try{
  for(const locale of ['en-US','fa-IR'])for(const size of [{width:1366,height:900},{width:390,height:844}]){
   const context=await browser.newContext({viewport:size,locale,ignoreHTTPSErrors:true});
   await context.addCookies([{name:'lang',value:locale,url:base}]);
   const page=await context.newPage();const errors=[];const badPaths=[];
   page.on('pageerror',e=>errors.push(e.message));
   page.on('request',r=>{if(r.url().includes('/remote/'+id+'/_alireza/remote/'))badPaths.push(r.url())});
   const prefix=locale+'-'+size.width;
   await page.goto(base,{waitUntil:'domcontentloaded'});
   await page.locator('#lgt-user').waitFor({state:'visible'});
   await page.screenshot({path:output+'/'+prefix+'-login.png',fullPage:true});
   assert.equal(await page.getAttribute('html','dir'),locale.startsWith('fa')?'rtl':'ltr');
   await page.fill('#lgt-user','testadmin');await page.fill('#lgt-pass','Scratch-Only-Password-9876');
   await page.click('form.lgt-form button[type=submit]');
   await page.waitForURL(base+'panel/');await page.locator('.bo-content').waitFor({state:'visible'});
   await page.screenshot({path:output+'/'+prefix+'-dashboard.png',fullPage:true});
   for(const path of ['panel/admins','panel/nodes','_alireza/remote/'+id+'/panel/inbounds','panel/content']){
    await page.goto(base+path,{waitUntil:'domcontentloaded'});await page.locator('.bo-content').waitFor({state:'visible'});
    assert.equal(await page.locator('#app[v-cloak]').count(),0,'Vue did not mount');
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+2),'Document horizontally overflows');
    if(path==='panel/nodes')await page.frameLocator('#alireza-nodes').locator('#nodes-list').waitFor({state:'visible'});
    if(path.includes('/remote/')){
     await page.locator('#alireza-node-select').waitFor();await page.waitForFunction(()=>!document.querySelector('#alireza-node-select').disabled);
     assert.equal(await page.inputValue('#alireza-node-select'),id);
     assert.equal(await page.evaluate(async()=> (await HttpUtil.get('/panel/api/inbounds/list')).success),true);
    }
    if(path==='panel/content'){
     await page.waitForFunction(()=>document.querySelector('#alireza-content select').options.length>1);
     await page.selectOption('#alireza-content select',id);await page.locator('.ap-policy-card').first().waitFor();
     await page.locator('.ap-policy-card button').first().click();await page.locator('dialog').waitFor({state:'visible'});
     await page.locator('dialog button').last().click();assert.equal(await page.locator('dialog').count(),0);
    }
    await page.screenshot({path:output+'/'+prefix+'-'+path.split('/').pop()+'.png',fullPage:true});
   }
   assert.deepEqual(badPaths,[]);assert.deepEqual(errors,[]);
   await page.goto(base+'logout');await page.locator('#lgt-user').waitFor({state:'visible'});
   results.push({locale,width:size.width,passed:true});await context.close();
  }
  fs.writeFileSync(output+'/browser-results.json',JSON.stringify(results,null,2));console.log('Browser checks passed:',results.length);
 }finally{await browser.close()}
})().catch(e=>{console.error(e);process.exitCode=1});
