import collections
import datetime
import hashlib
import json
import re
import ssl
import time
import uuid
from pathlib import Path
from dotenv import dotenv_values
import paho.mqtt.client as mqtt

inventory = {}
channels = {}
snapshots = {}
for path in sorted(Path('config/produits').glob('produits_*.json')):
    site = path.stem.removeprefix('produits_')
    data = json.loads(path.read_text(encoding='utf-8-sig'))
    snapshots[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    inventory[site] = {}
    channels[site] = set()
    for category, entries in data.items():
        if not isinstance(entries, dict):
            continue
        for device, entry in entries.items():
            inventory[site][device] = category
            if isinstance(entry, dict):
                for ch in entry.get('channels', [entry['channel']] if 'channel' in entry else []):
                    if ch.get('name') not in (None, '', '*'):
                        channels[site].add(ch['name'])

cfg = dotenv_values('D:/Programming/python/PYTHON-mqtt-logger/.secrets')
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='produits-audit-' + uuid.uuid4().hex[:12])
client.username_pw_set(cfg['MQTT_USERNAME'], cfg['MQTT_PASSWORD'])
tls = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
tls.load_default_certs()
client.tls_set_context(tls)
broker, port = cfg['MQTT_BROKER'], int(cfg['MQTT_PORT'])
del cfg
records = {}
start = datetime.datetime.now(datetime.timezone.utc).isoformat()
subscribed = False

def on_connect(c, userdata, flags, reason, properties):
    print('AUTHENTICATED', not reason.is_failure, flush=True)
    if not reason.is_failure:
        c.subscribe([('gw/+/+/+/tele/#', 0), ('gw/+/+/+/stat/#', 0)])

def on_subscribe(c, userdata, mid, reasons, properties):
    global subscribed
    subscribed = all(not r.is_failure for r in reasons)
    print('SUBSCRIBED', subscribed, flush=True)

def on_message(c, userdata, msg):
    parts = msg.topic.split('/')
    if len(parts) < 6:
        return
    tenant, site, device, direction, kind = parts[1:6]
    key = (tenant, site, device)
    row = records.setdefault(key, {'tenant':tenant, 'site':site, 'device':device,
        'retained_messages':0, 'live_messages':0, 'kinds':set(), 'device_evidence':False})
    row['retained_messages' if msg.retain else 'live_messages'] += 1
    row['kinds'].add(kind)
    if kind in ('LWT','HEARTBEAT','INFO1','INFO2','INFO3','STATUS2','STATUS5'):
        row['device_evidence'] = True
    # Never retain message bodies, PRINT output, credentials or configuration.
    if kind == 'LWT' and msg.payload in (b'Online', b'Offline'):
        row['lwt'] = msg.payload.decode()
        row['lwt_retained'] = bool(msg.retain)

client.on_connect = on_connect
client.on_subscribe = on_subscribe
client.on_message = on_message
try:
    client.connect(broker, port, 30)
    deadline = time.monotonic() + 90
    progress = time.monotonic() + 30
    while time.monotonic() < deadline:
        rc = client.loop(timeout=1)
        if rc != mqtt.MQTT_ERR_SUCCESS:
            raise RuntimeError('MQTT loop failed')
        if time.monotonic() >= progress:
            print('PROGRESS unique topic identities:', len(records), flush=True)
            progress += 30
finally:
    client.disconnect()
if not subscribed:
    raise RuntimeError('Subscription not confirmed')

for row in records.values():
    site, name = row['site'], row['device']
    row['kinds'] = sorted(row['kinds'])
    if site not in inventory:
        row['classification'] = 'no_site_inventory'
    elif name in inventory[site]:
        row['classification'] = 'defined'
    else:
        match = re.fullmatch(r'(.+)-(\d+)', name)
        if match and match[1] in inventory[site] and not row['device_evidence']:
            row['classification'] = 'derived_channel_topic'
            row['parent_device'] = match[1]
        elif name in channels[site] and not row['device_evidence']:
            row['classification'] = 'electrical_node_topic'
        else:
            row['classification'] = 'missing_device' if row['device_evidence'] else 'unresolved_topic_identity'
result = {'started_utc':start, 'duration_seconds':90, 'inventory_hashes':snapshots,
          'records':sorted(records.values(), key=lambda r:(r['site'],r['tenant'],r['device']))}
for path, digest in snapshots.items():
    assert hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest, 'Inventory changed during capture'
Path('temp/mqtt_produits_audit.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
summary = collections.Counter(r['classification'] for r in records.values())
print('SUMMARY', json.dumps(summary), flush=True)
for site in sorted({r['site'] for r in records.values()}):
    rows = [r for r in records.values() if r['site']==site and r['classification'] in ('missing_device','no_site_inventory','unresolved_topic_identity')]
    if rows:
        print(site, json.dumps([{k:r[k] for k in ('tenant','device','classification','live_messages','device_evidence')} for r in rows]), flush=True)
