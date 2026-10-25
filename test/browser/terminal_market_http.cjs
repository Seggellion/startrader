const fs=require("node:fs");
const path=require("node:path");
const base=process.env.TERMINAL_BASE_URL||"http://localhost:8037";
const out=process.env.TERMINAL_EVIDENCE_DIR||path.join(__dirname,"../../tmp");
const p95=x=>x.toSorted((a,b)=>a-b)[Math.ceil(x.length*.95)-1];
(async()=>{
const report={machine:{platform:process.platform,arch:process.arch,node:process.version},base,samples:[]};
for(const [name,url] of [["lookup","/market/terminals?q=Catalog"],["grouped","/market?terminal_api_id=900029"]]){
for(let i=0;i<3;i++)await(await fetch(base+url)).text();
const server=[],wall=[],bytes=[];
for(let i=0;i<30;i++){
 const start=performance.now(),r=await fetch(base+url),body=await r.text();
 if(r.status!==200)throw Error("HTTP "+r.status);
 wall.push(performance.now()-start);bytes.push(Buffer.byteLength(body));
 const runtime=r.headers.get("x-runtime");if(!runtime)throw Error("Missing server X-Runtime header");
 server.push(Number(runtime)*1000);
}
const value={name,sample_count:30,server_p95_ms:p95(server),wall_p95_ms:p95(wall),max_bytes:Math.max(...bytes)};

if(name==="lookup"&&value.max_bytes>20480)throw Error("payload budget");
report.samples.push(value);console.log(JSON.stringify(value));
}
fs.writeFileSync(path.join(out,"terminal-http-benchmark.json"),JSON.stringify(report,null,2));
for(const value of report.samples)if(value.server_p95_ms>(value.name==="lookup"?150:300))throw Error("p95 budget exceeded "+JSON.stringify(value));
})().catch(e=>{console.error(e);process.exitCode=1});
