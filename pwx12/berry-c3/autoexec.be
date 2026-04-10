var version = "2.0.032026 with calibration"

import string
import global
import mqtt
import json
import gpio
import path

global.rx = 18
global.tx = 19
var rst = 9   
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
        global.ser.flush()
        global.ser.write(bytes().fromstring(token_offset))
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
        # For current calibration, enforce channel index 1..3 before reaching STM32.
        if (size(argument) < 3 || argument[1] == "" || argument[2] == "" || (argument[1] != "1" && argument[1] != "2" && argument[1] != "3"))
            mqttprint("erreur arguments")
            return
        end
    end

    var token
    if (argument[0] == "VA" || argument[0] == "VB" || argument[0] == "VC")
        token = string.format("CAL V %s %s\n", argument[0], argument[1])
    else
        token = string.format("CAL I %s %s %s\n", argument[0], argument[1], argument[2])
    end
    global.ser.flush()
    global.ser.write(bytes().fromstring(token))
    mqttprint(token)
    tasmota.resp_cmnd_done()
end

# ------------------------------------------------------------
# ----------------------- SET COMMANDS -----------------------
# ------------------------------------------------------------

def SetCommand(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload), " ")
    var argument_raw = string.split(payload, " ")
    if (size(argument) == 0 || argument[0] == "")
        mqttprint("erreur arguments")
        return
    end

    global.ser.flush()

    if (argument[0] == "RESET")
        var token_reset = "SET RESET\n"
        global.ser.write(bytes().fromstring(token_reset))
        mqttprint(token_reset)
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
            if (size(argument) < 3 || (argument[2] != "1" && argument[2] != "2" && argument[2] != "3"))
                mqttprint("erreur arguments")
                return
            end
            token_mode = string.format("SET MODE CAL %s\n", argument[2])
        else
            token_mode = string.format("SET MODE %s\n", argument[1])
        end

        global.ser.write(bytes().fromstring(token_mode))
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
        global.ser.write(bytes().fromstring(token_type))
        mqttprint(token_type)
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

    global.ser.flush()

    if (argument[0] == "CONFIG")
        global.ser.write(bytes().fromstring("GET CONFIG\n"))
        mqttprint('GET CONFIG')
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "CAL")
        global.ser.write(bytes().fromstring("GET CAL\n"))
        mqttprint('GET CAL')
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "MODE")
        global.ser.write(bytes().fromstring("GET MODE\n"))
        mqttprint('GET MODE')
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "TYPE")
        global.ser.write(bytes().fromstring("GET TYPE\n"))
        mqttprint('GET TYPE')
        tasmota.resp_cmnd_done()
        return
    end

    if (argument[0] == "ENERGY")
        global.ser.write(bytes().fromstring("GET ENERGY\n"))
        mqttprint('GET ENERGY')
        tasmota.resp_cmnd_done()
        return
    end

    mqttprint("GET inconnu")
end

