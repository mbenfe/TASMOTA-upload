"""Subscribe only to pilot status; read JSON credentials from stdin, never print them."""
import json
import ssl
import sys
import time
import uuid
import paho.mqtt.client as mqtt

credentials = json.loads(sys.stdin.readline())
client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2,
                     client_id='egly-audit-' + uuid.uuid4().hex[:12])
client.username_pw_set(credentials['username'], credentials['password'])
del credentials
client.tls_set_context(ssl.create_default_context())
filters = [f'gw/+/egly/pwx12-tgbtint1/tele/{kind}'
           for kind in ['LWT', 'HEARTBEAT', 'INFO1', 'INFO_STM32']]
filters += ['gw/+/egly/pwx12-tgbtint1/stat/STATUS2']
seen = set()
connected = False

def on_connect(c, userdata, flags, reason, properties):
    global connected
    connected = not reason.is_failure
    print('MQTT connected:', connected, flush=True)
    if connected:
        c.subscribe([(topic, 0) for topic in filters])

def on_message(c, userdata, message):
    # Do not subscribe to PRINT, commands or configuration containing secrets.
    topic = message.topic
    seen.add(topic)
    result = {'topic': topic, 'retained': message.retain}
    try:
        payload = json.loads(message.payload)
        def versions(value):
            if not isinstance(value, dict):
                return {}
            safe = {}
            for key, item in value.items():
                if key.lower() in ['version', 'hardware', 'core', 'sdk', 'uptime'] and isinstance(item, (str, int, float)):
                    safe[key] = item
                elif isinstance(item, dict):
                    child = versions(item)
                    if child:
                        safe[key] = child
            return safe
        result['version_status'] = versions(payload)
    except (ValueError, UnicodeError):
        if message.payload in [b'Online', b'Offline']:
            result['state'] = message.payload.decode()
    print(json.dumps(result), flush=True)

client.on_connect = on_connect
client.on_message = on_message
try:
    client.connect('mqtt.adomelec.fr', 8883, keepalive=30)
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        if client.loop(timeout=1) != mqtt.MQTT_ERR_SUCCESS:
            break
finally:
    client.disconnect()
print('Observed status topics:', len(seen))
print('Read-only: no MQTT messages published; no device files changed.')
