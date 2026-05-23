var version = "2.0.032026 with calibration"

import string
import global
import mqtt
import json
import gpio
import path

global.rx = 18
global.tx = 19

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

    gpio.pin_mode(global.rx, gpio.INPUT_PULLUP)
    gpio.pin_mode(global.tx, gpio.OUTPUT)
    global.ser = serial(global.rx, global.tx, 921600, serial.SERIAL_8N1)

    mqttprint('serial initialised')
end

def name(cmd, idx, payload, payload_json)
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

def getfile(cmd, idx, payload, payload_json)
    import string
    var message
    var nom_fichier = string.split(payload, '/').pop()

    mqttprint(nom_fichier)
    var filepath = 'https://raw.githubusercontent.com/mbenfe/upload/main/' + payload
    mqttprint(filepath)

    var wc = webclient()
    if (wc == nil)
        mqttprint("Erreur: impossible d'initialiser le client web")
        tasmota.resp_cmnd("Erreur de téléchargement.")
        return
    end

    wc.set_follow_redirects(true)
    wc.begin(filepath)
    var st = wc.GET()
    if (st != 200)
        message = "Erreur: code HTTP " + str(st)
        mqttprint(message)
        wc.close()
        tasmota.resp_cmnd("Erreur de téléchargement.")
        return
    end

    var bytes_written = wc.write_file(nom_fichier)
    wc.close()
    mqttprint('Fetched ' + str(bytes_written))
    if st == 200
        tasmota.resp_cmnd('uploaded:' + nom_fichier)
    else
        tasmota.resp_cmnd("Erreur de téléchargement.")
    end
end

def dir(cmd, idx, payload, payload_json)
    import path
    var liste
    var file
    var taille
    var date
    var timestamp
    liste = path.listdir("/")
    mqttprint(str(liste.size()) + " fichiers")
    for i:0..(liste.size()-1)
        file = open(liste[i], "r")
        taille = file.size()
        file.close()
        timestamp = path.last_modified(liste[i])
        mqttprint(liste[i] + ' ' + tasmota.time_str(timestamp) + ' ' + str(taille))
    end
    tasmota.resp_cmnd_done()
end

def help()
    print("==================== EXHAUSTIVE HELP ====================")
    print("Driver 129 owns C071 flash/set/get/cal commands on its dedicated UART.")

    print("[REGISTERED COMMANDS]")
    print("Init | getfile | name | h | dir | getversion | update | couts")

    print("[STM32 SET COMMANDS]")
    print("set MODE CAL <1|2|3>")
    print("set MODE LOG")
    print("set MODE REG")
    print("set TYPE MONO")
    print("set TYPE TRI")
    print("set CONFIG")

    print("[STM32 GET COMMANDS]")
    print("get CAL")
    print("get CALFMT")
    print("get CONFIG   (publishes JSON on .../tele/CONFIG)")
    print("get MODE")
    print("get TYPE")
    print("get REG")
    print("get ENERGY")

    print("[STM32 CAL COMMANDS]")
    print("cal OFFSET")
    print("cal VA <voltage_ref>")
    print("cal VB <voltage_ref>")
    print("cal VC <voltage_ref>")
    print("cal IA <device:1..3> <current_ref>")
    print("cal IB <device:1..3> <current_ref>")
    print("cal IC <device:1..3> <current_ref>")
    print("examples: cal OFFSET | cal VA 235 | cal IA 1 5.1")

    print("[ESP32 LOCAL COMMANDS]")
    print("Init")
    print("getfile <repo_path/filename>")
    print("name <old_name> <new_name>")
    print("dir")
    print("getversion")
    print("update")
    print("couts")
    print("h")

    print("[NOTES]")
    print("- commands are no longer sent from Berry")
    print("- telemetry remains handled by pwx12_driver.be")
    print("- update downloads: c_<ville>.json, p_<ville>.json, conso.be, flasher.be, intelhex.be, pwx12_driver.be")
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

def update()
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    var myjson = json.load(buffer)
    global.ville = myjson["ville"]
    file.close()
    mqttprint("update: start")
    var name = string.format("c_%s.json", global.ville)
    var file_to_fetch = string.format("config/%s", name)
    mqttprint("update: getfile " + file_to_fetch)
    tasmota.cmd("getfile " + file_to_fetch)
    name = string.format("p_%s.json", global.ville)
    file_to_fetch = string.format("config/%s", name)
    mqttprint("update: getfile " + file_to_fetch)
    tasmota.cmd("getfile " + file_to_fetch)
    mqttprint("update: getfile pwx12/c3/berry/conso.be")
    tasmota.cmd("getfile pwx12/c3/berry/conso.be")
    mqttprint("update: getfile pwx12/c3/berry/flasher.be")
    tasmota.cmd("getfile pwx12/c3/berry/flasher.be")
    mqttprint("update: getfile flashers/stm32C071-PWX/intelhex.be")
    tasmota.cmd("getfile flashers/stm32C071-PWX/intelhex.be")
    mqttprint("update: getfile pwx12/c3/berry/pwx12_driver.be")
    tasmota.cmd("getfile pwx12/c3/berry/pwx12_driver.be")
    mqttprint("update: getfile pwx12/c3/berry/autoexec.be")
    tasmota.cmd("getfile pwx12/c3/berry/autoexec.be")
    mqttprint("update: getfile pwx12/c3/app/PWX12-flashed.bin")
    tasmota.cmd("getfile pwx12/c3/app/PWX12-flashed.bin")
    mqttprint("update: getfile pwx12/c3/boot/C071-bootloader.bin")
    tasmota.cmd("getfile pwx12/c3/boot/C071-bootloader.bin")
    mqttprint("update: done")
end

def couts()
    tasmota.cmd("br import conso as c; c.mqtt_publish('all')")
    tasmota.resp_cmnd_done()
end

def launch_driver()
    tasmota.load("pwx12_driver.be")
end

tasmota.cmd("seriallog 0")
print("serial log disabled")
tasmota.cmd("Teleperiod 0")

# ====================== ESP32 COMMANDS ======================
tasmota.add_cmd("Init", Init)
print("add_cmd:", "Init")
tasmota.add_cmd("getfile", getfile)
print("add_cmd:", "getfile")
tasmota.add_cmd("name", name)
print("add_cmd:", "name")
tasmota.add_cmd("h", help)
print("add_cmd:", "h")
tasmota.add_cmd('dir', dir)
print("add_cmd:", "dir")
tasmota.add_cmd('getversion', getversion)
print("add_cmd:", "getversion")
tasmota.add_cmd('update', update)
print("add_cmd:", "update")
tasmota.add_cmd('couts', couts)
print("add_cmd:", "couts")

############################################################
Init()
print("wait 30s for driver loading")
tasmota.set_timer(30000, launch_driver)
