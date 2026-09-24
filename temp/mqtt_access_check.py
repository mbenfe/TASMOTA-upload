import collections
import json
import ssl
import time
import uuid
from pathlib import Path
from dotenv import dotenv_values
import paho.mqtt.client as mqtt

cfg = dotenv_values('D:/Programming/python/PYTHON-mqtt-logger/.secrets')
broker = cfg['MQTT_BROKER']
port = int(cfg['MQTT_PORT'])
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id='readonly-audit-' + uuid.uuid4().hex[:12])
client.username_pw_set(cfg['MQTT_USERNAME'], cfg['MQTT_PASSWORD'])
if port != 8883:
    raise SystemExit('Configured port is not 8883; TLS settings need review before connecting.')
# Use conventional chain/hostname verification. Python 3.13+ default strict
# X.509 parsing rejects a locally installed CA's noncritical Basic Constraints.
# Certificate trust and hostname verification remain mandatory.
tls = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
tls.load_default_certs()
assert tls.verify_mode == ssl.CERT_REQUIRED and tls.check_hostname
client.tls_set_context(tls)
del cfg
counts = collections.Counter()
devices = {}
authenticated = False
subscribed = False

def on_connect(c, userdata, flags, reason, properties):
    global authenticated
    authenticated = not reason.is_failure
    print('AUTHENTICATED', authenticated, flush=True)
    if authenticated:
        c.subscribe([('gw/+/+/+/tele/LWT', 0), ('gw/+/+/+/tele/HEARTBEAT', 0)])

def on_subscribe(c, userdata, mid, reasons, properties):
    global subscribed
    subscribed = all(not r.is_failure for r in reasons)
    print('SUBSCRIPTION_GRANTED', subscribed, flush=True)

def on_message(c, userdata, msg):
    parts = msg.topic.split('/')
    if len(parts) != 6 or not parts[3].lower().startswith(('dl4-', 'dl12-', 'pwx4-', 'pwx12-')):
        return
    key = '/'.join(parts[1:4])
    record = devices.setdefault(key, {'topic_base': '/'.join(parts[:4]), 'live_heartbeat': False})
    counts[parts[-1]] += 1
    if parts[-1] == 'HEARTBEAT' and not msg.retain:
        record['live_heartbeat'] = True
    if parts[-1] == 'LWT' and msg.payload in [b'Online', b'Offline']:
        record['lwt'] = msg.payload.decode()
        record['lwt_retained'] = msg.retain

client.on_connect = on_connect
client.on_subscribe = on_subscribe
client.on_message = on_message
try:
    client.connect(broker, port, 30)
    deadline = time.monotonic() + 40
    while time.monotonic() < deadline:
        if client.loop(timeout=1) != mqtt.MQTT_ERR_SUCCESS:
            break
except Exception as exc:
    print('CONNECTION_ERROR', type(exc).__name__, getattr(exc, 'errno', None), flush=True)
    if isinstance(exc, ssl.SSLCertVerificationError):
        print('TLS verification:', exc.verify_message, flush=True)
    raise SystemExit(1)
finally:
    client.disconnect()
result = {'authenticated': authenticated, 'subscription_granted': subscribed,
          'message_counts': dict(counts), 'devices': devices}
Path('temp/mqtt_access_result.json').write_text(json.dumps(result, indent=2))
print('PWX_DL_DEVICES_OBSERVED', len(devices))
print('LIVE_HEARTBEATS', sum(v['live_heartbeat'] for v in devices.values()))
print('EGLY', json.dumps({k:v for k,v in devices.items() if '/egly/' in k}))
print('No MQTT messages published; no device changes.')
