var version = "1.0.082025 initiale"

# template  {"NAME":"Frico","GPIO":[1,1,1,1,1,1,1,640,608,1,1,1,1,1,1,1,1,1,609,641,1,1],"FLAG":0,"BASE":1}
# IO7 ds18b20 out
# IO8 SDA
# IO18 SCL
# IO19 ds18b20 in

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
    var payload =string.format("{\"texte\":\"%s\"}", texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, payload, true)
end


# Define loadconfig function
def loadconfig()
    print("loading esp32.cfg")
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    file.close()
    var myjson = json.load(buffer)
    global.ville = myjson["ville"]
    print(myjson["device"])
    global.device = myjson["device"]  # Changed from "devices" to "device"
    global.location = myjson["location"]
     
    global.client = myjson["client"]
    
    print('esp32.cfg loaded')

    print('loading config.json')
    
    file = open("config.json", "rt")
    if(file == nil)
        mqttprint("Error: Failed to open config.json")
        file.close()
        return
    end
    buffer = file.read()
    file.close()
    myjson = json.load(buffer)
    
    # Create config list based on nombre
    global.config = myjson[global.ville][global.device]
    global.remote_temp=(99)  # Initialize remote temperature to 99
    global.config=myjson[global.ville][global.device]
    mqttprint("config:" + str(global.config))
        
    # Add sensors to flat list if available (dsin will be added last)
    global.tempsource = []
    if(global.config["remote"] != "nok")
        global.tempsource.push("remote")
        global.remote_temp = 99
    end
    if(global.config["pt"] != "nok")
        global.tempsource.push("pt")
    end
    if(global.config["ds"] != "nok")
        global.tempsource.push("ds")
    end
        
    # Always add dsin at the end
    global.tempsource.push("dsin")    
    

    mqttprint("Available sensors: " + str(global.tempsource))
  
    print('config.json loaded')

    # initialize calibration
    if (path.exists("calibration.json"))
        file = open("calibration.json", "rt")
        buffer = file.read()
        file.close()
        myjson = json.load(buffer)
        global.factor = real(myjson["pt"])
        global.dsin_offset = real(myjson["dsin_offset"])
        global.ds_offset = real(myjson["ds_offset"])
    else
        print("calibration.json not found, using default factors")
        global.factor = 150
        global.dsin_offset = 0
        global.ds_offset = 0
        file = open("calibration.json", "wt")
        myjson = json.dump({"pt": global.factor, "dsin_offset": global.dsin_offset})
        file.write(myjson)
        file.close()
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
    
    # Parse payload as space-separated list of devices
    var device_list = string.split(payload, ' ')
    myjson["devices"] = device_list  # Changed from "device" to "devices"
    myjson["nombre"] = size(device_list)  # Update nombre automatically
    
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
    if size(arguments) < 2
        mqttprint("Error: Invalid arguments for cal command .e.g cal pt 21 or cal dsin 21")
        tasmota.resp_cmnd('Invalid arguments')
        return
    end
    name ="calibration.json"
    file = open(name, "rt")
    myjson = file.read()
    file.close()

    calibration = json.load(myjson)  

    if arguments[0] == 'pt'
        calibration['pt'] = real(global.average_temperature)*real(global.factor)/real(arguments[1])
        print("avg: " + str(global.average_temperature)," factor: " + str(global.factor), "calibration: " + str(calibration['pt']))
        global.factor = calibration['pt']
        print("calibration['pt'] = " + str(calibration['pt']))
    elif arguments[0] == 'dsin'
        calibration['dsin_offset'] = real(arguments[1])-global.dsin
        print("dsin_offset: " + str(calibration['dsin_offset']))
    elif arguments[0] == 'ds'
        calibration['ds_offset'] = real(arguments[1])-global.ds
        print("ds_offset: " + str(calibration['ds_offset']))
    else
        mqttprint("Error: Invalid sensor type. Use 'pt' or 'dsin'.")
        tasmota.resp_cmnd('Invalid sensor type')
        return
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
    name ="setup_" + payload + ".json"
    file = open(name, "rt")
    myjson = file.read()
    file.close()

    var topic = string.format("gw/%s/%s/%s/setup", global.client, global.ville, global.esp_device+"_"+payload)
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

    mqttprint('load io.be')
    tasmota.load('io.be')
    mqttprint('io driver loaded')

    mqttprint('load ds18b20.be')
    tasmota.load('ds18b20.be')
    mqttprint('ds18b20 driver loaded')

    mqttprint('load frico_driver.be')
    tasmota.load("frico_driver.be")
    mqttprint('frico driver loaded')

end



#-------------------------------- BASH -----------------------------------------#

tasmota.cmd("seriallog 0")
mqttprint("serial log disabled")

mqttprint('AUTOEXEC: create commande getfile')
tasmota.add_cmd('getfile', getfile)

tasmota.add_cmd('dir', dir)
tasmota.add_cmd('ville', ville)
tasmota.add_cmd('device', device)
tasmota.add_cmd('location', location)

# Initialize configuration
loadconfig()
mqttprint("ville:" + str(global.ville))
mqttprint("client:" + str(global.client))
mqttprint("device:" + str(global.device))
mqttprint("location:" + str(global.location))

tasmota.add_cmd('getversion', getversion)
tasmota.add_cmd('get', get)
tasmota.add_cmd('cal', cal)

# Set DS18B20 sensor reading interval to 60 seconds (instead of default 300 seconds)
tasmota.cmd("TelePeriod 60")
tasmota.cmd("MqttLog 0")
mqttprint("DS18B20 sensor reading interval set to 60 seconds")
mqttprint("Automatic MQTT telemetry disabled, Berry MQTT still active")

print(" wait 10s for drivers loading")
tasmota.set_timer(10000,launch_driver)