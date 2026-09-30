from pathlib import Path
import sys,json,re

root=Path('D:/Programming/Tasmota/TASMOTA-Tasmota-15.2.0/Tasmota')
password=sys.stdin.readline().strip()
assert password
changes={}
for number,name in [(129,'pwx12new'),(130,'pwx12legacy'),(131,'pwx4legacy'),(132,'pwx4new'),(136,'pwx4rogowski')]:
    p=root/f'tasmota/tasmota_xdrv_driver/xdrv_{number}_{name}.ino'
    raw=p.read_bytes(); s=raw.decode('utf-8')
    old='!SettingsText(SET_MQTT_USER)[0] || !SettingsText(SET_MQTT_PWD)[0]'
    assert s.count(old)==1
    s=s.replace(old,'!PWX_PUSH_USER[0] || !PWX_PUSH_PASSWORD[0]')
    s=s.replace('MQTT credentials missing','WebDAV credentials missing in my_user_config.h')
    s=s.replace('job->user = SettingsText(SET_MQTT_USER); job->password = SettingsText(SET_MQTT_PWD);','job->user = PWX_PUSH_USER; job->password = PWX_PUSH_PASSWORD;')
    changes[p]=(raw,s.encode('utf-8'))
p=root/'tasmota/my_user_config.h'
raw=p.read_bytes(); s=raw.decode('utf-8'); nl='\r\n' if '\r\n' in s else '\n'
assert 'PWX_PUSH_PASSWORD' not in s
marker='#define USE_PWX_WEBDAV_PUSH'
assert s.count(marker)==1
s=s.replace(marker,marker+nl+'#define PWX_PUSH_USER "tasmota"'+nl+'#define PWX_PUSH_PASSWORD '+json.dumps(password))
s=s.replace('// Synology account must match the ACTIVE MQTT username/password.','// Dedicated Synology WebDAV credentials; independent of MQTT.')
s=s.replace('// No NAS/MQTT password belongs in this block or public Berry scripts.','// Keep this credential-bearing header and Tasmota firmware private; no secrets in Berry.')
s=re.sub(r'^#define PWX_PUSH_URL[^\r\n]*','#define PWX_PUSH_URL "https://malek4b.synology.me:5006/webdav/tasmotafs"',s,flags=re.M)
changes[p]=(raw,s.encode('utf-8'))
p=root/'info/pwx_push.md'; raw=p.read_bytes(); s=raw.decode('utf-8')
start=s.index('Credentials are copied'); end=s.index('\nTLS uses',start)
s=s[:start]+'''Credentials are compiled from `PWX_PUSH_USER` and `PWX_PUSH_PASSWORD` in
`my_user_config.h`, independently of MQTT. All five drivers use the same
parameters. No credential getter exposes them to Berry and this feature does
not log credential values. Keep the header and compiled Tasmota firmware
private. Synology must have the matching account with WebDAV read/write access
to `webdav/tasmotafs`. The configured URL points to that folder.
'''+s[end:]
s=s.replace('  The checked-in default is deliberately incomplete: set the actual folder.','  The current destination is `/webdav/tasmotafs`.')
changes[p]=(raw,s.encode('utf-8'))
for p,(before,after) in changes.items():
    assert p.read_bytes()==before
    p.write_bytes(after)
print('Updated five drivers, dedicated WebDAV credentials, destination URL and documentation. MQTT settings unchanged.')
