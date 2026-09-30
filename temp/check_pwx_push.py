from pathlib import Path
import subprocess,re,json,hashlib
r=Path('D:/Programming/Tasmota/TASMOTA-Tasmota-15.2.0/Tasmota')
blocks=[]; results=[]
for number,name in [(129,'pwx12new'),(130,'pwx12legacy'),(131,'pwx4legacy'),(132,'pwx4new'),(136,'pwx4rogowski')]:
 rel=f'tasmota/tasmota_xdrv_driver/xdrv_{number}_{name}.ino'
 s=(r/rel).read_text(encoding='utf-8')
 old=(Path('C:/Users/benfe/AppData/Local/Temp/pwx_push_before_2boh14zt')/rel).read_text(encoding='utf-8')
 a=s.index('// BEGIN PWX WEBDAV PUSH'); b=s.index('// END PWX WEBDAV PUSH')+len('// END PWX WEBDAV PUSH')
 blocks.append(s[a:b]); stripped=s[:a]+s[b+2:]
 stripped=stripped.replace('      PwxPush::Poll();\n','',1)
 hook='''      if (XdrvMailbox.command && !strcasecmp(XdrvMailbox.command, "Push")) {
        PwxPush::Command(); result = true; break;
      }
'''
 assert stripped.count(hook)==1
 stripped=stripped.replace(hook,'',1)
 assert stripped==old, f'Unexpected unrelated edit in {rel}'
 assert s.count('PwxPush::Command(); result = true; break;')==1
 assert s.count('PwxPush::Poll();')==1
 assert s.index('static bool CustomLoadIdentity(')<a<s.index(f'bool Xdrv{number}(')
 results.append({'driver':number,'existing_source_preserved':True,'command_hook':True,'loop_hook':True})
assert len(set(blocks))==1
config=(r/'tasmota/my_user_config.h').read_text(encoding='utf-8')
for macro in ['USE_PWX_WEBDAV_PUSH','PWX_PUSH_URL','PWX_PUSH_TLS_PIN','PWX_PUSH_TLS_PIN2','PWX_PUSH_FILE_TIMEOUT_MS']:
 assert re.search(r'^#define '+macro+r'\b',config,re.M)
report={'drivers':results,'identical_implementation':True,'block_sha256':hashlib.sha256(blocks[0].encode()).hexdigest(),'validation':'Source checks only; no firmware compilation or live tests.'}
Path('temp/pwx_push_source_checks.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
