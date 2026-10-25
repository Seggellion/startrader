// Official Chrome, read-only live observation; no fabricated stream or data write.
const {chromium}=require(process.env.TERMINAL_PLAYWRIGHT_MODULE||"playwright");const fs=require("node:fs"),path=require("node:path");
(async()=>{const binary=process.env.GOOGLE_CHROME_BIN||"C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const browser=await chromium.launch({executablePath:binary,headless:true,args:["--use-angle=swiftshader","--enable-unsafe-swiftshader"]});
const report={browser:"Google Chrome",binary,version:await browser.version(),started_at:new Date().toISOString(),market_messages:0,applicable_messages:0,page_errors:[],console_errors:[]};
const file=path.join(process.env.TERMINAL_EVIDENCE_DIR,"terminal-live-observation.json");
try{
 const page=await browser.newPage({viewport:{width:1500,height:1000}});
 await page.exposeBinding("recordTerminalMarketMessage",(_source,applicable)=>{report.market_messages++;if(applicable)report.applicable_messages++;});
 await page.addInitScript(()=>{
  document.addEventListener("turbo:before-stream-render",event=>{
   const stream=event.target;if(stream.getAttribute("action")!=="replace"||!/^market_row_production_facility_\d+$/.test(stream.getAttribute("target")||""))return;
   const row=stream.querySelector("template")?.content.querySelector("article");
   window.recordTerminalMarketMessage(row?.dataset.terminalApiId==="27");
  });
 });
 page.on("pageerror",e=>report.page_errors.push(String(e)));
 page.on("console",m=>{if(m.type()==="error")report.console_errors.push(m.text())});
 await page.goto("https://startrader.altama.energy/market?terminal_api_id=27");
 await page.waitForFunction(()=>window.Stimulus?.getControllerForElementAndIdentifier(document.getElementById("market_results"),"market-results"));
 report.ready_at=new Date().toISOString();console.log("Read-only live Chrome observation started");
 fs.writeFileSync(file,JSON.stringify(report,null,2));
 await new Promise(resolve=>setTimeout(resolve,600000));
 report.finished_at=new Date().toISOString();
 report.elapsed_seconds=(Date.parse(report.finished_at)-Date.parse(report.ready_at))/1000;
 report.final_url=page.url();
 report.group_counts=await page.locator("[data-group-count]").evaluateAll(nodes=>nodes.map(n=>({side:n.dataset.groupCount,count:n.textContent})));
 await page.screenshot({path:path.join(process.env.TERMINAL_EVIDENCE_DIR,"terminal-live-observation-final.png")});
 console.log(JSON.stringify(report));
}finally{fs.writeFileSync(file,JSON.stringify(report,null,2));await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
