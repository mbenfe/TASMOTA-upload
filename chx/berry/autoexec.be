var version = "2.1.082026 chx script commands"

import string
import global
import mqtt
import json
import path

var ser                # serial object
var bsl_out = 32

def loadconfig()
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    file.close()
    var myjson = json.load(buffer)
    global.ville = myjson["ville"]
    global.device = myjson["device"]
    global.location = myjson["location"]
    global.client = myjson["client"]
end

def mqttprint(texte)
    var topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
    mqtt.publish(topic, texte, true)
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
        tasmota.resp_cmnd("Erreur d'initialisation du client web.")
        return
    end

    wc.set_follow_redirects(true)
    wc.begin(filepath)
    var st = wc.GET()
    if (st != 200)
        message = "Erreur: code HTTP " + str(st)
        mqttprint(message)
        tasmota.resp_cmnd("Erreur de telechargement.")
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

def update(cmd, idx, payload, payload_json)
    var selector = ""
    if payload != nil
        selector = string.tolower(payload)
    end

    var want_all = (selector == "" || selector == "*.*" || selector == "all")
    var want_be = (want_all || selector == "*.be" || selector == ".be" || selector == "be")
    var want_json = (want_all || selector == "*.json" || selector == ".json" || selector == "json")

    if !want_be && !want_json
        mqttprint("update: unknown filter '" + selector + "' (use *.be|*.json)")
        tasmota.resp_cmnd("invalid update filter")
        return
    end

    var to_fetch = []
    if want_be
        to_fetch.push("chx/berry/autoexec.be")
    end

    if want_json
        to_fetch.push("chx/config/thermostat_intermarche.json")
    end

    mqttprint("update: start")
    mqttprint("update: filter='" + selector + "' files=" + str(to_fetch.size()))
    for i:0..to_fetch.size()-1
        var file_to_fetch = to_fetch[i]
        mqttprint("update: getfile " + file_to_fetch)
        tasmota.cmd("getfile " + file_to_fetch)
    end

    mqttprint("update: done")
    tasmota.resp_cmnd('{"Update":"Done"}')
end

def help(cmd, idx, payload, payload_json)
    mqttprint("CHX command help")
    mqttprint("--- Script commands (autoexec.be) ---")
    mqttprint("getfile <repo/path/file> : download from mbenfe/upload to local FS")
    mqttprint("update [all|*.be|*.json] : refresh script/json files")
    mqttprint("help : print this command summary")
    mqttprint("--- Driver 135 commands (xdrv_135_chx.ino) ---")
    mqttprint("getversion : list .be versions detected on filesystem")
    mqttprint("set mode <AUTO|ABSENCE|MANUEL>")
    mqttprint("set offset <value>")
    mqttprint("set semaine <matin> <journee> <soir> <nuit>")
    mqttprint("set weekend <matin> <journee> <soir> <nuit>")
    mqttprint("setup <json> : update setup payload")
    mqttprint("note: get command is removed")
    tasmota.resp_cmnd_done()
end

def launch_driver()
    loadconfig()
    mqttprint('mqtt connected -> launch script commands')
    tasmota.add_cmd('getfile', / cmd, idx, payload, payload_json -> getfile(cmd, idx, payload, payload_json))
    tasmota.add_cmd('update', / cmd, idx, payload, payload_json -> update(cmd, idx, payload, payload_json))
    tasmota.add_cmd('help', / cmd, idx, payload, payload_json -> help(cmd, idx, payload, payload_json))

    mqttprint("ville:" + str(global.ville))
    mqttprint("client:" + str(global.client))
    mqttprint("device:" + str(global.device))
    mqttprint("location:" + str(global.location))
end

tasmota.cmd("timezone 99")
tasmota.cmd("seriallog 0")
tasmota.cmd("setoption146 1")
tasmota.cmd("sleep 120")

if(!mqtt.connected())
    print("MQTT not connected...")
else
    print("MQTT connected...")
end

tasmota.set_timer(10000,launch_driver)

