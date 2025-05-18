var version = "1.0.012025"

import string
import global
import mqtt
import json
import gpio
import path

var rx = 16    
var tx = 17    
var rst = 2   
var bsl = 13   

var device
var ville

#-------------------------------- COMMANDES -----------------------------------------#

def mqttprint(texte)
    import mqtt
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", ville, device)
    mqtt.publish(topic, texte, true)
end

def Calibration(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload), " ")
    if (argument[0] != "VA" && argument[0] != "VB" && argument[0] != "VC" && argument[0] != "IA" && argument[0] != "IB" && argument[0] != "IC" && argument[0] != "IN" 
        || argument[1] == "")
        mqttprint("erreur arguments")
        return
    end
    var token
    if (argument[0] == "VA" || argument[0] == "VB" || argument[0] == "VC")
        token = string.format("CAL %s %s", argument[0], argument[1])
    else
        token = string.format("CAL %s %s %s", argument[0], argument[1], argument[2])
    end
    global.serialSend.flush()
    global.serialSend.write(bytes().fromstring(token))
    mqttprint(token)
    tasmota.resp_cmnd_done()
end

def readcal()
    global.serialSend.flush()
    global.serialSend.write(bytes().fromstring("CAL READ"))
    mqttprint('CAL READ')
    tasmota.resp_cmnd_done()
end

def storecal()
    global.serialSend.flush()
    global.serialSend.write(bytes().fromstring("CAL STORE"))
    mqttprint('CAL STORE')
    tasmota.resp_cmnd_done()
end

def Init()
    gpio.pin_mode(rx, gpio.INPUT)
    gpio.pin_mode(tx, gpio.OUTPUT)
    global.serialSend = serial(rx, tx, 115200, serial.SERIAL_8N1)
    mqttprint('serial initialised')
    tasmota.resp_cmnd_done()
end

def BlReset(cmd, idx, payload, payload_json)
    global.serialSend.flush()
    global.serialSend.write(bytes().fromstring("SET RESET"))
    mqttprint("SET RESET")
    tasmota.resp_cmnd_done()
end

def BlMode(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload)," ")
    if(argument[0]!="CAL" && argument[0] !="LOG" && argument[0] !="REG")
        mqttprint("erreur arguments")
        return
    end
    global.serialSend.flush()
    if (argument[0] == "CAL")
        global.serialSend.write(bytes().fromstring("SET MODE CAL"))
        mqttprint("SET MODE CAL")
    elif(argument[0] == "LOG")
        global.serialSend.write(bytes().fromstring("SET MODE LOG"))
        mqttprint("SET MODE LOG")
    elif (argument[0] == "REG")
        global.serialSend.write(bytes().fromstring("SET MODE REG"))
        mqttprint("SET MODE REG")
    end
    tasmota.resp_cmnd_done()
end

def BlType(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload), ' ')
    if (argument[0] != 'MONO' && argument[0] != 'TRI')
        mqttprint('erreur arguments')
        return
    end
    if (argument[0] == 'MONO')
        global.serialSend.write(bytes().fromstring('SET TYPE MONO'))
    else
        global.serialSend.write(bytes().fromstring('SET TYPE TRI'))
    end
    tasmota.delay(500)
    tasmota.resp_cmnd_done()
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

def ville(cmd, idx, payload, payload_json)
    import json
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    var myjson = json.load(buffer)
    myjson["ville"] = payload
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

    mqttprint(nom_fichier)
    var filepath = 'https://raw.githubusercontent.com/mbenfe/upload/main/' + payload
    mqttprint(filepath)

    var wc = webclient()
    if (wc == nil)
        mqttprint("Erreur: impossible d'initialiser le client web")
        tasmota.resp_cmnd("Erreur d'initialisation du client web.")
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
        return
    end

    var bytes_written = wc.write_file(nom_fichier)
    wc.close()
    mqttprint('Fetched ' + str(bytes_written))
    message = 'uploaded:' + nom_fichier
    tasmota.resp_cmnd(message)
    return st
end

def sendconfig(cmd, idx, payload, payload_json)
    import string
    import json
    var file
    var buffer
    var myjson
    var device
    var total = ""
    var header
    var trouve = false
    mqttprint("send:" + payload)
    ############################ fichier config ###################
    file = open("esp32.cfg", "rt")
    buffer = file.read()
    myjson = json.load(buffer)
    device = myjson["device"]
    file.close()

    file = open(payload, "rt")
    if (file == nil)
        mqttprint("fichier non existant:" + payload)
        return
    end
    buffer = file.read()
    file.close()
    myjson = json.load(buffer)
    for key:myjson.keys()
        if (key == device)
            trouve = true
             total+='CONFIG'+' '+key+'_'+myjson[key]["root"][0]+'_'+myjson[key]["produit"]+'_'+myjson[key]["techno"][0]+'_'+str(myjson[key]["ratio"][0])
             mqttprint(str(total))
        end
    end
    if (trouve == true)
        global.serialSend.flush()
        var mybytes = bytes().fromstring(total)
        global.serialSend.write(mybytes)
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
    mqttprint("Stm32reset:reset du STM32")
    mqttprint("getfile <path/filename>: load file")
    mqttprint("sendconfig p_<name>.json: configure pwx")
    mqttprint("ville <nom>: set ville")
    mqttprint("device <nom>: set device name")
    mqttprint("BlReset: reset the BL6552 chip")
    mqttprint("BlMode <mode> (cal ou log): set mode ")
    mqttprint("Init", Init)
    mqttprint("cal <parameter> <value> (VA, VB ou VC)")
    mqttprint("ex: cal VA 235")
    mqttprint("cal <device> <parameter> <value> (IA, IB ou IC)")
    mqttprint("ex: cal IA 1 5.1")
    mqttprint("readcal: affiche les parametres de calibration")
    mqttprint("storecal: sauvegarde la calibration")
    mqttprint("h: this help")
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

tasmota.cmd("seriallog 0")
print("serial log disabled")
tasmota.cmd("Teleperiod 0")
print("teleperiod set")


tasmota.add_cmd("Stm32reset", Stm32Reset)
tasmota.add_cmd("getfile", getfile)
tasmota.add_cmd("sendconfig", sendconfig)
tasmota.add_cmd("ville", ville)
tasmota.add_cmd("device", device)
tasmota.add_cmd("name", name)
tasmota.add_cmd("BlReset", BlReset)
tasmota.add_cmd("BlMode", BlMode)
tasmota.add_cmd("Init", Init)
tasmota.add_cmd("cal", Calibration)
tasmota.add_cmd("readcal", readcal)
tasmota.add_cmd("storecal", storecal)
tasmota.add_cmd("h", help)
tasmota.add_cmd('dir', dir)
tasmota.add_cmd('getversion', getversion)

############################################################
tasmota.cmd("Init")
tasmota.delay(500)
tasmota.load("pwx4_build_driver.be")