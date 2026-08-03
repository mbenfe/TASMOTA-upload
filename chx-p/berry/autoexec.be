var version = "1.0.112024 initiale"

import string
import global
import mqtt
import json
import gpio
import path

var ser                # serial object
var bsl_out = 32   

# Define loadconfig function
def loadconfig()
    print("loadconfig")
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    file.close()
    var myjson = json.load(buffer)
    global.ville = myjson["ville"]
    global.device = myjson["device"]
    global.location = myjson["location"]
    global.client = myjson["client"]
end

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client,global.ville, global.device)
    mqtt.publish(topic, texte, true)
end

#-------------------------------- FONCTIONS -----------------------------------------#

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

def set(cmd, idx, payload, payload_json)
    var arguments = string.split(payload, ' ')
    var file = open("setup_device.json", "rt")
    var myjson = file.read()
    file.close()
    var thermostat = json.load(myjson)  
    if arguments[0] == "mode"
        thermostat['mode'] = arguments[1]
    elif arguments[0] == "offset"
        thermostat['offset'] = real(arguments[1])
    elif arguments[0] == "semaine"
        thermostat['semaine']['matin'] = real(arguments[1])
        thermostat['semaine']['journee'] = real(arguments[2])
        thermostat['semaine']['soir'] = real(arguments[3])
        thermostat['semaine']['nuit'] = real(arguments[4])
    elif arguments[0] == "weekend"
        thermostat['weekend']['matin'] = real(arguments[1])
        thermostat['weekend']['journee'] = real(arguments[2])
        thermostat['weekend']['soir'] = real(arguments[3])
        thermostat['weekend']['nuit'] = real(arguments[4])
    elif arguments[0] == "absence"
        thermostat['absence']['temperature'] = real(arguments[1])
        thermostat['absence']['humidite'] = real(arguments[2])
    end
    var buffer = json.dump(thermostat)
    file = open("setup_device.json", "wt")
    file.write(buffer)
    file.close()

    var topic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
    mqtt.publish(topic, buffer, true)

    tasmota.resp_cmnd('done')
    tasmota.cmd("restart 1")
end

def get(cmd, idx, payload, payload_json)
    var file = open("setup_device.json", "rt")
    var myjson = file.read()
    file.close()

    var topic = string.format("gw/%s/%s/%s/setup", global.client, global.ville, global.device)
    mqtt.publish(topic, myjson, true)

    tasmota.resp_cmnd('done')
end


def getversion()
    var fichier
    var files = path.listdir("/")
    for i:0..files.size()-1
        if string.endswith(files[i], ".be")
            fichier = open(files[i], "r")
            var content = fichier.readline()
            var version_match = string.find(content, 'var version')
            if version_match != -1
                var liste = string.split(content, ' ')
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
        to_fetch.push("chx-p/berry/autoexec.be")
        to_fetch.push("chx-p/berry/chx_driver.be")
        to_fetch.push("chx-p/berry/conso.be")
    end

    if want_json
        var name = string.format("c_%s.json", global.ville)
        to_fetch.push(string.format("config/%s", name))
        to_fetch.push("chx-p/config/setup_device.json")
        to_fetch.push("chx-p/config/setup_general.json")
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
    mqttprint("CHX-P command help")
    mqttprint("--- Script commands (autoexec.be) ---")
    mqttprint("getfile <repo/path/file> : download from mbenfe/upload to local FS")
    mqttprint("update [all|*.be|*.json] : batch refresh script/json files")
    mqttprint("help : print this command summary")
    mqttprint("--- Driver 133 commands (xdrv_133_chx_p.ino) ---")
    mqttprint("get : publish current setup_device.json to gw/<client>/<ville>/<device>/setup")
    mqttprint("set mode <AUTO|ABSENCE|MANUEL>")
    mqttprint("set offset <value>")
    mqttprint("save <0|1> : 1 enables low-power run mode with WiFi duty cycle (ON 20s / OFF 100s)")
    mqttprint("set semaine <matin> <journee> <soir> <nuit>")
    mqttprint("set weekend <matin> <journee> <soir> <nuit>")
    mqttprint("getversion : list .be versions detected on filesystem")
    mqttprint("--- Ownership split ---")
    mqttprint("script owns: getfile, update, help")
    mqttprint("driver owns: get, set, getversion, save")
    mqttprint("network-required while save=1: upgrade, update, getfile, mqtt publishes")
    mqttprint("when WiFi is OFF, these wait/fail until wake window; use save 0 for continuous network")
    tasmota.resp_cmnd_done()
end

def launch_driver()
    # Initialize configuration before any MQTT publish that uses global values.
    loadconfig()
    mqttprint('mqtt connected -> launch driver')
    tasmota.add_cmd('getfile', / cmd, idx, payload, payload_json -> getfile(cmd, idx, payload, payload_json))
    tasmota.add_cmd('update', / cmd, idx, payload, payload_json -> update(cmd, idx, payload, payload_json))
    tasmota.add_cmd('help', / cmd, idx, payload, payload_json -> help(cmd, idx, payload, payload_json))

    mqttprint("ville:" + str(global.ville))
    mqttprint("client:" + str(global.client))
    mqttprint("device:" + str(global.device))
    mqttprint("location:" + str(global.location))

    mqttprint('Driver 133 runtime active (chx_driver.be disabled)')
end

#-------------------------------- BASH -----------------------------------------#
tasmota.cmd("timezone 99")
tasmota.cmd("seriallog 0")

if(!mqtt.connected())
    print("MQTT not connected...")
else
    print("MQTT connected...")
end

tasmota.set_timer(10000,launch_driver)
