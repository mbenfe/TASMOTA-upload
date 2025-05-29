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
    tasmota.resp_cmnd('done')
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
    tasmota.resp_cmnd('done')
end

def location(cmd, idx, payload, payload_json)
    import json
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    var myjson = json.load(buffer)
    myjson["location"] = payload
    buffer = json.dump(myjson)
    file.close()
    file = open("esp32.cfg", "wt")
    file.write(buffer)
    file.close()
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

def launch_driver()
    mqttprint('mqtt connected -> launch driver')
    tasmota.add_cmd('getfile', getfile)
    tasmota.add_cmd('dir', dir)
    tasmota.add_cmd('ville', ville)
    tasmota.add_cmd('device', device)
    tasmota.add_cmd('location', location)
    tasmota.add_cmd('getversion', getversion)
    tasmota.add_cmd('get', get)
    tasmota.add_cmd('set', set)


    # Initialize configuration
    loadconfig()
    mqttprint("ville:" + str(global.ville))
    mqttprint("client:" + str(global.client))
    mqttprint("device:" + str(global.device))
    mqttprint("location:" + str(global.location))


    mqttprint('load command.be')
    tasmota.load('command.be')
    tasmota.load('chx_driver.be')
end

#-------------------------------- BASH -----------------------------------------#
tasmota.cmd("seriallog 0")
# tasmota.cmd("i2cdriver12 0")
if(!mqtt.connected())
    print("MQTT not connected...")
else
    print("MQTT connected...")
end

tasmota.set_timer(10000,launch_driver)
