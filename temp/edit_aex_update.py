from pathlib import Path
import json,re
base=Path('aex')
pwx=Path('pwx4/c3/berry/autoexec.be').read_text(encoding='utf-8-sig')
raw=pwx[pwx.index('def fetch_file_raw(payload)'):pwx.index('def fetch_file(payload)')]
raw=raw.replace("    mqttprint('Fetched ' + str(bytes_written))", "    if bytes_written == nil || bytes_written <= 0\n        mqttprint('update: file write failed')\n        return -2\n    end\n    mqttprint('Fetched ' + str(bytes_written))")
update='''def update(cmd, idx, payload, payload_json)
    var selector = ""
    if payload != nil
        selector = string.tolower(payload)
    end
    if selector != "" && selector != "*.*" && selector != "all" && selector != "*.be" && selector != ".be" && selector != "be"
        tasmota.resp_cmnd("invalid update filter (use *.be)")
        return
    end

    var file = open("esp32.cfg", "rt")
    var cfg = json.load(file.read())
    file.close()
    var aex_type = cfg.find("type", "DEFAULT_TYPE")
    var scripts
    if aex_type == "standard"
        scripts = ["command.be", "io.be", "ds18b20.be", "pt1000.be", "standard_driver.be", "autoexec.be"]
    elif aex_type == "seet"
        scripts = ["command.be", "seet_driver.be", "autoexec.be"]
    elif aex_type == "climair"
        scripts = ["command.be", "climair_driver.be", "autoexec.be"]
    else
        tasmota.resp_cmnd("invalid AEX type (use climair|seet|standard)")
        return
    end

    mqttprint("update: type=" + aex_type + " files=" + str(scripts.size()))
    for script:scripts
        var remote = "aex/" + aex_type + "/berry/" + script
        var st = fetch_file_raw(remote)
        if st != 200
            mqttprint("update: failed " + remote + " status=" + str(st))
            tasmota.resp_cmnd("update failed: " + script)
            return
        end
    end
    mqttprint("update: done; restart to load updated scripts")
    tasmota.resp_cmnd("updated; restart to load updated scripts")
end

'''
for variant in ('standard','seet','climair'):
 folder=base/variant/'berry';p=folder/'autoexec.be';s=p.read_text(encoding='utf-8-sig')
 assert 'def update(' not in s and 'def fetch_file_raw(' not in s
 s=re.sub(r'^var version = .*', 'var version = "1.1.102026 type and update"',s,count=1)
 start=s.index('def loadconfig()');pos=s.index('    var myjson = json.load(buffer)',start)+len('    var myjson = json.load(buffer)')
 migration='''
    global.aex_type = myjson.find("type", "VARIANT")
    if global.aex_type != "standard" && global.aex_type != "seet" && global.aex_type != "climair"
        raise "value_error", "invalid AEX type (use climair|seet|standard)"
    end
    if !myjson.contains("type")
        myjson["type"] = global.aex_type
        var cfg_file = open("esp32.cfg", "wt")
        cfg_file.write(json.dump(myjson))
        cfg_file.close()
    end
    print("type: " + global.aex_type)'''.replace('VARIANT',variant)
 s=s[:pos]+migration+s[pos:]
 s=s.replace('def getfile(cmd, idx, payload, payload_json)',raw+update.replace('DEFAULT_TYPE',variant)+'def getfile(cmd, idx, payload, payload_json)',1)
 s=s.replace("tasmota.add_cmd('getfile', getfile)","tasmota.add_cmd('getfile', getfile)\ntasmota.add_cmd('update', update)",1)
 p.write_bytes(s.replace('\r\n','\n').replace('\n','\r\n').encode('utf-8'))
 cfg=folder/'esp32.cfg';data=json.loads(cfg.read_text(encoding='utf-8-sig'));data['type']=variant;cfg.write_bytes((json.dumps(data,separators=(',',':'))+'\r\n').encode())
print('Updated three AEX autoexec scripts and three esp32.cfg templates.')