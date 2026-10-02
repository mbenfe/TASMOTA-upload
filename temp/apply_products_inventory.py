import json,re,copy,collections
from pathlib import Path
x=json.loads(Path('temp/products_field_audit.json').read_text());assert x['subscription_granted'] and not x['error']
allowed={'inter','benfeghoul','lambert','bauduin'}
added=[];pending=[];evidence=[]
for p in sorted(Path('config/produits').glob('produits_*.json')):
 city=p.stem.removeprefix('produits_');d=json.loads(p.read_text());before=copy.deepcopy(d)
 for r in x['records']:
  if r['city']!=city or r['tenant'] not in allowed:continue
  name=r['device'];family=None
  status=any(k in r['kinds'] for k in ('LWT','HEARTBEAT','INFO1'))
  sensor='SENSOR' in r['kinds'] and name in r['payload_devices']
  if not(status or sensor):continue
  if re.match(r'^(aex|rdx|msx|plugx|acwfx|htchx)(?:[-_]|$)',name,re.I):family=re.split('[-_]',name)[0].lower()
  elif name.startswith('chxp-'):family='chx-p'
  elif name.startswith('chx-'):family='chx'
  elif name.startswith(('zb-bridge','zb-znp')) and status:family='zigbee'
  elif re.match(r'^ch\d',name):pending.append((city,name,'Heating family CHX/CHX-P pending user decision'));continue
  if not family:continue
  if r['payload_devices'] and name not in r['payload_devices']:
   pending.append((city,name,'Topic differs from payload Device: '+', '.join(r['payload_devices'])));continue
  if name not in d.get(family,{}):
   d.setdefault(family,{})[name]={};added.append((city,family,name))
  evidence.append(dict(city=city,family=family,device=name,tenant=r['tenant'],retained=r['retained'],live=r['live'],lwt=r.get('lwt'),kinds=r['kinds']))
 if d!=before:p.write_text(json.dumps(d,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
 saved=json.loads(p.read_text());assert saved['pwx']==before['pwx'];assert saved.get('snx')==before.get('snx');assert all(v=={} for f in saved.values() for v in f.values())
# Prefix-based layout candidates only: never infer controller from generic relay or pipe names.
for file,names in x['layouts'].items():
 city=re.sub(r'^(mobile|web)_','',file).removesuffix('.json');p=Path('config/produits/produits_'+city+'.json')
 d=json.loads(p.read_text()) if p.exists() else {}
 known={n for f in d.values() for n in f}
 for name in names:
  if re.match(r'^(aex-|rdx-|hitachi_|chxp-|chx-|ch\d|plugx-|relay\d|switch_)',name,re.I) and name not in known:
   pending.append((city,name,'Layout reference: '+file))
Path('temp/products_inventory_evidence.json').write_text(json.dumps(dict(capture_utc=x['checked_utc'],added=added,evidence=evidence,pending=sorted(set(pending))),indent=2))
lines=['# Other product inventory audit','', 'Capture UTC: '+x['checked_utc']+'. Subscription-only capture, 40 seconds; no MQTT publication.','', 'Existing PWX and SNX entries preserved. All added values are empty objects. Other namespaces included only for the named residential cities; demo/invite/labo excluded. Gateway and controller identities preferred over channels.','', '| City | Family | Device | Tenant | Retained messages | Fresh messages | Retained LWT |','| --- | --- | --- | --- | ---: | ---: | --- |']
for r in evidence:lines.append('| '+ ' | '.join(str(r[k] if r[k] is not None else '-') for k in ('city','family','device','tenant','retained','live','lwt'))+' |')
lines+=['','## Pending candidates','', '| City | Name | Reason |','| --- | --- | --- |']
for row in sorted(set(pending)):lines.append('| '+' | '.join(row)+' |')
lines+=['','Zigbee sensors and numeric/hex-address sensor topics are pending classification and user choice. Saint-Maur relay1..7 and Chilly-Mazarin hitachi_* are layout endpoint names with no demonstrated physical controller mapping. Web generic names such as aerotherm1, chauffage1 and rideau1 may be placeholders; not added.','', 'No observation is not proof of absence. Retained status may be stale, and fresh topic traffic does not prove a direct physical publisher. Unsupported/unobserved families are not added as empty sections. Evidence snapshot: temp/products_inventory_evidence.json; raw identity metadata: temp/products_field_audit.json.']
Path('config/produits/PRODUCTS_AUDIT.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('Added',len(added),'identities');print('Families',dict(collections.Counter(f for _,f,_ in added)));print('Pending',len(set(pending)))