def Stm32Reset()
    print("Resetting STM32...")
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

    gpio.pin_mode(global.rx, gpio.INPUT_PULLUP)
    gpio.pin_mode(global.tx, gpio.OUTPUT)
    global.ser = serial(global.rx, global.tx, 115200, serial.SERIAL_8N1)

    gpio.pin_mode(rst, gpio.OUTPUT)
    gpio.pin_mode(bsl, gpio.OUTPUT)
    gpio.digital_write(bsl, 0)
    gpio.digital_write(rst, 1)

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
        tasmota.add_driver(global.pwx12)
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
    var config_file
    var total = ""
    var trouve = false

    print("sendconfig called")
    
    if (global.device == nil || global.ville == nil)
        mqttprint("ERROR: device or ville not initialized (call Init first)")
        tasmota.resp_cmnd("ERROR: device or ville not initialized")
        return
    end
    
    config_file = string.format("p_%s.json", global.ville)
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
        if (key == global.device)
            trouve = true
            var p0 = "1"
            var p1 = "1"
            var p2 = "1"
            var m0 = "tri"
            var m1 = "tri"
            var m2 = "tri"

            if myjson[key].contains("PGA") && myjson[key]["PGA"] != nil
                if size(myjson[key]["PGA"]) > 0 && myjson[key]["PGA"][0] != nil
                    p0 = str(myjson[key]["PGA"][0])
                end
                if size(myjson[key]["PGA"]) > 1 && myjson[key]["PGA"][1] != nil
                    p1 = str(myjson[key]["PGA"][1])
                end
                if size(myjson[key]["PGA"]) > 2 && myjson[key]["PGA"][2] != nil
                    p2 = str(myjson[key]["PGA"][2])
                end
            end

            if myjson[key].contains("mode") && myjson[key]["mode"] != nil
                if type(myjson[key]["mode"]) == "list"
                    if size(myjson[key]["mode"]) > 0 && myjson[key]["mode"][0] != nil
                        m0 = str(myjson[key]["mode"][0])
                    end
                    if size(myjson[key]["mode"]) > 1 && myjson[key]["mode"][1] != nil
                        m1 = str(myjson[key]["mode"][1])
                    end
                    if size(myjson[key]["mode"]) > 2 && myjson[key]["mode"][2] != nil
                        m2 = str(myjson[key]["mode"][2])
                    end
                elif type(myjson[key]["mode"]) == "string"
                    m0 = str(myjson[key]["mode"])
                    m1 = m0
                    m2 = m0
                end
            end

            var r0 = "*"
            var r1 = "*"
            var r2 = "*"
            if myjson[key].contains("root") && myjson[key]["root"] != nil
                if size(myjson[key]["root"]) > 0 && myjson[key]["root"][0] != nil
                    r0 = str(myjson[key]["root"][0])
                end
                if size(myjson[key]["root"]) > 1 && myjson[key]["root"][1] != nil
                    r1 = str(myjson[key]["root"][1])
                end
                if size(myjson[key]["root"]) > 2 && myjson[key]["root"][2] != nil
                    r2 = str(myjson[key]["root"][2])
                end
            end

            var t0 = "ct"
            var t1 = "ct"
            var t2 = "ct"
            if myjson[key].contains("techno") && myjson[key]["techno"] != nil
                if size(myjson[key]["techno"]) > 0 && myjson[key]["techno"][0] != nil
                    t0 = str(myjson[key]["techno"][0])
                end
                if size(myjson[key]["techno"]) > 1 && myjson[key]["techno"][1] != nil
                    t1 = str(myjson[key]["techno"][1])
                end
                if size(myjson[key]["techno"]) > 2 && myjson[key]["techno"][2] != nil
                    t2 = str(myjson[key]["techno"][2])
                end
            end

            var q0 = "1000"
            var q1 = "1000"
            var q2 = "1000"
            if myjson[key].contains("ratio") && myjson[key]["ratio"] != nil
                if size(myjson[key]["ratio"]) > 0 && myjson[key]["ratio"][0] != nil
                    q0 = str(myjson[key]["ratio"][0])
                end
                if size(myjson[key]["ratio"]) > 1 && myjson[key]["ratio"][1] != nil
                    q1 = str(myjson[key]["ratio"][1])
                end
                if size(myjson[key]["ratio"]) > 2 && myjson[key]["ratio"][2] != nil
                    q2 = str(myjson[key]["ratio"][2])
                end
            end

            total = "CONFIG " + key + ":"
                + r0 + ":" + r1 + ":" + r2 + ":"
                + myjson[key]["produit"] + ":"
                + t0 + ":" + t1 + ":" + t2 + ":"
                + q0 + ":" + q1 + ":" + q2 + ":"
                + p0 + ":" + p1 + ":" + p2 + ":"
                + m0 + ":" + m1 + ":" + m2
        end
    end

    if (trouve == true)
        global.ser.flush()
        total = "SET " + total + "\n"
        var mybytes = bytes().fromstring(total)
        global.ser.write(mybytes)
        mqttprint(str(total))
        tasmota.resp_cmnd("config sent")
    else
        mqttprint("device " + str(global.device) + " non trouve")
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
    print("Stm32reset | hold | start | set | get | cal")
    print("Init | getfile | name | sendconfig | h | dir | getversion | update | couts")

    print("[STM32 LINK CONTROL]")
    print("Stm32reset")
    print("hold")
    print("start")

    print("[STM32 SET COMMANDS]")
    print("set MODE CAL <1|2|3>")
    print("set MODE LOG")
    print("set MODE REG")
    print("set TYPE MONO")
    print("set TYPE TRI")
    print("set CONFIG")

    print("[STM32 GET COMMANDS]")
    print("get CAL")
    print("get CONFIG   (query STM32 applied config/register dump)")
    print("get MODE")
    print("get TYPE")
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
    print("sendconfig")
    print("dir")
    print("getversion")
    print("update")
    print("couts")
    print("h")

    print("[NOTES]")
    print("- UART single link on C3: commands and telemetry share same serial")
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
    hold()
    var name = string.format("c_%s.json", global.ville)
    var command = string.format("getfile config/%s", name)
    mqttprint("update: " + command)
    tasmota.cmd(command)
    name = string.format("p_%s.json", global.ville)
    command = string.format("getfile config/%s", name)
    mqttprint("update: " + command)
    tasmota.cmd(command)
    mqttprint("update: getfile pwx12/berry-c3/conso.be")
    tasmota.cmd("getfile pwx12/berry-c3/conso.be")   
    mqttprint("update: getfile flashers/stm32C071-PWX/flasher.be")
    tasmota.cmd("getfile flashers/stm32C071-PWX/flasher.be")
    mqttprint("update: getfile flashers/stm32C071-PWX/intelhex.be")
    tasmota.cmd("getfile flashers/stm32C071-PWX/intelhex.be")
    mqttprint("update: getfile pwx12/berry-c3/pwx12_driver.be")
    tasmota.cmd("getfile pwx12/berry-c3/pwx12_driver.be")
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
tasmota.add_cmd("stm32reset", Stm32Reset)
tasmota.add_cmd("hold", hold)
tasmota.add_cmd("start", start)
tasmota.add_cmd("set", SetCommand)
tasmota.add_cmd("get", GetCommand)
tasmota.add_cmd("cal", Calibration)

# ====================== ESP32 COMMANDS ======================
tasmota.add_cmd("Init", Init)
tasmota.add_cmd("getfile", getfile)
tasmota.add_cmd("name", name)
tasmota.add_cmd("sendconfig", sendconfig)
tasmota.add_cmd("h", help)
tasmota.add_cmd('dir', dir)
tasmota.add_cmd('getversion', getversion)
tasmota.add_cmd('update', update)
tasmota.add_cmd('couts', couts)

############################################################
Init()
tasmota.load("pwx12_driver.be")
