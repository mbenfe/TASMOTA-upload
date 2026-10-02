import json,re,ssl,time,uuid,datetime,collections
from pathlib import Path
from dotenv import dotenv_values
import paho.mqtt.client as mqtt
layouts={}
def walk(x):
    if isinstance(x,dict):
        for k,v in x.items():
            if k in ('master','slave','device','devices'):
                for s in v if isinstance(v,list) else [v]:
                    if isinstance(s,str) and re.match(r'^snx(?:[-_]|$)',s,re.I): yield s
            yield from walk(v)
    elif isinstance(x,list):
        for v in x: yield from walk(v)
for p in sorted(Path('config').glob('*.json')):
    if not p.name.startswith(('mobile_','web_')): continue
    try: names=sorted(set(walk(json.loads(p.read_text(encoding='utf-8-sig')))))
    except Exception: continue
    if names: layouts[p.name]=names
records={}; subscribed=False
cfg=dotenv_values('D:/Programming/python/PYTHON-mqtt-logger/.secrets')
c=mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,client_id='snx-readonly-'+uuid.uuid4().hex[:10])
c.username_pw_set(cfg['MQTT_USERNAME'],cfg['MQTT_PASSWORD'])
tls=ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT);tls.load_default_certs();c.tls_set_context(tls)
broker,port=cfg['MQTT_BROKER'],int(cfg['MQTT_PORT']);del cfg
filters=[('gw/+/+/+/tele/'+s,0) for s in ('LWT','HEARTBEAT','REGULATEUR','STATISTIC','SNXDETAILS','INFO1')]
def connect(c,u,f,r,p):
    if r.is_failure: raise RuntimeError('MQTT authentication rejected')
    c.subscribe(filters)
def sub(c,u,m,r,p):
    global subscribed
    subscribed=all(not x.is_failure for x in r)
def message(c,u,m):
    ps=m.topic.split('/')
    if len(ps)<6:return
    tenant,city,device,_,kind=ps[1:6]
    if not re.match(r'^snx(?:[-_]|$)',device,re.I) and kind not in ('REGULATEUR','STATISTIC','SNXDETAILS'):return
    key=(tenant,city,device)
    row=records.setdefault(key,dict(tenant=tenant,city=city,device=device,kinds=set(),retained=0,live=0,payload_devices=set(),names=set()))
    row['kinds'].add(kind);row['retained' if m.retain else 'live']+=1
    if kind=='LWT' and m.payload in (b'Online',b'Offline'):row['lwt']=m.payload.decode()
    try: data=json.loads(m.payload)
    except Exception:return
    if isinstance(data,dict):
        for field,target in [('Device','payload_devices'),('Name','names')]:
            if isinstance(data.get(field),str):row[target].add(data[field])
c.on_connect=connect;c.on_subscribe=sub;c.on_message=message
error=None
try:
    c.connect(broker,port,30)
    deadline=time.monotonic()+40
    while time.monotonic()<deadline:
        if c.loop(timeout=1)!=mqtt.MQTT_ERR_SUCCESS:raise RuntimeError('MQTT loop failed')
except Exception as e:error=type(e).__name__+': '+str(e)
finally:c.disconnect()
for r in records.values():
    for k in ('kinds','payload_devices','names'):r[k]=sorted(r[k])
result=dict(checked_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),duration_seconds=40,subscription_granted=subscribed,error=error,layouts=layouts,records=sorted(records.values(),key=lambda r:(r['city'],r['device'])))
Path('temp/snx_field_audit.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('LAYOUT SNX REFERENCES',json.dumps(layouts));print('MQTT',subscribed,'ERROR',error)
for r in result['records']:print(json.dumps(r))