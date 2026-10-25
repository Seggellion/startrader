// Driver API launches the official installed Google Chrome executable only.
const { chromium } = require(process.env.TERMINAL_PLAYWRIGHT_MODULE || "playwright");
const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const chrome = process.env.GOOGLE_CHROME_BIN || "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const base = process.env.TERMINAL_BASE_URL || "http://localhost:8037";
const evidence = process.env.TERMINAL_EVIDENCE_DIR || path.join(__dirname, "../../tmp");
const live = process.env.TERMINAL_LIVE === "true";
fs.mkdirSync(evidence, {recursive:true});
const checks = [], errors = [], consoles = [];
const record = (name, detail={}) => { checks.push({name, ...detail}); console.log("PASS " + name); };
(async () => {
  assert(fs.existsSync(chrome), "Official Chrome executable missing");
  const browser = await chromium.launch({executablePath:chrome, headless:true, args:["--use-angle=swiftshader", "--enable-unsafe-swiftshader"]});
  const context = await browser.newContext({viewport:{width:1500,height:1000}});
  const page = await context.newPage();
  page.on("pageerror", error => errors.push(String(error)));
  page.on("console", message => { if(message.type()==="error") consoles.push(message.text()); });
  const ready = async () => {
    await page.waitForFunction(() => window.Stimulus?.getControllerForElementAndIdentifier(document.querySelector('[data-controller~="market-filters"]'),"market-filters") &&
      window.Stimulus?.getControllerForElementAndIdentifier(document.getElementById("market_results"),"market-results"));
    await page.evaluate(() => new Promise(resolve => requestAnimationFrame(resolve)));
  };
  const visit = async (url="/market") => { await page.goto(base+url); await ready(); };
  const input = () => page.locator("#market_terminal_search");
  const selected = () => page.locator('input[name="terminal_api_id"]');
  try {
    await visit();
    assert.equal(await page.locator('form[data-controller="market-filters"]').count(),1);
    assert.equal(await page.locator('[data-market-group]').count(),0);
    assert.equal(await page.locator('[role="option"]').count(),0);
    record("single responsive form; legacy feed; no selector preload", {browser:await browser.version()});
    await input().fill(live ? "Bezdek" : "Shared");
    await page.waitForFunction(() => document.querySelectorAll('[role="option"]').length > 0);
    assert((await page.locator('[role="option"]').count()) <=20);
    const optionText = await page.locator('[role="option"]').first().textContent();
    assert(optionText.includes("ID "));
    const priorURL = page.url();
    await input().press("ArrowDown");
    await input().press("Enter");
    const terminalId = await selected().inputValue();
    assert(/^[1-9]\d*$/.test(terminalId));
    assert.equal(page.url(),priorURL);
    assert.equal(await page.locator('[data-market-group]').count(),0);
    record("bounded contextual search and keyboard selection are drafts", {terminalId});
    await page.getByRole("button",{name:"Apply",exact:true}).click();
    await page.waitForURL(/terminal_api_id=/);
    await ready();
    assert.deepEqual(await page.locator("[data-market-group]").evaluateAll(nodes=>nodes.map(n=>n.dataset.marketGroup)),["buy","sell"]);
    assert((await page.locator('[data-market-group="buy"] article').count())<=50);
    assert((await page.locator('[data-market-group="sell"] article').count())<=50);
    record("explicit Apply, canonical identity and Buy/Sell order");

    if (!live) {
      assert.equal(terminalId,"900029");
      assert.equal(await page.locator('[data-group-count="buy"]').textContent(),"63");
      assert.equal(await page.locator('[data-group-count="sell"]').textContent(),"62");
      assert.equal(await page.locator('[data-market-group="buy"] article').count(),50);
      const allIds=await page.locator("[id]").evaluateAll(nodes=>nodes.map(n=>n.id));
      assert.equal(allIds.length,new Set(allIds).size);
      await visit("/market?terminal_api_id=900029&buy_page=1&sell_page=1");
      await page.getByRole("link",{name:"Next Sell page",exact:true}).click();
      await page.waitForFunction(()=>document.querySelectorAll('[data-market-group="sell"] article').length===12);
      await page.goBack();
      await page.waitForFunction(()=>new URL(location.href).searchParams.get("sell_page")==="1"&&document.querySelectorAll('[data-market-group="sell"] article').length===50);
      await page.goForward();
      await page.waitForFunction(()=>new URL(location.href).searchParams.get("sell_page")==="2"&&document.querySelectorAll('[data-market-group="sell"] article').length===12);
      await visit("/market?terminal_api_id=900029&buy_page=1&sell_page=1");
      record("first pagination from a direct URL restores actual rows on Back/Forward");
      await page.getByRole("link",{name:"Next Buy page",exact:true}).click();
      await page.waitForURL(/buy_page=2/);
      await page.waitForFunction(()=>document.querySelectorAll('[data-market-group="buy"] article').length===13);
      assert.equal(await page.locator('[data-market-group="buy"] article').count(),13);
      assert.equal(await page.locator('[data-market-group="sell"] article').count(),50);
      assert((await page.locator("body").innerText()).includes("No current quote"));
      record("full counts, overlap IDs, missing quotes, independent 50-row pages");
      await page.locator('input[name="q"]').fill("unsaved");
      await page.getByRole("link",{name:"Next Sell page",exact:true}).click();
      await page.waitForURL(/sell_page=2/);
      await page.waitForFunction(()=>document.querySelectorAll('[data-market-group="sell"] article').length===12);
      await page.waitForFunction(()=>document.querySelector('input[name="q"]').value==="");
      await page.goBack();
      await page.waitForFunction(()=>new URL(location.href).searchParams.get("sell_page")==="1"&&document.querySelectorAll('[data-market-group="sell"] article').length===50);
      await page.goForward();
      await page.waitForFunction(()=>new URL(location.href).searchParams.get("sell_page")==="2"&&document.querySelectorAll('[data-market-group="sell"] article').length===12);
      await page.reload();await ready();
      assert.equal(await selected().inputValue(),"900029");
      record("paging discards drafts; direct reload and back/forward restore canonical pages");

      await visit("/market?terminal_api_id=900029&buy_page=1&sell_page=1");
      await page.locator('input[name="q"]').fill("draft must survive");
      await page.evaluate(()=>{
        window.__refreshRequests=0;
        const real=window.fetch;
        window.fetch=(url,options)=>{if(options?.headers?.["Turbo-Frame"]==="market_results")window.__refreshRequests++;return real(url,options)};
      });
      const mutation=await page.evaluate(async()=>await (await fetch("/__terminal_test__/mutate",{method:"POST"})).json());
      await page.evaluate(({id,terminal_api_id})=>{
        window.__stream=(id,t)=>window.Turbo.renderStreamMessage('<turbo-stream action="replace" target="market_row_production_facility_'+id+'"><template><article data-terminal-api-id="'+t+'">BAD_UNGROUPED_INJECTION</article></template></turbo-stream>');
        for(let n=0;n<8;n++) window.__stream(id,terminal_api_id);
      },mutation);
      await page.waitForTimeout(350);
      assert.equal(await page.locator("text=BAD_UNGROUPED_INJECTION").count(),0);
      assert.equal(await page.evaluate(()=>window.__refreshRequests),0);
      assert.equal(await page.locator('input[name="q"]').inputValue(),"draft must survive");
      assert((await page.locator('[data-market-results-target="status"]').textContent()).includes("Updates available"));
      await page.getByRole("heading",{name:"Terminal Market",exact:true}).focus();
      const beforeRefreshScroll=await page.evaluate(()=>scrollY);
      await page.waitForFunction(()=>document.querySelector('[data-market-group="buy"]').textContent.includes("Changed by fixture"));
      assert.equal(await page.locator('input[name="q"]').inputValue(),"draft must survive");
      assert.equal(await page.locator('[data-group-count="sell"]').textContent(),"61");
      assert.equal(await page.evaluate(()=>window.__refreshRequests),1);
      await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(resolve)));
      assert.equal(await page.evaluate(()=>document.activeElement.id),"market_results_heading");
      assert(Math.abs((await page.evaluate(()=>scrollY))-beforeRefreshScroll)<=1);
      await page.evaluate(()=>{
        const holder=document.createElement("div");holder.id="unrelated_stream";document.body.append(holder);
        window.Turbo.renderStreamMessage('<turbo-stream action="update" target="unrelated_stream"><template>unrelated preserved</template></turbo-stream>');
      });
      await page.waitForFunction(()=>document.getElementById("unrelated_stream").textContent==="unrelated preserved");
      record("scoped burst invalidation, no ungrouped injection, draft preservation and unrelated streams");
      await page.evaluate(()=>{
        const real=window.fetch;window.__starts=[];window.__active=0;window.__maxActive=0;
        window.fetch=async(url,options)=>{
          if(options?.headers?.["Turbo-Frame"]!=="market_results")return real(url,options);
          window.__starts.push(Date.now());window.__active++;window.__maxActive=Math.max(window.__maxActive,window.__active);
          const response=await real(url,options);const first=window.__starts.length===1;
          return {ok:response.ok,text:async()=>{
            if(first)await new Promise(resolve=>window.__releaseRefresh=resolve);
            const text=await response.text();window.__active--;return text;
          }};
        };
      });
      await page.evaluate(({id,terminal_api_id})=>window.__stream(id,terminal_api_id),mutation);
      await page.waitForFunction(()=>typeof window.__releaseRefresh==="function");
      await page.evaluate(({id,terminal_api_id})=>{for(let n=0;n<10;n++)window.__stream(id,terminal_api_id)},mutation);
      await page.waitForTimeout(100);
      assert.equal(await page.evaluate(()=>window.__starts.length),1);
      await page.evaluate(()=>window.__releaseRefresh());
      await page.waitForFunction(()=>window.__starts.length===2&&window.__active===0);
      assert.equal(await page.evaluate(()=>window.__maxActive),1);
      assert((await page.evaluate(()=>window.__starts[1]-window.__starts[0]))>=990);
      record("one active refresh and one coalesced pending invalidation at one per second");
      await page.evaluate(async()=>await fetch("/__terminal_test__/mutate?mode=bulk",{method:"POST"}));
      await page.getByRole("link",{name:"Refresh results",exact:true}).click();
      await page.waitForFunction(()=>document.querySelector('[data-market-group="buy"]').textContent.includes("Bulk fixture change"));
      assert.equal(await page.locator('input[name="q"]').inputValue(),"draft must survive");
      record("explicit Refresh sees unbroadcast bulk changes and preserves drafts");
      await visit("/market?terminal_api_id=900029&buy_page=2&sell_page=2");
      const shrink=await page.evaluate(async()=>await (await fetch("/__terminal_test__/mutate?mode=shrink",{method:"POST"})).json());
      await page.evaluate(({id,terminal_api_id})=>{
        window.Turbo.renderStreamMessage('<turbo-stream action="replace" target="market_row_production_facility_'+id+'"><template><article data-terminal-api-id="'+terminal_api_id+'">BAD_UNGROUPED_INJECTION</article></template></turbo-stream>');
      },shrink);
      await page.waitForFunction(()=>new URL(location.href).searchParams.get("buy_page")==="1"&&new URL(location.href).searchParams.get("sell_page")==="1");
      assert((await page.locator('[data-market-group="buy"] article').count())<50);
      assert((await page.locator('[data-market-group="sell"] article').count())<50);
      record("automatic refresh clamps vanished last pages in both groups");
      await visit("/market?terminal_api_id=900029");
      await page.evaluate(()=>{
        const real=window.fetch,oldHTML=document.getElementById("market_results").outerHTML;
        window.fetch=(url,options)=>{
          if(options?.headers?.["Turbo-Frame"]==="market_results") {
            window.__staleSignal=options.signal;
            return Promise.resolve({ok:true,text:()=>new Promise(resolve=>window.__releaseStaleFrame=()=>resolve(oldHTML))});
          }
          return real(url,options);
        };
        const row=document.querySelector("[data-facility-id]");
        window.Turbo.renderStreamMessage('<turbo-stream action="replace" target="market_row_production_facility_'+row.dataset.facilityId+'"><template><article data-terminal-api-id="900029">STALE_INJECTION</article></template></turbo-stream>');
      });
      await page.waitForFunction(()=>typeof window.__releaseStaleFrame==="function");
      await page.locator('input[name="q"]').fill("No matching fixture");
      await page.getByRole("button",{name:"Apply",exact:true}).click();
      await page.waitForFunction(()=>document.querySelector('[data-group-count="buy"]')?.textContent==="0");
      assert.equal(await page.evaluate(()=>window.__staleSignal.aborted),true);
      await page.evaluate(()=>window.__releaseStaleFrame());
      await page.waitForTimeout(100);
      assert.equal(await page.locator('[data-group-count="buy"]').textContent(),"0");
      assert.equal(await page.locator('input[name="q"]').inputValue(),"No matching fixture");
      record("late automatic frame response is rejected after Apply navigation");
    }

    await visit("/market?terminal_api_id="+terminalId);
    await input().fill("Edited label");
    assert.equal(await selected().inputValue(),"");
    await page.getByRole("button",{name:"Clear terminal",exact:true}).click();
    assert.equal(await selected().inputValue(),"");
    assert.equal(await input().inputValue(),"");
    await page.locator('select[name="star_system"]').selectOption("Pyro");
    assert(!page.url().includes("star_system=Pyro"));
    record("editing/clear invalidate hidden identity; controls remain staged");
    await page.getByRole("link",{name:"Reset",exact:true}).click();
    await page.waitForURL(base+"/");await ready();
    assert.equal(await selected().inputValue(),"");
    assert.equal(await page.locator("[data-market-group]").count(),0);
    record("Reset restores legacy mode");
    if(!live) {
      await visit("/market?page=1");
      const firstLegacy=await page.locator('article[id^="market_row_production_facility_"]').first().getAttribute("id");
      await page.getByRole("link",{name:"Next Market page",exact:true}).click();
      await page.waitForURL(/page=2/);
      await page.waitForFunction(id=>document.querySelector('article[id^="market_row_production_facility_"]')?.id!==id,firstLegacy);
      await page.goBack();
      await page.waitForFunction(id=>new URL(location.href).searchParams.get("page")==="1"&&document.querySelector('article[id^="market_row_production_facility_"]')?.id===id,firstLegacy);
      record("legacy first pagination Back restores the original rows");
    }


    if(!live) {
      for (const phase of ["response","json","clear","system","selection"]) {
        await visit();
        await page.evaluate((phase)=>{
          window.__originalFetch=window.fetch;window.__calls=[];
          window.fetch=async(url,options)=>{
            if(!String(url).includes("/market/terminals?"))return window.__originalFetch(url,options);
            const query=new URL(String(url),location.href).searchParams.get("q");window.__calls.push(query);
            const data={results:[{terminal_api_id:query==="Old"?7771:7772,name:query==="Old"?"OLD":"NEW",context:"Host / Stanton",code:"RACE",star_system_name:"Stanton"}],has_more:false};
            if(query==="Old"&&phase!=="json")await new Promise(resolve=>window.__release=resolve);
            return {ok:true,json:async()=>{if(query==="Old"&&phase==="json")await new Promise(resolve=>window.__release=resolve);return data;}};
          };
        },phase);
        await input().fill("Old");
        await page.waitForFunction(()=>window.__calls.includes("Old")&&typeof window.__release==="function");
        if (phase === "clear") {
          await page.getByRole("button",{name:"Clear terminal",exact:true}).click();
        } else if (phase === "system") {
          await page.locator('select[name="star_system"]').selectOption("Pyro");
        } else {
          await input().fill("New");
          await page.waitForFunction(()=>document.querySelector('[role="option"]')?.textContent.includes("NEW"));
          if(phase==="selection")await input().press("Enter");
        }
        await page.evaluate(()=>window.__release());
        await page.waitForTimeout(100);
        if(phase==="clear"||phase==="system")assert.equal(await page.locator('[role="option"]').count(),0);
        else if(phase==="selection") {
          assert.equal(await selected().inputValue(),"7772");
          assert.equal(await input().inputValue(),"NEW");
        } else assert((await page.locator('[role="option"]').textContent()).includes("NEW"));
        record("stale "+phase+" response rejected");
      }
      await visit();
      await page.evaluate(()=>{window.__lookupCalls=0;const real=window.fetch;window.fetch=(...args)=>{if(String(args[0]).includes("/market/terminals?"))window.__lookupCalls++;return real(...args)}});
      await input().dispatchEvent("compositionstart");
      await input().fill("Shared");
      await page.waitForTimeout(400);
      assert.equal(await page.evaluate(()=>window.__lookupCalls),0);
      await input().dispatchEvent("compositionend");
      await page.waitForFunction(()=>window.__lookupCalls===1);
      await page.waitForFunction(()=>document.querySelectorAll('[role="option"]').length>0);
      await input().press("ArrowUp");
      assert.equal(await input().getAttribute("aria-activedescendant"),await page.locator('[role="option"]').last().getAttribute("id"));
      await input().press("Escape");assert.equal(await input().getAttribute("aria-expanded"),"false");
      await input().press("Tab");assert.notEqual(await page.evaluate(()=>document.activeElement.id),"market_terminal_search");
      record("IME composition debounce, Up/Escape/Tab focus");
      await visit("/market?terminal_api_id=900029");
      await page.evaluate(()=>{
        const real=window.fetch;let first=true;
        window.fetch=(url,options)=>{
          if(first&&String(url).includes("/market/terminals?")){first=false;return Promise.reject(new Error("Controlled network failure"))}
          return real(url,options);
        };
      });
      await page.getByRole("button",{name:"Search all systems",exact:true}).click();
      await page.waitForFunction(()=>!document.querySelector('[data-terminal-selector-target="retry"]').hidden);
      assert.equal(await selected().inputValue(),"900029");
      await page.getByRole("button",{name:"Retry search",exact:true}).click();
      await page.waitForFunction(()=>document.querySelectorAll('[role="option"]').length>0);
      assert.equal(await selected().inputValue(),"900029");
      record("search error/retry preserves selected identity");

      await visit("/market?terminal_api_id=900029&star_system=Pyro");
      assert((await page.locator('[role="alert"]').innerText()).includes("outside"));
      assert.equal(await page.locator("[data-facility-id]").count(),0);
      await visit("/market?terminal_api_id=29junk");
      assert.equal(await page.locator("[data-market-group]").count(),2);
      assert.equal(await page.locator("[data-facility-id]").count(),0);
      record("crafted mismatch and invalid identity never broaden results");
    }

    for(const width of [320,375]) {
      await page.setViewportSize({width,height:850});
      await visit();
      await page.getByRole("button",{name:"Filters",exact:true}).click();
      await input().fill(live?"Bezdek":"Shared");
      await page.waitForFunction(()=>document.querySelectorAll('[role="option"]').length>0);
      await page.locator('[role="option"]').first().click();
      await page.getByRole("button",{name:"Apply",exact:true}).click();
      await page.waitForURL(/terminal_api_id=/);await ready();
      assert.equal(await page.locator('[data-market-group]').count(),2);
      assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
      await page.screenshot({path:path.join(evidence,"terminal-"+(live?"live":"preview")+"-"+width+".png"),fullPage:false});
      record("mobile "+width+" px selection/Apply and no overflow");
    }
    if(!live) {
      await page.setViewportSize({width:320,height:850});
      await visit();
      await page.getByRole("button",{name:"Filters",exact:true}).click();
      await input().fill("LONG");
      await page.waitForFunction(()=>document.querySelectorAll('[role="option"]').length>0);
      await page.locator('[role="option"]').first().click();
      assert((await page.locator("#market_terminal_summary").textContent()).includes("New Babbage Hall"));
      assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1));
      await page.screenshot({path:path.join(evidence,"terminal-preview-long-label.png")});
      record("long selected name wraps recognizably in the 320 px filter panel");
    }
    await page.setViewportSize({width:1500,height:1000});
    await visit("/market?terminal_api_id="+terminalId);
    await page.locator('[data-market-group="buy"] button').first().click();
    assert((await page.locator('[data-market-board-target="selectedCommodity"]').first().textContent()).trim().length>0);
    await page.screenshot({path:path.join(evidence,"terminal-"+(live?"live":"preview")+"-desktop.png"),fullPage:false});
    record("map/details selection survives grouped rendering");
    assert.equal(errors.length,0,"Unexpected page errors: "+errors.join("\n"));
  } finally {
    const result={browser:"Google Chrome",binary:chrome,version:await browser.version(),base,live,checks,errors,consoleErrors:consoles,timestamp:new Date().toISOString()};
    fs.writeFileSync(path.join(evidence,"terminal-"+(live?"live":"preview")+"-chrome.json"),JSON.stringify(result,null,2));
    await browser.close();
  }
})().catch(error=>{console.error(error.stack);process.exitCode=1});
