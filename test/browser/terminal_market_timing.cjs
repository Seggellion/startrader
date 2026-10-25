const {chromium}=require(process.env.TERMINAL_PLAYWRIGHT_MODULE||"playwright");const fs=require("node:fs"),path=require("node:path");
const p95=values=>values.toSorted((a,b)=>a-b)[Math.ceil(values.length*.95)-1];
(async()=>{const binary=process.env.GOOGLE_CHROME_BIN||"C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const browser=await chromium.launch({executablePath:binary,headless:true,args:["--use-angle=swiftshader","--enable-unsafe-swiftshader"]});
try{
 const page=await browser.newPage({viewport:{width:1500,height:1000}});
 const base=process.env.TERMINAL_BASE_URL||"http://localhost:8037", samples=[];
 for(let n=0;n<33;n++){
   const started=performance.now();const response=await page.goto(base+"/market?terminal_api_id=900029",{waitUntil:"domcontentloaded"});
   await page.waitForFunction(()=>window.Stimulus?.getControllerForElementAndIdentifier(document.getElementById("market_results"),"market-results"));
   await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
   const measured=await page.evaluate(()=>{const e=performance.getEntriesByType("navigation")[0];return {ttfb_ms:e.responseStart-e.requestStart,download_ms:e.responseEnd-e.responseStart,dom_ms:e.domContentLoadedEventEnd-e.responseEnd,offer_rows:document.querySelectorAll("[data-facility-id]").length}});
   measured.controls_and_paint_ms=performance.now()-started;measured.server_ms=Number(response.headers()["x-runtime"])*1000;
   if(n>=3)samples.push(measured);
   if(measured.offer_rows>100)throw Error("DOM bound");
 }
 const summary={browser:"Google Chrome",binary,version:await browser.version(),samples:samples.length,viewport:"1500x1000",max_offer_rows:Math.max(...samples.map(s=>s.offer_rows))};
 for(const key of ["ttfb_ms","download_ms","dom_ms","controls_and_paint_ms","server_ms"])summary[key+"_p95"]=p95(samples.map(s=>s[key]));
 fs.writeFileSync(path.join(process.env.TERMINAL_EVIDENCE_DIR,"terminal-chrome-timing.json"),JSON.stringify({summary,samples},null,2));
 console.log(JSON.stringify(summary));
}finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
