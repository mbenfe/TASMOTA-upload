import json, ssl, sys, time, uuid
from pathlib import Path
import paho.mqtt.client as mqtt

mode = sys.argv[1]
credentials = json.loads(sys.stdin.readline())
targets = []
excluded = []
for path in sorted(Path('config').glob('power_*.json')):
    site = path.stem.removeprefix('power_')
    for device, cfg in json.loads(path.read_text(encoding='utf-8-sig')).items():
        if not isinstance(cfg, dict):
            continue
        if str(cfg.get('produit', '')).lower() in ('virtuel', 'virtual') or device.lower().startswith(('virtuel', 'virtual')):
            excluded.append([site, device])
        else:
            targets.append((site, device))
client = mqtt.Client(client_id='couts-batch-' + uuid.uuid4().hex[:12], protocol=mqtt.MQTTv311)
client.username_pw_set(credentials['username'], credentials['password'])
client.tls_set(cert_reqs=ssl.CERT_REQUIRED)
seen = {}
responses = set()
connected = False
publishing = False
def on_connect(c, u, f, rc):
    global connected
    connected = rc == 0
    print('CONNECTION', rc, flush=True)
    if connected:
        c.subscribe('gw/#')
def on_message(c, u, msg):
    parts = msg.topic.split('/')
    if len(parts) != 6:
        return
    _, customer, site, device, prefix, command = parts
    if (site, device) in targets:
        seen.setdefault(site + '/' + device, set()).add(customer)
        if publishing and not msg.retain and prefix in ('stat', 'tele') and command.upper() in ('RESULT', 'COUTS'):
            responses.add(site + '/' + device)
client.on_connect = on_connect
client.on_message = on_message
client.connect('mqtt.adomelec.fr', 8883, 30)
client.loop_start()
try:
    time.sleep(12)
    if not connected:
        raise RuntimeError('MQTT connection failed')
    if mode == 'discover':
        result = {'targets': targets, 'excluded': excluded, 'observed': {k: sorted(v) for k,v in seen.items()}}
        Path('temp/couts_discovery.json').write_text(json.dumps(result, indent=2))
        print(json.dumps(result), flush=True)
    else:
        plan = json.loads(Path('temp/couts_plan.json').read_text())
        publishing = True
        sent = []
        for topic in plan:
            info = client.publish(topic, payload=b'', qos=0, retain=True)
            info.wait_for_publish(timeout=10)
            if not info.is_published():
                raise RuntimeError('Publish failed: ' + topic)
            sent.append(topic)
            Path('temp/couts_sent.json').write_text(json.dumps(sent, indent=2))
            time.sleep(0.1)
        time.sleep(15)
        report = {'sent': sent, 'responses': sorted(responses), 'excluded': excluded}
        Path('temp/couts_report.json').write_text(json.dumps(report, indent=2))
        print(json.dumps({'published': len(sent), 'reply_devices': len(responses), 'excluded': len(excluded)}), flush=True)
finally:
    client.disconnect()
    client.loop_stop()
