const {chromium}=require(process.env.TERMINAL_PLAYWRIGHT_MODULE||"playwright");const fs=require("node:fs"),path=require("node:path"),assert=require("node:assert/strict");
(async()=>{const binary=process.env.GOOGLE_CHROME_BIN||"C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const browser=await chromium.launch({executablePath:binary,headless:true,args:["--use-angle=swiftshader","--enable-unsafe-swiftshader"]});
const base=process.env.TERMINAL_BASE_URL||"http://localhost:8037",live=process.env.TERMINAL_LIVE==="true",checks=[];
try{
 for(const width of [320,375]){
  const context=await browser.newContext({viewport:{width,height:850},isMobile:true,hasTouch:true,deviceScaleFactor:1});
  const page=await context.newPage();await page.goto(base+"/market");
  await page.waitForFunction(()=>window.Stimulus?.getControllerForElementAndIdentifier(document.querySelector('[data-controller="terminal-selector"]'),"terminal-selector"));
  await page.getByRole("button",{name:"Filters",exact:true}).tap();
  await page.locator("#market_terminal_search").fill(live?"Bezdek":"Shared");
  await page.waitForFunction(()=>document.querySelectorAll('[role="option"]').length>0);
  await page.locator('[role="option"]').first().tap();
  const id=await page.locator('input[name="terminal_api_id"]').inputValue();assert(/^[1-9]\d*$/.test(id));
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
  await page.getByRole("button",{name:"Apply",exact:true}).tap();
  await page.waitForFunction(()=>document.querySelectorAll("[data-market-group]").length===2);
  assert(new URL(page.url()).searchParams.get("terminal_api_id")===id);
  checks.push({width,touch:true,isMobile:true,terminal_api_id:id});await context.close();
 }
 const result={browser:"Google Chrome",binary,version:await browser.version(),emulation:"Chrome mobile/touch emulation; not a physical device test",live,checks};
 fs.writeFileSync(path.join(process.env.TERMINAL_EVIDENCE_DIR,"terminal-"+(live?"live":"preview")+"-touch.json"),JSON.stringify(result,null,2));
 console.log(JSON.stringify(result));
}finally{await browser.close()}
})().catch(error=>{console.error(error);process.exitCode=1});
