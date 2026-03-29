var version = "2.0.032026 with calibration"

import string
import global
import mqtt
import json
import gpio
import path

var rxSend = 16
var txSend = 17
var rxReceive = 3
var txReceive = 1
var rst = 2   
var bsl = 13   

global.device = nil
global.ville = nil
global.client = nil

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

# ------------------------------------------------------------
# ----------------------- CAL COMMANDS -----------------------
# ------------------------------------------------------------

def Calibration(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload), " ")
    if (size(argument) == 0 || argument[0] == "")
        mqttprint("erreur arguments")
        return
    end

    if (argument[0] == "OFFSET")
        var token_offset = "CAL OFFSET\n"
        global.serSend.flush()
        global.serSend.write(bytes().fromstring(token_offset))
        mqttprint(token_offset)
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] != "VA" && argument[0] != "VB" && argument[0] != "VC" && argument[0] != "IA" && argument[0] != "IB" && argument[0] != "IC")
        mqttprint("erreur arguments")
        return
    end

    if (argument[0] == "VA" || argument[0] == "VB" || argument[0] == "VC")
        if (size(argument) < 2 || argument[1] == "")
            mqttprint("erreur arguments")
            return
        end
    else
        # Single BL6552: accept only "cal IA <current_ref>" form.
        if (size(argument) != 2 || argument[1] == "")
            mqttprint("erreur arguments")
            return
        end
    end

    var token
    if (argument[0] == "VA" || argument[0] == "VB" || argument[0] == "VC")
        token = string.format("CAL V %s %s\n", argument[0], argument[1])
    else
        var current_ref = argument[1]
        token = string.format("CAL I %s %s\n", argument[0], current_ref)
    end
    global.serSend.flush()
    global.serSend.write(bytes().fromstring(token))
    mqttprint(token)
    tasmota.resp_cmnd_done()
end

# ------------------------------------------------------------
# ----------------------- SET COMMANDS -----------------------
# ------------------------------------------------------------

def SetCommand(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload), " ")
    if (size(argument) == 0 || argument[0] == "")
        mqttprint("erreur arguments")
        return
    end

    global.serSend.flush()

    if (argument[0] == "RESET")
        mqttprint("SET RESET disabled; use Stm32reset")
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "MODE")
        if (size(argument) < 2 || (argument[1] != "CAL" && argument[1] != "LOG" && argument[1] != "REG"))
            mqttprint("erreur arguments")
            return
        end

        var token_mode
        if (argument[1] == "CAL")
            # Single BL6552: only accept "set MODE CAL".
            if (size(argument) != 2)
                mqttprint("erreur arguments")
                return
            end
            token_mode = "SET MODE CAL\n"
        else
            token_mode = string.format("SET MODE %s\n", argument[1])
        end

        global.serSend.write(bytes().fromstring(token_mode))
        mqttprint(token_mode)
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "TYPE")
        if (size(argument) < 2 || (argument[1] != "MONO" && argument[1] != "TRI"))
            mqttprint("erreur arguments")
            return
        end
        var token_type = string.format("SET TYPE %s\n", argument[1])
        global.serSend.write(bytes().fromstring(token_type))
        mqttprint(token_type)
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "CONFIG")
        mqttprint("SET CONFIG disabled; applied by driver at boot")
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "STORAGE")
        mqttprint("SET STORAGE disabled")
        tasmota.resp_cmnd_done()
        return
    end

    mqttprint("SET inconnu")
end

# ------------------------------------------------------------
# ----------------------- GET COMMANDS -----------------------
# ------------------------------------------------------------

