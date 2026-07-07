var version = "04072026 dir update *"

import string
import global
import mqtt
import json
import gpio
import path

var rxReceive = 3
var txReceive = 1
var rst = 2   
var bsl = 13   

#-------------------------------- COMMANDES -----------------------------------------#

def mqttprint(texte)
    import mqtt
    var payload = string.format("{\"texte\":\"%s\"}", texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, payload, true)
end

# ============================================================
# ====================== STM32 COMMANDS ======================
# ============================================================

def Stm32Reset()
    gpio.pin_mode(rst, gpio.OUTPUT)
    gpio.pin_mode(bsl, gpio.OUTPUT)
    gpio.digital_write(rst, 0)
    tasmota.delay(100)  # wait 10ms
    gpio.digital_write(rst, 1)
    tasmota.delay(100)  # wait 10ms
    tasmota.resp_cmnd("STM32 reset")
end

def hold()
    # Hold STM32 in reset and keep boot pin low.
    gpio.pin_mode(rst, gpio.OUTPUT)
    gpio.pin_mode(bsl, gpio.OUTPUT)
    gpio.digital_write(bsl, 0)
    gpio.digital_write(rst, 0)
    tasmota.resp_cmnd("done")
end

def start()
    # Release reset and keep boot pin low for normal boot.
    gpio.pin_mode(rst, gpio.OUTPUT)
    gpio.pin_mode(bsl, gpio.OUTPUT)
    gpio.digital_write(bsl, 0)
    gpio.digital_write(rst, 1)
    tasmota.resp_cmnd("done")
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

    gpio.pin_mode(rxReceive, gpio.INPUT)
    gpio.pin_mode(txReceive, gpio.OUTPUT)
    gpio.pin_mode(rst, gpio.OUTPUT)
    gpio.pin_mode(bsl, gpio.OUTPUT)
    gpio.digital_write(bsl, 0)
    gpio.digital_write(rst, 1)

    global.serReceive = serial(rxReceive, txReceive, 921600, serial.SERIAL_8N1)
    mqttprint('serial receive initialised')
end



def rename(cmd, idx, payload, payload_json)
    import json
    var argument = string.split(payload, ' ')
    if (size(argument) < 2)
        mqttprint('erreur arguments')
        tasmota.resp_cmnd('exit')
        return
    end
    var file = open('conso.json', 'r')
    var config = file.read()
    file.close()
    var myjson = json.load(config)
    var trouve = 0
    mqttprint('recherche')
    for i:0..2
        mqttprint(str(i))
        if (myjson['hours'][i]['Name'] == argument[0])
            myjson['hours'][i]['Name'] = argument[1]
            trouve += 1
        end
        if (myjson['days'][i]['Name'] == argument[0])
            myjson['days'][i]['Name'] = argument[1]
            trouve += 1
        end
        if (myjson['months'][i]['Name'] == argument[0])
            myjson['months'][i]['Name'] = argument[1]
            trouve += 1
        end
    end
    if (trouve == 0)
        mqttprint('nom non existant')
        tasmota.resp_cmnd('exit')
        return
    else
        mqttprint('rename ' + str(argument[0]) + ' -> ' + argument[1])
        file = open('conso.json', 'w')
        var newconfig = json.dump(myjson)
        file.write(newconfig)
        file.close()
    end
    tasmota.resp_cmnd('done')
end

