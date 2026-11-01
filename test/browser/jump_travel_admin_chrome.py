import subprocess,json,pathlib,hashlib,time
import argparse
parser=argparse.ArgumentParser(description='Google Chrome visual capture of synthetic Rails admin snapshots')
parser.add_argument('--output-dir',required=True,help='Absolute Windows output directory for screenshots and isolated Chrome profile')
args=parser.parse_args()
windows_root=args.output_dir.rstrip('\\/')
root=pathlib.Path(subprocess.check_output(['wslpath','-u',windows_root],text=True).strip())
root.mkdir(parents=True,exist_ok=True)
repo=pathlib.Path(__file__).resolve().parents[2]
chrome='/mnt/c/Program Files/Google/Chrome/Application/chrome.exe'
cases={'no-journey':'No matching journeys','scheduled':'Scheduled travel','interdicted':'No scheduled arrival while interdicted','interdicted-mismatch':'Player location differs from ship location','overdue':'Awaiting completion','invalid':'Invalid travel state'}
results=[]
for name,expected in cases.items():
 html_path=repo/'tmp/jump-travel-browser'/(name+'.html')
 url=pathlib.PureWindowsPath(subprocess.check_output(['wslpath','-w',str(html_path)],text=True).strip()).as_uri()
 target=windows_root+'\\jump-repair-'+name+'.png'
 args=[chrome,'--headless','--disable-gpu','--no-first-run','--no-default-browser-check','--disable-extensions',
 '--disable-background-networking','--user-data-dir='+windows_root+'\\jump-repair-chrome-profile',
 '--window-size=1440,1000','--screenshot='+target,'--dump-dom',url]
 try:
  result=subprocess.run(args,capture_output=True,timeout=35)
  html=result.stdout.decode('utf-8',errors='replace')
  png=root/('jump-repair-'+name+'.png')
  ok=result.returncode==0 and expected in html and png.exists()
  results.append({'state':name,'exit':result.returncode,'expected_text_present':expected in html,
   'screenshot_exists':png.exists(),'passed':ok,'html_sha256':hashlib.sha256(html.encode()).hexdigest()})
 except subprocess.TimeoutExpired:
  results.append({'state':name,'passed':False,'error':'Chrome process timeout'})
 report={'browser':'Google Chrome','executable':r'C:\Program Files\Google\Chrome\Application\chrome.exe',
 'scope':'Isolated authenticated Rails-rendered synthetic HTML snapshots, scripts removed and built Tailwind inlined; visual state only, no external client end-to-end claim.',
 'checks':results}
 (repo/'docs/discovery/jump_travel_repair_chrome.json').write_text(json.dumps(report,indent=2))
 print(json.dumps(results[-1]),flush=True)
