import json
from pathlib import Path
from collections import Counter
from datetime import datetime
from zoneinfo import ZoneInfo
p=json.loads(Path('temp/champigny_mqtt_capture_10min_20261007.json').read_text(encoding='utf-8'))
r=p['records'];expected=p['expected'];byid={x['ID']:x for x in expected}
kinds={'REGULATEUR','REGULATEUR_LOG','CONDENSEUR','CONDENSEUR_LOG'}
def valid(z):
 d=z['data'];e=byid.get(d.get('ID'))
 return e and d.get('Name')==e['Name'] and d.get('genre')==e['category']
rows=[z for z in r if not z['retained'] and z['topic'].split('/')[-1] in kinds and isinstance(z['data'],dict)]
bad=[z for z in rows if not valid(z)]; good=[z for z in rows if valid(z)]
lines=['# Champigny SNX - 10-minute MQTT observation','', 'Start: '+p['start_utc']+'; end: '+p['end_utc']+'.','Read-only mqtt.adomelec.fr:8883 TLS, gw/inter/champigny/#, QoS 1. No publications.','Compared to local auto_champigny/Core/Src/generated_registers.cpp kConfigFroidData.','', '| Category | STM32 | Fresh | Normal telemetry | LOG only | Retained only | Absent |','|---|---:|---:|---:|---:|---:|---:|']
statuses={}
for e in expected:
 hits=[z for z in good if z['data']['ID']==e['ID']]
 normal=[z for z in hits if z['topic'].split('/')[-1] in {'REGULATEUR','CONDENSEUR'}]
 retained=[z for z in r if z['retained'] and z['topic'].split('/')[-1] in kinds and isinstance(z['data'],dict) and z['data'].get('ID')==e['ID'] and valid(z)]
 statuses[e['ID']]=dict(status='normal' if normal else 'log_only' if hits else 'retained_only' if retained else 'absent',messages=len(hits),normal=len(normal),first=hits[0]['utc'] if hits else '-',last=hits[-1]['utc'] if hits else '-',retained=len(retained))
for g in ['vitrine+','bac+','CF+','vitrine-','bac-','CF-','condenseur']:
 es=[e for e in expected if e['category']==g];c=Counter(statuses[e['ID']]['status'] for e in es)
 lines.append(f"| {g} | {len(es)} | {c['normal']+c['log_only']} | {c['normal']} | {c['log_only']} | {c['retained_only']} | {c['absent']} |")
for g in ['vitrine+','bac+','CF+','vitrine-','bac-','CF-','condenseur']:
 lines+=['','## '+g,'','| ID | Exact Name | Status | Fresh messages | Normal messages | First UTC | Last UTC |','|---:|---|---|---:|---:|---|---|']
 for e in sorted([e for e in expected if e['category']==g],key=lambda e:e['ID']):
  s=statuses[e['ID']];lines.append(f"| {e['ID']} | `{e['Name']}` | {s['status']} | {s['messages']} | {s['normal']} | {s['first']} | {s['last']} |")
errors=[z for z in r if z['topic'].endswith('/SNX_RX_ERROR') and not z['retained']]
lines+=['','## Exceptions','',f'Fresh identity/category mismatches: {len(bad)}.',f'Fresh SNX_RX_ERROR: {len(errors)}.']
for z in bad+errors:lines+=['','```json',json.dumps(z,ensure_ascii=False),'```']
weird=[z for z in good if z['data']['ID']==18 and z['topic'].endswith('/REGULATEUR')]
lines+=['','## CfSurgReception_18','',f'Fresh normal messages: {len(weird)}.']
if weird:
 lines+=['Latest payload:','```json',json.dumps(weird[-1],ensure_ascii=False),'```']
lines+=['','Only live MQTT and local STM32 source were checked. Firmware flashed on devices and physical equipment were not checked. Missing traffic within this window does not prove a device is offline.']
Path('temp/champigny_snx_inventory_10min_20261007.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('WINDOW',p['start_utc'],p['end_utc'],'MESSAGES',len(r));print('\n'.join(lines[6:15]))
print('STATUS',json.dumps({str(e['ID']):dict(Name=e['Name'],**statuses[e['ID']]) for e in expected if statuses[e['ID']]['status']!='normal'},ensure_ascii=False))
print('BAD_COUNT',len(bad),'ERROR_COUNT',len(errors));print('BAD',json.dumps(bad,ensure_ascii=False));print('ERRORS',json.dumps(errors,ensure_ascii=False))
print('CF18',json.dumps([z['data'] for z in weird],ensure_ascii=False))
print('ALL_TOPIC_COUNTS',json.dumps(dict(Counter(z['topic'].split('/')[-1]+(' retained' if z['retained'] else ' fresh') for z in r))))
