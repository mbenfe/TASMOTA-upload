var version = "04072026 dir update *"

import string
import global
import mqtt
import json
import path

#-------------------------------- COMMANDES -----------------------------------------#

def mqttprint(texte)
    import mqtt
    var payload = string.format("{\"texte\":\"%s\"}", texte)
    var topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
    mqtt.publish(topic, payload, true)
end

# ============================================================
# ====================== ESP32 COMMANDS ======================
# ============================================================

def Init()
    import json
    var file = open("esp32.cfg", "rt")
    if file == nil || file.size() == 0
        if file != nil
            file.close()
        end
        file = open("esp32.cfg", "wt")
        var jsonstring = string.format('{"ville":"unknown","client":"inter","device":"unknown"}')
        file.write(jsonstring)
        file.close()
        file = open("esp32.cfg", "rt")
    end

    var buffer = file.read()
    file.close()
    var jsonmap = json.load(buffer)
    if jsonmap == nil
        mqttprint("CONFIG: invalid esp32.cfg")
        return
    end

    global.client = jsonmap["client"]
    global.ville = jsonmap["ville"]
    global.device = jsonmap["device"]
    print('client:', global.client)
    print('ville:', global.ville)
    print('device:', global.device)

end



def fetch_file(payload)
    import string
    import path
    var message
    var nom_fichier = string.split(payload, '/').pop()

    tasmota.cmd("hold")

    mqttprint(nom_fichier)
    var filepath = 'https://raw.githubusercontent.com/mbenfe/upload/main/' + payload
    mqttprint(filepath)

    var wc = webclient()
    if (wc == nil)
        mqttprint("Erreur: impossible d'initialiser le client web")
        tasmota.cmd("start")
        return -1
    end

    wc.set_follow_redirects(true)
    wc.begin(filepath)
    var st = wc.GET()
    if (st != 200)
        message = "Erreur: code HTTP " + str(st)
        mqttprint(message)
        wc.close()
        tasmota.cmd("start")
        return st
    end

    var bytes_written = wc.write_file(nom_fichier)
    wc.close()
    mqttprint('Fetched ' + str(bytes_written))
    tasmota.cmd("start")
    return st
end

def getfile(cmd, idx, payload, payload_json)
    var st = fetch_file(payload)
    if st == 200
        var nom_fichier = string.split(payload, '/').pop()
        tasmota.resp_cmnd('uploaded:' + nom_fichier)
    elif st == -1
        tasmota.resp_cmnd("Erreur d'initialisation du client web.")
    else
        tasmota.resp_cmnd("Erreur de téléchargement.")
    end
end

def dir(cmd, idx, payload, payload_json)
    import path
    var selector = ""
    if payload != nil
        selector = string.tolower(payload)
    end

    var want_all = (selector == "" || selector == "*.*" || selector == "all")
    var want_be = (want_all || selector == "*.be" || selector == ".be" || selector == "be")
    var want_hex = (want_all || selector == "*.hex" || selector == ".hex" || selector == "hex")
    var want_bin = (want_all || selector == "*.bin" || selector == ".bin" || selector == "bin")
    var want_json = (want_all || selector == "*.json" || selector == ".json" || selector == "json")

    if !want_be && !want_hex && !want_bin && !want_json
        mqttprint("dir: unknown filter '" + selector + "' (use *.be|*.hex|*.bin|*.json)")
        tasmota.resp_cmnd("invalid dir filter")
        return
    end

    var liste
    var file
    var taille
    var date
    var timestamp
    var matched = 0
    liste = path.listdir("/")
    mqttprint("dir: filter='" + selector + "'")
    for i:0..(liste.size()-1)
        var name_lc = string.tolower(liste[i])
        var match = want_all
        if !match
            if want_be && string.endswith(name_lc, ".be")
                match = true
            elif want_hex && string.endswith(name_lc, ".hex")
                match = true
            elif want_bin && string.endswith(name_lc, ".bin")
                match = true
            elif want_json && string.endswith(name_lc, ".json")
                match = true
            end
        end

        if match
            file = open(liste[i], "r")
            if file != nil
                taille = file.size()
                file.close()
                timestamp = path.last_modified(liste[i])
                mqttprint(liste[i] + ' ' + tasmota.time_str(timestamp) + ' ' + str(taille))
                matched += 1
            end
        end
    end
    mqttprint(str(matched) + " fichiers")
    tasmota.resp_cmnd_done()
end

def del_file(cmd, idx, payload, payload_json)
    import path
    var filename = payload

    if filename == nil || filename == ""
        tasmota.resp_cmnd("usage: del <filename>")
        return
    end

    if string.find(filename, "*") != -1 || string.find(filename, "?") != -1
        tasmota.resp_cmnd("wildcards not allowed")
        return
    end

    if string.find(filename, "/") != -1 || string.find(filename, "\\") != -1
        tasmota.resp_cmnd("strict filename only")
        return
    end

    if !path.exists(filename)
        tasmota.resp_cmnd("file not found")
        return
    end

    path.remove(filename)
    if path.exists(filename)
        tasmota.resp_cmnd("delete failed")
    else
        tasmota.resp_cmnd("deleted:" + filename)
    end
end

