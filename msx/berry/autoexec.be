var version = "1.0.042025 initial"

import string
import global
import mqtt
import json
import gpio
import path  

#-------------------------------- COMMANDES -----------------------------------------#
def loadconfig()
    import json
    var jsonstring
    var file 
    file = open("esp32.cfg", "rt")
    if file.size() == 0
        print('create esp32 config file')
        file = open("esp32.cfg", "wt")
        jsonstring = string.format("{\"ville\":\"unknown\",\"client\":\"inter\",\"device\":\"unknown\"}")
        file.write(jsonstring)
        file.close()
        file = open("esp32.cfg", "rt")
    end
    var buffer = file.read()
    var jsonmap = json.load(buffer)
    global.client = jsonmap["client"]
    print('client:', global.client)
    global.ville = jsonmap["ville"]
    print('ville:', global.ville)
    global.device = jsonmap["device"]
    print('device:', global.device)
end

def mqttprint(texte)
    import mqtt
    var topic = string.format("gw/inter/%s/%s/tele/PRINT",global.ville,global.device)
    mqtt.publish(topic,texte,true)
end


def ville(cmd, idx,payload, payload_json)
    import json
    var file = open("esp32.cfg","rt")
    var buffer = file.read()
    var myjson=json.load(buffer)
    myjson["ville"]=payload
    buffer = json.dump(myjson)
    file.close()
    file = open("esp32.cfg","wt")
    file.write(buffer)
    file.close()
    tasmota.resp_cmnd("done")
end

def device(cmd, idx,payload, payload_json)
    import json
    var file = open("esp32.cfg","rt")
    var buffer = file.read()
    var myjson=json.load(buffer)
    myjson["device"]=payload
    buffer = json.dump(myjson)
    file.close()
    file = open("esp32.cfg","wt")
    file.write(buffer)
    file.close()
    tasmota.resp_cmnd("done")
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

def dir(cmd, idx,payload, payload_json)
    import path
    var liste
    var file
    var taille
    var date
    var timestamp
    liste = path.listdir("/")
    mqttprint(str(liste.size())+" fichiers")
    for i:0..(liste.size()-1)
        file = open(liste[i],"r")
        taille = file.size()
        file.close()
        timestamp = path.last_modified(liste[i])
        mqttprint(liste[i]+' '+tasmota.time_str(timestamp)+' '+str(taille))
    end
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
    print("mise a jour des fichier")
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    var myjson = json.load(buffer)
    var ville = myjson["ville"]
    var name = string.format("c_%s.json", ville)
    file.close()
    var command = string.format("getfile config/%s", name)
    print(command)
    tasmota.cmd(command)
    tasmota.resp_cmnd_done()
    command = "getfile msx/berry/autoexec.be"
    print(command)
    tasmota.cmd(command)
    tasmota.resp_cmnd_done()
    command = "getfile msx/berry/msx_driver.be"
    print(command)
    tasmota.cmd(command)
    tasmota.resp_cmnd_done()
    command = "getfile msx/berry/conso.be"
    print(command)
    tasmota.cmd(command)    
    tasmota.resp_cmnd_done()
end

def couts()
    tasmota.cmd("br import conso as c; c.mqtt_publish('all')")
    tasmota.resp_cmnd_done()
end

#---------------------------------- SCRIPT --------------------------------------------#
print("MSX : autoexec.be")
print("MSX Driver version: " + version)

loadconfig()
mqttprint("ville:" + str(global.ville))
mqttprint("client:" + str(global.client))
mqttprint("device:" + str(global.device))

tasmota.add_cmd("getfile", getfile)
print("add command getfile")
tasmota.add_cmd('dir', dir)
print("add command dir")
tasmota.add_cmd('getversion', getversion)
print("add command getversion")
tasmota.add_cmd('update', update)
print("add command update")
tasmota.add_cmd('couts', couts)
print("add command couts")
tasmota.add_cmd('mqttprint', mqttprint)
print("add command mqttprint")
tasmota.add_cmd("device", device)
print("add command device")
tasmota.add_cmd("ville", ville)
print("add command ville")

############################################################
print("load MSX Driver")
tasmota.load("msx_driver.be")

