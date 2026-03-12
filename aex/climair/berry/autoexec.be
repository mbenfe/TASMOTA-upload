var version = "1.0.082025 initiale"

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
    global.device = myjson["device"]
    print(global.device)
    global.location = myjson["location"]

    global.client = myjson["client"]
    print(global.client)

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
    
    global.config = myjson[global.ville][global.device]
    mqttprint("config: " + str(global.config))
    global.tempsource = []
    global.remote_temp = 99

    if(global.config["remote"] != "nok")
        global.tempsource.push("remote")
        global.remote_temp = 99
    end
    if(global.config["ds"] != "nok")
        global.tempsource.push("ds")
    end
    global.tempsource.push("dsin")

    mqttprint("Available sensors: " + str(global.tempsource))
    mqttprint("source: " + str(global.tempsource))
    print('config.json loaded')

    # initialize calibration
    if (path.exists("calibration.json"))
        file = open("calibration.json", "rt")
        buffer = file.read()
        file.close()
        myjson = json.load(buffer)
        global.dsin_offset = real(myjson["dsin_offset"])
        global.ds_offset = real(myjson["ds_offset"])
    else
        print("calibration.json not found, using default offsets")
        global.dsin_offset = 0
        global.ds_offset = 0
        file = open("calibration.json", "wt")
        myjson = json.dump({"dsin_offset": global.dsin_offset, "ds_offset": global.ds_offset})
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
    file = open("esp32.cfg", "rt")
    buffer = file.read()
    myjson = json.load(buffer)
    myjson["location"] = payload
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
        mqttprint("Error: Invalid arguments for cal command .e.g cal dsin 21 or cal ds 21")
        tasmota.resp_cmnd('Invalid arguments')
        return
    end
    name ="calibration.json"
    file = open(name, "rt")
    myjson = file.read()
    file.close()

    calibration = json.load(myjson)  

    if arguments[0] == 'dsin'
        calibration['dsin_offset'] = real(arguments[1])-global.dsin
        print("dsin_offset: " + str(calibration['dsin_offset']))
    elif arguments[0] == 'ds'
        calibration['ds_offset'] = real(arguments[1])-global.ds
        print("ds_offset: " + str(calibration['ds_offset']))
    else
        mqttprint("Error: Invalid sensor type. Use 'dsin' or 'ds'.")
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
    name ="setup.json"
    file = open(name, "rt")
    myjson = file.read()
    file.close()

    var topic = string.format("gw/%s/%s/%s/setup", global.client, global.ville, global.device)
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

def stop()
    gpio.digital_write(global.relay, 0)
    tasmota.resp_cmnd('stop done')
end

def start()
    gpio.digital_write(global.relay, 1)
    tasmota.resp_cmnd('start done')
end

def launch_driver()
    mqttprint('load climair_driver')
    tasmota.load('climair_driver.be')
    mqttprint('climair_driver loaded')
end

def check_gpio()

    # Check if GPIOs are configured correctly
    var gpio_result = tasmota.cmd("Gpio")
    
    if gpio_result != nil
        # Check GPIO8 (DS18x20-1 - 1312)
        if gpio_result['GPIO8'] != nil
            if !gpio_result['GPIO8'].contains('DS18x201')
                mqttprint("WARNING: GPIO8 not DS18x20-1! Reconfiguring...")
                tasmota.cmd("Gpio8 1312")
            end
        end
        
        # Check GPIO20 (DS18x20-2 - 1313)
        if gpio_result['GPIO20'] != nil
            if !gpio_result['GPIO20'].contains('DS18x202')
                mqttprint("WARNING: GPIO20 not DS18x20-2! Reconfiguring...")
                tasmota.cmd("Gpio20 1313")
            end
        end
    else
        mqttprint("ERROR: Cannot read GPIO configuration")
        return false
    end
    
    return true
end


#-------------------------------- BASH -----------------------------------------#

check_gpio()

tasmota.cmd("seriallog 0")
mqttprint("serial log disabled")

mqttprint('AUTOEXEC: create commande getfile')
tasmota.add_cmd('getfile', getfile)

tasmota.add_cmd('dir', dir)
tasmota.add_cmd('ville', ville)
tasmota.add_cmd('device', device)
tasmota.add_cmd('location', location)
tasmota.add_cmd('stop', stop)
tasmota.add_cmd('start', start)

# Initialize configuration
loadconfig()
mqttprint("ville:" + str(global.ville))
mqttprint("client:" + str(global.client))
mqttprint("device:" + str(global.device))
mqttprint("location:" + str(global.location))

tasmota.add_cmd('getversion', getversion)
tasmota.add_cmd('get', get)
tasmota.add_cmd('cal', cal)

print(" wait 30s for drivers loading")
tasmota.set_timer(30000,launch_driver)