def fetch_file(payload)
    import string
    import path
    var message
    var nom_fichier = string.split(payload, '/').pop()

    hold()

    mqttprint(nom_fichier)
    var filepath = 'https://raw.githubusercontent.com/mbenfe/upload/main/' + payload
    mqttprint(filepath)

    var wc = webclient()
    if (wc == nil)
        mqttprint("Erreur: impossible d'initialiser le client web")
        tasmota.add_driver(global.pwx12)
        start()
        return -1
    end

    wc.set_follow_redirects(true)
    wc.begin(filepath)
    var st = wc.GET()
    if (st != 200)
        message = "Erreur: code HTTP " + str(st)
        mqttprint(message)
        wc.close()
        start()
        return st
    end

    var bytes_written = wc.write_file(nom_fichier)
    wc.close()
    mqttprint('Fetched ' + str(bytes_written))
    start()
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
    print("Driver 130 owns STM32 set/get/cal commands on UART 16/17.")

    print("[REGISTERED COMMANDS]")
    print("Stm32reset | hold | start")
    print("Init | getfile | name | help | h | dir | getversion | update | couts")

    print("[STM32 LINK CONTROL]")
    print("Stm32reset")
    print("hold")
    print("start")

    print("[STM32 DRIVER COMMANDS]")
    print("set MODE CAL <1|2|3>")
    print("set MODE LOG")
    print("set MODE REG")
    print("set TYPE MONO")
    print("set TYPE TRI")
    print("set CONFIG")
    print("get CAL")
    print("get CALFMT")
    print("get CONFIG   (query STM32 applied config as JSON)")
    print("get MODE")
    print("get TYPE")
    print("get REG")
    print("get ENERGY")
    print("cal OFFSET")
    print("cal VA <voltage_ref>")
    print("cal VB <voltage_ref>")
    print("cal VC <voltage_ref>")
    print("cal IA <device:1..3> <current_ref>")
    print("cal IB <device:1..3> <current_ref>")
    print("cal IC <device:1..3> <current_ref>")
    print("cal V <VA|VB|VC> <voltage_ref>")
    print("cal I <IA|IB|IC> <device:1..3> <current_ref>")
    print("examples: cal OFFSET | cal VA 235 | cal IA 1 5.1 | cal I IA 1 5.1")

    print("[CONFIG HELPER]")
    print("set CONFIG")
    print("- auto-detects file: p_<ville>.json")
    print("- uses current device from esp32.cfg as lookup key")
    print("- sends all 3-channel config to STM32")

    print("[ESP32 LOCAL COMMANDS]")
    print("Init")
    print("getfile <repo_path/filename>")
    print("rename <old_name> <new_name>")
    print("dir")
    print("dir *.be | dir *.hex | dir *.bin | dir *.json")
    print("getversion")
    print("update")
    print("couts")
    print("h")

    print("[NOTES]")
    print("- UART send link: driver 130 on pins 16/17")
    print("- UART receive link: telemetry from STM32 on pins 3/1")
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
        to_fetch.push("pwx12/legacy/berry/conso.be")
        to_fetch.push("pwx12/legacy/berry/pwx12_driver.be")
        to_fetch.push("pwx12/legacy/berry/flasher.be")
        to_fetch.push("pwx12/legacy/berry/intelhex.be")
        to_fetch.push("pwx12/legacy/berry/autoexec.be")
    end

    if want_bin
        to_fetch.push("pwx12/legacy/app/pwx12legacy-flashed.bin")
    end

    if want_hex
        to_fetch.push("hex/pwx12legacy-flashed.hex")
        to_fetch.push("hex/F412-bootloader.hex")
    end

    mqttprint("update: start")
    mqttprint("update: filter='" + selector + "' files=" + str(to_fetch.size()))
    for i:0..to_fetch.size()-1
        var file_to_fetch = to_fetch[i]
        mqttprint("update: getfile " + file_to_fetch)
        fetch_file(file_to_fetch)
    end
    mqttprint("update: done")
    tasmota.resp_cmnd_done()
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
print("main: register stm32 commands")

# ====================== STM32 COMMANDS ======================
tasmota.add_cmd("Stm32reset", Stm32Reset)
tasmota.add_cmd("hold", hold)
tasmota.add_cmd("start", start)

# ====================== ESP32 COMMANDS ======================
print("main: register esp32 commands")
tasmota.add_cmd("Init", Init)
tasmota.add_cmd("getfile", getfile)
tasmota.add_cmd("rename", rename)
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
print("main: load pwx12_driver.be")
tasmota.load("pwx12_driver.be")
print("main: autoexec done")