def GetCommand(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload), " ")
    if (size(argument) == 0 || argument[0] == "")
        mqttprint("erreur arguments")
        return
    end

    global.serSend.flush()

    if (argument[0] == "CONFIG")
        global.serSend.write(bytes().fromstring("GET CONFIG\n"))
        mqttprint('GET CONFIG')
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "CAL")
        global.serSend.write(bytes().fromstring("GET CAL\n"))
        mqttprint('GET CAL')
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "MODE")
        global.serSend.write(bytes().fromstring("GET MODE\n"))
        mqttprint('GET MODE')
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "ENERGY")
        global.serSend.write(bytes().fromstring("GET ENERGY\n"))
        mqttprint('GET ENERGY')
        tasmota.resp_cmnd_done()
        return
    end

    mqttprint("GET inconnu")
end

def pretty_print_config()
    import json
    import string

    var file = open("esp32.cfg", "rt")
    if file == nil
        mqttprint("CONFIG: missing esp32.cfg")
        return
    end
    var buffer = file.read()
    file.close()
    var runtime_cfg = json.load(buffer)
    if runtime_cfg == nil
        mqttprint("CONFIG: invalid esp32.cfg")
        return
    end

    var ville = runtime_cfg["ville"]
    var device = runtime_cfg["device"]
    var cfg_file = string.format("p_%s.json", ville)

    file = open(cfg_file, "rt")
    if file == nil
        mqttprint("CONFIG: missing " + cfg_file)
        return
    end
    buffer = file.read()
    file.close()
    var all_cfg = json.load(buffer)
    if all_cfg == nil || !all_cfg.contains(device)
        mqttprint("CONFIG: device " + device + " not found in " + cfg_file)
        return
    end

    var dev = all_cfg[device]
    mqttprint("CONFIG SUMMARY")
    mqttprint(string.format("ville=%s device=%s produit=%s", ville, device, str(dev["produit"])))

    for i: 0..0
        var name = "*"
        var techno = "ct"
        var ratio = "1000"
        var pga = "1"
        var mode = "tri"

        if dev.contains("root") && dev["root"] != nil && size(dev["root"]) > i && dev["root"][i] != nil
            name = str(dev["root"][i])
        end
        if dev.contains("techno") && dev["techno"] != nil && size(dev["techno"]) > i && dev["techno"][i] != nil
            techno = str(dev["techno"][i])
        end
        if dev.contains("ratio") && dev["ratio"] != nil && size(dev["ratio"]) > i && dev["ratio"][i] != nil
            ratio = str(dev["ratio"][i])
        end
        if dev.contains("PGA") && dev["PGA"] != nil && size(dev["PGA"]) > i && dev["PGA"][i] != nil
            pga = str(dev["PGA"][i])
        end
        if dev.contains("mode") && dev["mode"] != nil
            if type(dev["mode"]) == "list" && size(dev["mode"]) > i && dev["mode"][i] != nil
                mode = str(dev["mode"][i])
            elif type(dev["mode"]) == "string"
                mode = str(dev["mode"])
            end
        end

        mqttprint(string.format("ch%d Name=%s techno=%s ratio=%s pga=%s mode=%s", i + 1, name, techno, ratio, pga, mode))
    end
end

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

    gpio.pin_mode(rxSend, gpio.INPUT)
    gpio.pin_mode(txSend, gpio.OUTPUT)
    gpio.pin_mode(rxReceive, gpio.INPUT)
    gpio.pin_mode(txReceive, gpio.OUTPUT)

    global.serSend = serial(rxSend, txSend, 115200, serial.SERIAL_8N1)
    global.serReceive = serial(rxReceive, txReceive, 115200, serial.SERIAL_8N1)
    mqttprint('serial initialised')
end

def ville(cmd, idx, payload, payload_json)
    import json
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    var myjson = json.load(buffer)
    myjson["ville"] = payload
    global.ville = payload
    buffer = json.dump(myjson)
    file.close()
    file = open("esp32.cfg", "wt")
    file.write(buffer)
    file.close()
    tasmota.resp_cmnd("done")
end

