import json, ssl, time, uuid, re
from pathlib import Path
from collections import Counter
from datetime import datetime, timezone
from dotenv import dotenv_values
import paho.mqtt.client as mqtt
source=Path('D:/Programming/embedded/STM32/Groupe SNX/auto_champigny/Core/Src/generated_registers.cpp').read_text(encoding='utf-8-sig')
expected={int(i):dict(ID=int(i),category=g,Name=n) for i,g,n in re.findall(r'^\s*\{(\d+), \{"(vitrine[+-]|bac[+-]|CF[+-]|condenseur)", "([^"]+)"',source,re.M)}
cfg=dotenv_values('D:/Programming/python/PYTHON-mqtt-logger/.secrets')
c=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='readonly-champigny-'+uuid.uuid4().hex[:10])
c.username_pw_set(cfg['MQTT_USERNAME'],cfg['MQTT_PASSWORD']);del cfg
ctx=ssl.create_default_context();c.tls_set_context(ctx)
records=[]
def connected(c,u,f,r,p):
 print('CONNECTED',str(r),flush=True)
 if not r.is_failure:c.subscribe('gw/inter/champigny/#',qos=1)
def subscribed(c,u,m,r,p):print('SUBSCRIBED',[str(x) for x in r],flush=True)
def message(c,u,m):
 raw=m.payload.decode('utf-8',errors='replace')
 try:data=json.loads(raw)
 except ValueError:data=raw
 records.append(dict(utc=datetime.now(timezone.utc).isoformat(),topic=m.topic,retained=m.retain,data=data))
c.on_connect=connected;c.on_subscribe=subscribed;c.on_message=message
start=datetime.now(timezone.utc).isoformat()
try:
 c.connect('mqtt.adomelec.fr',8883,30)
 end=time.monotonic()+120
 while time.monotonic()<end:
  rc=c.loop(timeout=1)
  if rc!=mqtt.MQTT_ERR_SUCCESS:print('LOOP_ERROR',rc,flush=True);break
finally:c.disconnect()
out=dict(start_utc=start,end_utc=datetime.now(timezone.utc).isoformat(),broker='mqtt.adomelec.fr:8883',subscription='gw/inter/champigny/#',expected=list(expected.values()),records=records)
p=Path('temp/champigny_mqtt_capture_20261007.json');p.write_text(json.dumps(out,indent=2,ensure_ascii=False),encoding='utf-8')
print('SAVED',str(p),'MESSAGES',len(records),flush=True)
print('COUNTS',json.dumps(dict(Counter(x['topic'].split('/')[-1]+(' retained' if x['retained'] else ' fresh') for x in records))),flush=True)
for kind in ['REGULATEUR','SNXDETAILS','STATISTIC','LWT','STATE']:
 rr=[x for x in records if x['topic'].endswith('/'+kind)]
 if rr:
  print('SAMPLE',kind,json.dumps(rr[0],ensure_ascii=False),flush=True)
fresh=[x for x in records if not x['retained'] and x['topic'].endswith('/REGULATEUR') and isinstance(x['data'],dict)]
seen={}
for x in fresh:
 d=x['data']; key=(d.get('ID'),d.get('Name'));seen[key]=dict(data=d,topic=x['topic'],received_utc=x['utc'],count=1+seen.get(key,{}).get('count',0))
print('FRESH_UNITS',json.dumps(list(seen.values()),ensure_ascii=False),flush=True)
