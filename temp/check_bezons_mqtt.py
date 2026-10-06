import json,ssl,time,uuid
from pathlib import Path
from collections import Counter
from dotenv import dotenv_values
import paho.mqtt.client as mqtt
cfg=dotenv_values('D:/Programming/python/PYTHON-mqtt-logger/.secrets')
c=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='readonly-bezons-'+uuid.uuid4().hex[:10])
c.username_pw_set(cfg['MQTT_USERNAME'],cfg['MQTT_PASSWORD'])
del cfg
tls=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT); tls.load_default_certs(); c.tls_set_context(tls)
records=[]
def connected(c,u,f,r,p):
 print('CONNECTED',str(r),flush=True)
 if not r.is_failure: c.subscribe('gw/inter/bezons/#',qos=1)
def subscribed(c,u,m,r,p): print('SUBSCRIBED',[str(x) for x in r],flush=True)
def message(c,u,m):
 raw=m.payload.decode('utf-8',errors='replace')
 try: data=json.loads(raw)
 except ValueError: data=raw
 records.append(dict(utc=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),topic=m.topic,retained=m.retain,data=data))
c.on_connect=connected;c.on_subscribe=subscribed;c.on_message=message
try:
 c.connect('mqtt.adomelec.fr',8883,30)
 end=time.monotonic()+60
 while time.monotonic()<end:
  rc=c.loop(timeout=1)
  if rc!=mqtt.MQTT_ERR_SUCCESS: print('LOOP_ERROR',rc);break
finally:
 c.disconnect()
p=Path('temp/bezons_mqtt_capture_20261006.json');p.write_text(json.dumps(records,indent=2),encoding='utf-8')
counts=Counter((x['topic'].split('/')[-1],x['retained']) for x in records)
print('COUNTS',json.dumps([dict(kind=k[0],retained=k[1],count=v) for k,v in counts.items()]))
w=json.loads(Path('config/web_bezons.json').read_text(encoding='utf-8-sig'))['applications'][0]['data']['Froid']
expected={x['master'] for x in w}
for retained in [True,False]:
 seen={x['data'].get('Name') for x in records if x['retained']==retained and isinstance(x['data'],dict) and x['topic'].endswith('/REGULATEUR')}
 print('REGULATEUR', 'RETAINED' if retained else 'LIVE', 'matched',len(expected&seen),'names',sorted(seen))
print('SAVED',p,'MESSAGES',len(records))
