var version = "1.0.112024 initiale"

import string
import global
import mqtt
import json
import gpio
import path

var ser                # serial object
var bsl_out = 32   

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, texte, true)
end

# Define loadconfig function
def loadconfig()
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    file.close()
    var myjson = json.load(buffer)
    global.ville = myjson["ville"]
    global.device = myjson["device"]
    global.nombre = myjson["nombre"]
    global.location = list()
    for i:0..global.nombre-1
        global.location.insert(i,myjson["location"][i])
    end
    global.client = myjson["client"]


    file = open("config.json", "rt")
    if(file == nil)
        mqttprint("Error: Failed to open config.json")
        file.close()
        return
    end
    buffer = file.read()
    file.close()
    myjson = json.load(buffer)
    global.config = myjson[global.ville][global.device]
    mqttprint("config: " + str(global.config))
    if(global.config["pt1"] != "nok")
        global.tempsource = "pt1"
    elif(global.config["pt2"] != "nok")
        global.tempsource = "pt2"
    elif(global.config["ds1"] != "nok")
        global.tempsource = "ds1"
    elif(global.config["ds2"] != "nok")
        global.tempsource = "ds2"
    else
        global.tempsource = "dsin"
    end
end


#-------------------------------- FONCTIONS -----------------------------------------#
# Function to update the city in the configuration file
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

# Function to update the device in the configuration file
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

# Function to update the location in the configuration file
def location(cmd, idx, payload, payload_json)
    import json
    var file
    var buffer
    var myjson
    var arguments
    arguments = string.split(payload, ' ')
    file = open("esp32.cfg", "rt")
    buffer = file.read()
    myjson = json.load(buffer)
    myjson["location"][int(arguments[0])] = arguments[1]
    buffer = json.dump(myjson)
    file.close()
    file = open("esp32.cfg", "wt")
    file.write(buffer)
    file.close()
    tasmota.resp_cmnd('done')
end

# Function to download a file from a URL and save it locally
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

# Function to list files in the root directory and their details
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

# Function to set thermostat parameters
def cal(cmd, idx, payload, payload_json)
    var arguments
    var file 
    var myjson
    var calibration
    var name
    arguments = string.split(payload, ' ')
    name ="calibration.json"
    file = open(name, "rt")
    myjson = file.read()
    file.close()

    calibration = json.load(myjson)  
    if string.tolower(arguments[0]) == "pt1"
        calibration['pt1'] = real(global.average_temperature1)*real(global.factor1)/real(arguments[1])
        print("avg: " + str(global.average_temperature1)," factor: " + str(global.factor1), "calibration: " + str(calibration['pt1']))
        global.factor1 = calibration['pt1']
        print("calibration['pt1'] = " + str(calibration['pt1']))
    elif string.tolower(arguments[0]) == "pt2"
        calibration['pt2'] = real(global.average_temperature2)*real(global.factor2)/real(arguments[1])
        global.factor2 = calibration['pt2']
        print("calibration['pt2'] = " + str(calibration['pt2']))
    end
    var buffer = json.dump(calibration)
    print(buffer)
    file = open(name, "wt")
    file.write(buffer)
    file.close()
    tasmota.resp_cmnd_done()
end

# Function to get thermostat parameters
def get(cmd, idx, payload, payload_json)
    var file
    var myjson
    var name
    name ="thermostat_" + payload + ".json"
    file = open(name, "rt")
    myjson = file.read()
    file.close()

    var topic = string.format("gw/%s/%s/%s/setup", global.client, global.ville, global.device+"_"+payload)
    mqtt.publish(topic, myjson, true)

    tasmota.resp_cmnd('done')
end

# Function to get the version of the files
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
    print("load io driver")
    #mqttprint('load io.be')
    tasmota.load('io.be')
    print("io driver loaded")
end

#-------------------------------- BASH -----------------------------------------#

# tasmota.cmd("seriallog 0")
# mqttprint("serial log disabled")

# mqttprint('AUTOEXEC: create commande getfile')
# tasmota.add_cmd('getfile', getfile)

# tasmota.add_cmd('dir', dir)
# tasmota.add_cmd('ville', ville)
# tasmota.add_cmd('device', device)
# tasmota.add_cmd('location', location)

# # Initialize configuration
# loadconfig()
# mqttprint("ville:" + str(global.ville))
# mqttprint("client:" + str(global.client))
# mqttprint("device:" + str(global.device))
# mqttprint("location:" + str(global.location))

# tasmota.add_cmd('getversion', getversion)
# tasmota.add_cmd('get', get)
# tasmota.add_cmd('cal', cal)


# #mqttprint('load ds18b20.be')
# #tasmota.load('ds18b20.be')
# #mqttprint('load pt1000.be')
# #tasmota.load('pt1000.be')
# #mqttprint('load command.be')
# #tasmota.load('command.be')
# #mqttprint('load aerotherme_driver')
# #tasmota.load('aerotherme_driver.be')

print(" wait 10s for drivers loading")
tasmota.set_timer(10000,launch_driver)

