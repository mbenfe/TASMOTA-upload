import json, glob, collections
from pathlib import Path
p=max(glob.glob('C:/Users/benfe/AppData/Local/Temp/pwx_mqtt_audit_*.json'),key=lambda p:Path(p).stat().st_mtime)
r=json.loads(Path(p).read_text()); print('CAPTURE',p)
sites=collections.defaultdict(list)
for x in r: sites[x['topic'].split('/')[2]].append(x)
for site, rows in sorted(sites.items()):
    latest={}
    for x in rows:
        d=x['data']; name=d.get('Name','') if isinstance(d,dict) else ''; latest[(x['topic'],name)]=x
    powers=[x for x in latest.values() if x['topic'].endswith('/POWER')]
    offline=[x['topic'].split('/')[3] for x in latest.values() if x['topic'].endswith('/LWT') and str(x['data']).lower()!='online']
    bad=[x for x in latest.values() if isinstance(x['data'],dict) and (x['data'].get('missing_sources') or (x['topic'].endswith('VIRTUALSTATUS') and x['data'].get('reason')!='running'))]
    negative=[(x['topic'].split('/')[3],x['data']) for x in powers if isinstance(x['data'],dict) and isinstance(x['data'].get('ActivePower'),(int,float)) and x['data']['ActivePower']<0]
    cfg=Path('config')/('power_'+site+'.json')
    expected=json.loads(cfg.read_text(encoding='utf-8-sig')) if cfg.exists() else {}
    offpower=[d for d in offline if d in expected]
    print(json.dumps(dict(site=site,messages=len(rows),live=sum(not x['retained'] for x in rows),power_channels=len(powers),offline_power_devices=offpower,other_offline=offline,bad_virtual=bad,negative=negative)))