def device(cmd, idx, payload, payload_json)
    import json
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    var myjson = json.load(buffer)
    myjson["device"] = payload
    global.device = payload
    buffer = json.dump(myjson)
    file.close()
    file = open("esp32.cfg", "wt")
    file.write(buffer)
    file.close()
    tasmota.resp_cmnd("done")
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
    for i:0..0
        mqttprint(str(i))
        if (size(myjson['hours']) > i && myjson['hours'][i]['Name'] == argument[0])
            myjson['hours'][i]['Name'] = argument[1]
            trouve += 1
        end
        if (size(myjson['days']) > i && myjson['days'][i]['Name'] == argument[0])
            myjson['days'][i]['Name'] = argument[1]
            trouve += 1
        end
        if (size(myjson['months']) > i && myjson['months'][i]['Name'] == argument[0])
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
        tasmota.resp_cmnd("Erreur d'initialisation du client web.")
        tasmota.add_driver(global.pwx4)
        start()
        return
    end

    wc.set_follow_redirects(true)
    wc.begin(filepath)
    var st = wc.GET()
    if (st != 200)
        message = "Erreur: code HTTP " + str(st)
        mqttprint(message)
        tasmota.resp_cmnd("Erreur de téléchargement.")
        wc.close()
        start()
        return
    end

    var bytes_written = wc.write_file(nom_fichier)
    wc.close()
    mqttprint('Fetched ' + str(bytes_written))
    message = 'uploaded:' + nom_fichier
    tasmota.resp_cmnd(message)
    start()
    return st
end

