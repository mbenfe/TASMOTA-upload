from pathlib import Path
import hashlib
import json
import tempfile

ROOT = Path('D:/Programming/Tasmota/TASMOTA-Tasmota-15.2.0/Tasmota')
HERE = Path(__file__).parent
block = (HERE / 'pwx_push_block.txt').read_text(encoding='utf-8')
changes = {}
for number, name in [(129,'pwx12new'), (130,'pwx12legacy'), (131,'pwx4legacy'), (132,'pwx4new'), (136,'pwx4rogowski')]:
    path = ROOT / f'tasmota/tasmota_xdrv_driver/xdrv_{number}_{name}.ino'
    raw = path.read_bytes()
    text = raw.decode('utf-8').replace('\r\n', '\n')
    assert 'BEGIN PWX WEBDAV PUSH' not in text
    marker = f'bool Xdrv{number}(uint32_t function) {{'
    assert text.count(marker) == 1
    head, tail = text.split(marker)
    assert tail.count('case FUNC_COMMAND:') == 1
    assert tail.count('case FUNC_LOOP:') == 1
    tail = tail.replace('case FUNC_COMMAND:', '''case FUNC_COMMAND:
      if (XdrvMailbox.command && !strcasecmp(XdrvMailbox.command, "Push")) {
        PwxPush::Command(); result = true; break;
      }''', 1)
    tail = tail.replace('case FUNC_LOOP:', 'case FUNC_LOOP:\n      PwxPush::Poll();', 1)
    updated = head + block + '\n' + marker + tail
    newline = '\r\n' if b'\r\n' in raw else '\n'
    changes[path] = (raw, updated.replace('\n', newline).encode('utf-8'))

path = ROOT / 'tasmota/my_user_config.h'
raw = path.read_bytes()
text = raw.decode('utf-8').replace('\r\n', '\n')
marker = '#ifdef USE_CONFIG_OVERRIDE\n'
assert text.count(marker) == 1 and 'PWX_PUSH_URL' not in text
config = '''// Native PWX filesystem backup over HTTPS WebDAV (all five PWX families).
// Synology account must match the ACTIVE MQTT username/password.
// Set the existing NAS shared-folder URL and verified RSA public-key pin below.
// No NAS/MQTT password belongs in this block or public Berry scripts.
#define USE_PWX_WEBDAV_PUSH
#define PWX_PUSH_URL "https://malek4b.synology.me:5006/"  // Append /<shared-folder>
#define PWX_PUSH_TLS_PIN ""   // Required: NAS RSA public-key SHA1 (40 hex digits)
#define PWX_PUSH_TLS_PIN2 ""  // Optional second verified key during rotation
#define PWX_PUSH_FILE_TIMEOUT_MS 300000UL

'''
text = text.replace(marker, config + marker)
changes[path] = (raw, text.replace('\n', '\r\n' if b'\r\n' in raw else '\n').encode('utf-8'))

path = ROOT / 'info/pwx_push.md'
assert not path.exists()
changes[path] = (None, (HERE / 'pwx_push_documentation.md').read_bytes())

# Stage all transformations before touching the checkout; preserve existing edits.
backup = Path(tempfile.mkdtemp(prefix='pwx_push_before_'))
backup.mkdir(exist_ok=True)
manifest = {}
for path, (before, after) in changes.items():
    relative = str(path.relative_to(ROOT)).replace('\\', '/')
    if before is not None:
        target = backup / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        assert not target.exists(), 'Backup already exists; do not overwrite it'
        target.write_bytes(before)
    manifest[relative] = {'before': hashlib.sha256(before).hexdigest() if before is not None else None,
                          'after': hashlib.sha256(after).hexdigest()}
for path, (before, after) in changes.items():
    assert (path.read_bytes() if path.exists() else None) == before, 'Concurrent edit: ' + str(path)
    path.write_bytes(after)
(backup / 'manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
print('Installed Push in five drivers, compilation settings and info/pwx_push.md. No credentials read or printed.')
