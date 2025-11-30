var version = "1.0.082025 initiale"

import string
import global
import mqtt
import json
import gpio
import path

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
    global.client = myjson["client"]
    global.ville = myjson["ville"]
    global.device = myjson["device"]
    print('esp32.cfg loaded')
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
    myjson["devices"] = device_list
    myjson["nombre"] = size(device_list)
    
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


#-------------------------------- BASH -----------------------------------------#

tasmota.cmd("seriallog 0")
mqttprint("serial log disabled")

mqttprint('AUTOEXEC: create commande getfile')
tasmota.add_cmd('getfile', getfile)

tasmota.add_cmd('dir', dir)
tasmota.add_cmd('ville', ville)
tasmota.add_cmd('device', device)


# Initialize configuration
loadconfig()
mqttprint("ville:" + str(global.ville))
mqttprint("client:" + str(global.client))
mqttprint("device:" + str(global.device))

tasmota.add_cmd('getversion', getversion)
tasmota.add_cmd('get', get)
tasmota.add_cmd('cal', cal)

#-------------------------------- WEB UI -----------------------------------------#

print("Initializing Web UI...")

class WebUI
    def init()
        print("WebUI: init")
    end
    
    def web_add_main_button()
        import webserver
        import global
        
        # Add control form directly on main page
        var html = "<fieldset><legend><b>🎛️ HBS Control Panel</b></legend>"
        html += "<form action='/' method='get'>"
        
        # Location field
        html += "<p><label><b>📍 Location:</b></label><br>"
        html += "<input type='text' name='location' value='" + str(global.ville) + "' style='width:100%;padding:5px'></p>"
        
        # Device field
        html += "<p><label><b>🖥️ Device:</b></label><br>"
        html += "<input type='text' name='device' value='" + str(global.device) + "' style='width:100%;padding:5px'></p>"
        
        # On/Off dropdown
        html += "<p><label><b>🔌 On/Off:</b></label><br>"
        html += "<select name='onoff' style='width:100%;padding:5px'>"
        html += "<option value='0'>0 - Off</option>"
        html += "<option value='1'>1 - On</option>"
        html += "</select></p>"
        
        # Fan Speed dropdown
        html += "<p><label><b>💨 Fan Speed:</b></label><br>"
        html += "<select name='fanspeed' style='width:100%;padding:5px'>"
        html += "<option value='0'>0 - Off</option>"
        html += "<option value='1'>1 - Low</option>"
        html += "<option value='2'>2 - Medium</option>"
        html += "<option value='3'>3 - High</option>"
        html += "<option value='4'>4 - Max</option>"
        html += "<option value='a'>A - Auto</option>"
        html += "</select></p>"
        
        # Louver checkbox and dropdown
        html += "<p><label>"
        html += "<input type='checkbox' id='louver_enable' name='louver_enable' value='1' onchange='document.getElementById(\"louver\").disabled=!this.checked'> "
        html += "<b>📐 Enable Louver Control</b>"
        html += "</label></p>"
        
        html += "<p><label><b>📐 Louver Position:</b></label><br>"
        html += "<select name='louver' id='louver' style='width:100%;padding:5px' disabled>"
        html += "<option value='0'>0</option>"
        html += "<option value='1'>1</option>"
        html += "<option value='2'>2</option>"
        html += "<option value='3'>3</option>"
        html += "<option value='4'>4</option>"
        html += "<option value='5'>5</option>"
        html += "<option value='a'>A - Auto</option>"
        html += "</select></p>"
        
        # Temperature dropdown
        html += "<p><label><b>🌡️ Temperature:</b></label><br>"
        html += "<select name='temperature' style='width:100%;padding:5px'>"
        for temp:17..29
            html += "<option value='" + str(temp) + "'>" + str(temp) + "°C</option>"
        end
        html += "</select></p>"
        
        # Buttons
        html += "<p style='text-align:center'>"
        html += "<button type='submit' name='action' value='start' class='button bgrn'>▶️ START</button> "
        html += "<button type='submit' name='action' value='stop' class='button bred'>⏹️ STOP</button>"
        html += "</p>"
        
        html += "</form></fieldset>"
        
        webserver.content_send(html)
    end
    
    def web_add_handler()
        print("WebUI: Handler registered (no custom pages)")
    end
end

# Create driver instance
web_ui = WebUI()
tasmota.add_driver(web_ui)

print("WebUI: Driver registered")
mqttprint("Web UI initialized")

#-------------------------------- LOGGER -----------------------------------------#

# print("Loading logger.be...")
# load("logger.be")
# print("Logger: Dual UART monitoring active")