def help()
    print("==================== EXHAUSTIVE HELP ====================")
    print("Driver 132 owns STM32 set/get/cal/config commands on C071 UART.")

    print("[REGISTERED COMMANDS]")
    print("Driver: stm32reset | hold | start")
    print("Script: Init | getfile | name | help | h | dir | getversion | update | couts")

    print("[STM32 LINK CONTROL]")
    print("Stm32reset")
    print("hold")
    print("start")

    print("[STM32 DRIVER COMMANDS]")
    print("set MODE CAL|LOG|REG")
    print("set TYPE MONO|TRI")
    print("set CONFIG")
    print("get CAL")
    print("get CONFIG")
    print("get MODE")
    print("get TYPE")
    print("get ENERGY")
    print("cal OFFSET")
    print("cal VA <voltage_ref>")
    print("cal VB <voltage_ref>")
    print("cal VC <voltage_ref>")
    print("cal IA <current_ref>")
    print("cal IB <current_ref>")
    print("cal IC <current_ref>")

    print("[ESP32 LOCAL COMMANDS]")
    print("Init")
    print("getfile <repo_path/filename>")
    print("dir")
    print("dir *.be | dir *.hex | dir *.bin | dir *.json")
    print("getversion")
    print("update")
    print("couts")
    print("h")

    print("[NOTES]")
    print("- UART receive link: telemetry from STM32 handled by driver 132 on pins 18/19")
    print("- update                   : download all update files")
    print("- update *.be             : download all Berry files")
    print("- update *.hex            : download all HEX files")
    print("- update *.bin            : download all BIN files")
    print("- update *.json           : download c_<ville>.json and p_<ville>.json")
    tasmota.resp_cmnd_done()
end

def getversion()
    var fichier
    var files = path.listdir("/")
    for i:0..files.size()-1
        if string.endswith(files[i],".be")
            fichier = open(files[i], "r")
            var content = fichier.readline()
            var version_match = string.find(content, 'var version')
           if version_match != -1
                var liste = string.split(content,' ')
                mqttprint(files[i] + " version: " + liste[3])
            else
                mqttprint(files[i] + " version: undefined version")
            end
            fichier.close()
        end
    end
    tasmota.resp_cmnd_done()
end

def update(cmd, idx, payload, payload_json)
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    var myjson = json.load(buffer)
    global.ville = myjson["ville"]
    file.close()

    var selector = ""
    if payload != nil
        selector = string.tolower(payload)
    end

    var want_all = (selector == "" || selector == "*.*" || selector == "all")
    var want_be = (want_all || selector == "*.be" || selector == ".be" || selector == "be")
    var want_hex = (want_all || selector == "*.hex" || selector == ".hex" || selector == "hex")
    var want_bin = (want_all || selector == "*.bin" || selector == ".bin" || selector == "bin")
    var want_json = (want_all || selector == "*.json" || selector == ".json" || selector == "json")

    if !want_be && !want_hex && !want_bin && !want_json
        mqttprint("update: unknown filter '" + selector + "' (use *.be|*.hex|*.bin|*.json)")
        tasmota.resp_cmnd("invalid update filter")
        return
    end

    var to_fetch = []
    if want_json
        var name = string.format("c_%s.json", global.ville)
        to_fetch.push(string.format("config/%s", name))
        name = string.format("p_%s.json", global.ville)
        to_fetch.push(string.format("config/%s", name))
        to_fetch.push("config/power_shared_villes.json")
    end

    if want_be
        to_fetch.push("pwx4/c3/berry/conso.be")
        to_fetch.push("pwx4/c3/berry/pwx4_driver.be")
        to_fetch.push("pwx4/c3/berry/autoexec.be")
    end

    if want_bin
        to_fetch.push("pwx4/c3/app/pwx4new-flashed.bin")
        to_fetch.push("pwx4/c3/boot/C071-bootloader.bin")
    end

    if want_hex
        to_fetch.push("hex/C071-bootloader.hex")
        to_fetch.push("hex/pwx4new-flashed.hex")
    end

    mqttprint("update: start")
    mqttprint("update: filter='" + selector + "' files=" + str(to_fetch.size()))
    for i:0..to_fetch.size()-1
        var file_to_fetch = to_fetch[i]
        mqttprint("update: getfile " + file_to_fetch)
        fetch_file(file_to_fetch)
    end
    mqttprint("update: done")
end

def couts()
    tasmota.cmd("br import conso as c; c.mqtt_publish('all')")
    tasmota.resp_cmnd_done()
end

print("main: disable seriallog")
tasmota.cmd("seriallog 0")
print("serial log disabled")
print("main: disable teleperiod")
tasmota.cmd("Teleperiod 0")
print("main: stm32 commands handled by driver")

# ====================== ESP32 COMMANDS ======================
print("main: register esp32 commands")
tasmota.add_cmd("Init", Init)
tasmota.add_cmd("getfile", getfile)
tasmota.add_cmd("help", help)
tasmota.add_cmd("h", help)
tasmota.add_cmd('dir', dir)
tasmota.add_cmd('del', del_file)
tasmota.add_cmd('getversion', getversion)
tasmota.add_cmd('update', update)
tasmota.add_cmd('couts', couts)

############################################################
print("main: call Init")
Init()
print("main: load pwx4_driver.be")
tasmota.load("pwx4_driver.be")
print("main: autoexec done")
