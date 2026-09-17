import json, ssl, sys, time, uuid, tempfile
from pathlib import Path
from collections import Counter
import paho.mqtt.client as mqtt

credentials = json.loads(sys.stdin.readline())
client = mqtt.Client(client_id='pwx-audit-' + uuid.uuid4().hex[:12], protocol=mqtt.MQTTv311)
client.username_pw_set(credentials['username'], credentials['password'])
del credentials
client.tls_set(cert_reqs=ssl.CERT_REQUIRED, tls_version=ssl.PROTOCOL_TLS_CLIENT)
filters = [('gw/+/+/+/cmnd/PWXVREQUEST', 0),
           ('gw/+/+/+/cmnd/PWXVREPLY', 0),
           ('gw/+/+/+/tele/VIRTUALSTATUS', 0),
           ('gw/+/+/+/tele/POWER', 0),
           ('gw/+/+/dl12-fn-3/tele/PRINT', 0),
           ('gw/+/+/+/tele/LWT', 0)]
counts = Counter()
records = []
seen = {}
connected = False

def on_connect(c, userdata, flags, rc):
    global connected
    print('CONNECTION_RESULT', rc, flush=True)
    if rc == 0:
        connected = True
        c.subscribe(filters)

def on_subscribe(c, userdata, mid, granted):
    print('SUBSCRIPTION_RESULT', list(granted), flush=True)

def on_message(c, userdata, msg):
    topic = msg.topic
    payload = msg.payload.decode('utf-8', errors='replace')
    try:
        data = json.loads(payload)
    except (ValueError, TypeError):
        data = payload
    if False:
        return
    rec = {'received_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'topic': topic, 'retained': msg.retain, 'data': data}
    records.append(rec)
    kind = topic.rsplit('/', 1)[-1]
    source = data.get('source', '') if isinstance(data, dict) else ''
    name = data.get('name', '') if isinstance(data, dict) else ''
    counts[(kind, source, name, bool(msg.retain))] += 1
    key = (topic, name, source)
    if kind == 'VIRTUALSTATUS':
        print('OBSERVED', json.dumps(rec), flush=True)
    seen[key] = True

client.on_connect = on_connect
client.on_subscribe = on_subscribe
client.on_message = on_message
try:
    client.connect('mqtt.adomelec.fr', 8883, keepalive=30)
    deadline = time.monotonic() + 70
    tick = time.monotonic() + 15
    while time.monotonic() < deadline:
        rc = client.loop(timeout=1)
        if rc != mqtt.MQTT_ERR_SUCCESS:
            print('LOOP_ERROR', rc, flush=True)
            break
        if time.monotonic() >= tick:
            print('PROGRESS', len(records), 'relevant messages', flush=True)
            tick += 15
        if not connected and time.monotonic() > deadline - 55:
            break
finally:
    client.disconnect()
    path = Path(tempfile.gettempdir()) / ('pwx_mqtt_audit_' + time.strftime('%Y%m%d_%H%M%S') + '.json')
    path.write_text(json.dumps(records, indent=2), encoding='utf-8')
    print('CAPTURE_PATH', str(path), flush=True)
    print('COUNTS', json.dumps([{'kind': k[0], 'source': k[1], 'name': k[2], 'retained': k[3], 'count': v} for k,v in counts.items()]), flush=True)

