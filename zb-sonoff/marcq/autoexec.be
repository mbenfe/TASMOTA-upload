var version = "1.0.032025 initiale"

import string
import global
import mqtt
import json
import gpio
import path

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client,global.ville, global.device)
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
    global.client = myjson["client"]
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

# Function to launch the driver
def launch_driver()
    mqttprint('mqtt connected -> launch driver')
    tasmota.load('zb_handler.be')
end



#-------------------------------- BASH -----------------------------------------#
tasmota.cmd("seriallog 0")
mqttprint("serial log disabled")

mqttprint('AUTOEXEC: create commande getfile')
tasmota.add_cmd('getfile', getfile)

loadconfig()

mqttprint('load zb_handler.be')
mqttprint('wait for 45 seconds ....')
tasmota.set_timer(45000,launch_driver)

# tasmota.load("supervisor.be")