def sendconfig(cmd, idx, payload, payload_json)
    import string
    import json
    var file
    var buffer
    var myjson
    var device
    var ville
    var config_file
    var total = ""
    var header
    var trouve = false
    ############################ fichier config ###################
    file = open("esp32.cfg", "rt")
    buffer = file.read()
    myjson = json.load(buffer)
    device = myjson["device"]
    ville = myjson["ville"]
    file.close()

    if payload == nil || payload == ""
        config_file = string.format("p_%s.json", ville)
    else
        config_file = payload
    end
    mqttprint("send:" + config_file)

    file = open(config_file, "rt")
    if (file == nil)
        mqttprint("fichier non existant:" + config_file)
        return
    end
    buffer = file.read()
    file.close()
    myjson = json.load(buffer)
    for key:myjson.keys()
        if (key == device)
            trouve = true
                var p0 = "1"
                var m0 = "tri"
                if myjson[key].contains("PGA") && myjson[key]["PGA"] != nil && size(myjson[key]["PGA"]) > 0
                    p0 = str(myjson[key]["PGA"][0])
                end
                if myjson[key].contains("mode") && myjson[key]["mode"] != nil
                    if type(myjson[key]["mode"]) == "list" && size(myjson[key]["mode"]) > 0
                        m0 = str(myjson[key]["mode"][0])
                    elif type(myjson[key]["mode"]) == "string"
                        m0 = str(myjson[key]["mode"])
                    end
                end

                total = "CONFIG " + key + ":"
                    + myjson[key]["root"][0] + ":"
                    + myjson[key]["produit"] + ":"
                    + myjson[key]["techno"][0] + ":"
                    + myjson[key]["ratio"][0] + ":"
                    + p0 + ":"
                    + m0
        end
    end
    if (trouve == true)
        global.serSend.flush()
        total = "SET " + total + "\n"
        var mybytes = bytes().fromstring(total)
        global.serSend.write(mybytes)
        mqttprint(str(total))
        tasmota.resp_cmnd("config sent")
    else
        mqttprint("device " + str(device) + " non trouvé")
        tasmota.resp_cmnd("config not sent")
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
    print("All tokens for set/get/cal are case-insensitive.")

    print("[REGISTERED COMMANDS]")
    print("Stm32reset | hold | start | set | get | sendconfig | cal")
    print("Init | getfile | ville | device | name | h | dir | getversion | update | couts")

    print("[STM32 LINK CONTROL]")
    print("Stm32reset")
    print("hold")
    print("start")

    print("[STM32 SET COMMANDS]")
    print("set MODE CAL")
    print("set MODE LOG")
    print("set MODE REG")
    print("set TYPE MONO")
    print("set TYPE TRI")

    print("[STM32 GET COMMANDS]")
    print("get CAL")
    print("get CONFIG   (query STM32 applied config as JSON)")
    print("get MODE")
    print("get ENERGY")

    print("[STM32 CAL COMMANDS]")
    print("cal OFFSET")
    print("cal VA <voltage_ref>")
    print("cal VB <voltage_ref>")
    print("cal VC <voltage_ref>")
    print("cal IA <current_ref>")
    print("cal IB <current_ref>")
    print("cal IC <current_ref>")
    print("examples: cal OFFSET | cal VA 235 | cal IA 5.1")

    print("[CONFIG HELPER]")
    print("sendconfig")
    print("- default file: p_<ville>.json from esp32.cfg")
    print("sendconfig <json_file_path>  (optional override)")
    print("example override: sendconfig p_maisons-laffite.json")
    print("expects file key = current device from esp32.cfg")

    print("[ESP32 LOCAL COMMANDS]")
    print("Init")
    print("getfile <repo_path/filename>")
    print("ville <new_ville>")
    print("device <new_device>")
    print("name <old_name> <new_name>")
    print("dir")
    print("getversion")
    print("update")
    print("couts")
    print("h")

    print("[NOTES]")
    print("- UART send link: commands to STM32")
    print("- UART receive link: telemetry from STM32")
    print("- update downloads: c_<ville>.json, p_<ville>.json, command.be, conso.be, flasher.be, logger.be, pwx4_driver.be")
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
    var ville = global.ville
    file.close()
    mqttprint("update: start")
    hold()
    var name = string.format("c_%s.json", ville)
    var command = string.format("getfile config/%s", name)
    mqttprint("update: " + command)
    tasmota.cmd(command)
    name = string.format("p_%s.json", ville)
    command = string.format("getfile config/%s", name)
    mqttprint("update: " + command)
    tasmota.cmd(command)
    mqttprint("update: getfile pwx4/berry-legacy/command.be")
    tasmota.cmd("getfile pwx4/berry-legacy/command.be")
    mqttprint("update: getfile pwx4/berry-legacy/conso.be")
    tasmota.cmd("getfile pwx4/berry-legacy/conso.be")   
    mqttprint("update: getfile pwx4/berry-legacy/flasher.be")
    tasmota.cmd("getfile pwx4/berry-legacy/flasher.be")
    mqttprint("update: getfile pwx4/berry-legacy/logger.be")
    tasmota.cmd("getfile pwx4/berry-legacy/logger.be")
    mqttprint("update: getfile pwx4/berry-legacy/pwx4_driver.be")
    tasmota.cmd("getfile pwx4/berry-legacy/pwx4_driver.be")
    start()
    mqttprint("update: done")
end

def couts()
    tasmota.cmd("br import conso as c; c.mqtt_publish('all')")
    tasmota.resp_cmnd_done()
end

tasmota.cmd("seriallog 0")
print("serial log disabled")
tasmota.cmd("Teleperiod 0")

# ====================== STM32 COMMANDS ======================
tasmota.add_cmd("Stm32reset", Stm32Reset)
tasmota.add_cmd("hold", hold)
tasmota.add_cmd("start", start)
tasmota.add_cmd("set", SetCommand)
tasmota.add_cmd("get", GetCommand)
tasmota.add_cmd("sendconfig", sendconfig)
tasmota.add_cmd("cal", Calibration)

# ====================== ESP32 COMMANDS ======================
tasmota.add_cmd("Init", Init)
tasmota.add_cmd("getfile", getfile)
tasmota.add_cmd("ville", ville)
tasmota.add_cmd("device", device)
tasmota.add_cmd("name", name)
tasmota.add_cmd("h", help)
tasmota.add_cmd('dir', dir)
tasmota.add_cmd('getversion', getversion)
tasmota.add_cmd('update', update)
tasmota.add_cmd('couts', couts)

############################################################
Init()
tasmota.load("pwx4_driver.be")
print(global.pwx4)
