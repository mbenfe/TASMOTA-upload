# IO9 1W out (external DS18B20 #1)
# IO21 Marche
# IO20 Arret
# IO6  Chauffage
# IO7 Ventillation
# IO18 Relay 2
# IO19 Relay 1


import mqtt
import string
import json
import global


def mqttprint(texte)
    var payload =string.format("{\"texte\":\"%s\"}", texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, payload, true)
    return true
end

def get_cron_second()
    # Hash FNV-1a 32 bits, bonne dispersion, déterministe
    var combined = string.format("%s|%s", global.ville, global.device)

    var hash = 2166136261  # offset basis FNV-1a 32-bit

    for i : 0 .. size(combined) - 1
        var val = string.byte(combined, i)
        hash = (hash ^ val) & 0xFFFFFFFF
        hash = (hash * 16777619) & 0xFFFFFFFF
    end

    # Petit "finalizer" pour améliorer la diffusion avant modulo 60
    hash = (hash ^ (hash >> 16)) & 0xFFFFFFFF

    return hash % 60
end

class AEROTHERME
    var day_list
    var count

    def poll()
        global.temperature = 99
        global.dsin = 99
        var data = tasmota.read_sensors()
        if(data == nil)
            return 99
        end
        var myjson = json.load(data)
        if(myjson.contains("DS18B20"))
            global.dsin = myjson["DS18B20"]["Temperature"]
        end

        global.temperature = global.dsin + global.dsin_offset
    end


    def check_gpio()
        # Check if GPIOs are configured correctly for DS18B20
        var gpio_result = tasmota.cmd("Gpio")
        
        if gpio_result != nil
            # Check GPIO9 (DS18x20-1 - 1312)
            if gpio_result['GPIO9'] != nil
                if !gpio_result['GPIO9'].contains('1312')
                    mqttprint("WARNING: GPIO9 not DS18x20-1! Reconfiguring...")
                    tasmota.cmd("Gpio9 1312")
                end
            end
        else
            mqttprint("ERROR: Cannot read GPIO configuration")
            return false
        end
        
        return true
    end

    def acknowledge_mysetup(topic, idx, payload_s, payload_b)
        print("debug: function acknowledge_mysetup() started")
        var myjson = json.load(payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            print("debug: function acknowledge_mysetup() ended with error myjson==nil")
            return
        end
        var newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)

        global.setup['onoff'] = myjson['DATA']['onoff']
        # attention ne pas changer offset !!!!!!!!
        global.setup['ouvert'] = myjson['DATA']['ouvert']
        global.setup['ferme'] = myjson['DATA']['ferme']
        global.setup['lundi'] = myjson['DATA']['lundi']
        global.setup['mardi'] = myjson['DATA']['mardi']
        global.setup['mercredi'] = myjson['DATA']['mercredi']
        global.setup['jeudi'] = myjson['DATA']['jeudi']
        global.setup['vendredi'] = myjson['DATA']['vendredi']
        global.setup['samedi'] = myjson['DATA']['samedi']
        global.setup['dimanche'] = myjson['DATA']['dimanche']
       
        var buffer = json.dump(global.setup)
        var file = open("setup.json", "wt")
        if file == nil
            mqttprint("Error: Failed to open setup.json for writing")
            print("debug: function acknowledge_mysetup() ended with error file==nil")
            return
        end
        file.write(buffer)
        file.close()
        
        var payload = string.format('{"Device":"%s","Name":"setup","TYPE":"SETUP","DATA":%s}', 
        global.device, buffer)
        mqtt.publish(newtopic, payload, true)
        tasmota.delay(5)

        # payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"ouvert":%.1f,"ferme":%.1f,"offset":%.1f,"location":"%s","Target":%.1f,"source":"%s","Power":%d,"onoff":%d,"Marche":%d}', 
        #     global.device, global.device, global.temperature-global.setup['offset'], global.setup['ouvert'], global.setup['ferme'], global.setup['offset'], global.location, global.target, global.tempsource[0], global.power, global.setup['onoff'], gpio.digital_read(global.io_marche))
        # newtopic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        # mqtt.publish(newtopic, payload, true)
        self.every_minute()
        print("debug: function acknowledge_mysetup() ended successfully")
    end

    # Initialization function
    def init()
        var file
        var myjson        
        global.temperature = 99
        global.target = 0
        file = open("setup.json", "rt")
        if file == nil
            mqttprint("Error: Failed to open setup.json")
            return
        end
        myjson = file.read()
        file.close()
        global.setup = json.load(myjson)
        if global.setup == nil
            mqttprint("Error: Failed to parse setup.json")
            return
        end
        print(global.setup)
        
        self.day_list = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
        mqttprint("subscription MQTT...")
        self.subscribes()
        mqttprint('MQTT subscription done')
        
        # Configure relay outputs
        global.relay1 = 19
        global.relay2 = 18
        gpio.pin_mode(global.relay1, gpio.OUTPUT)
        gpio.pin_mode(global.relay2, gpio.OUTPUT)
        gpio.digital_write(global.relay1, 0)  # Set relay 1 to OFF
        gpio.digital_write(global.relay2, 0)  # Set relay 2 to OFF
        
        # Configure IO inputs
        global.io_marche = 21
        global.io_arret = 20
        global.io_chauffage = 6
        global.io_ventilation = 7
        gpio.pin_mode(global.io_marche, gpio.INPUT)
        gpio.pin_mode(global.io_arret, gpio.INPUT)
        gpio.pin_mode(global.io_chauffage, gpio.INPUT)
        gpio.pin_mode(global.io_ventilation, gpio.INPUT)

        print(" Marche : " + str(global.io_marche))
        print(" Arret : " + str(global.io_arret))
        print(" Chauffage : " + str(global.io_chauffage))
        print(" Ventilation : " + str(global.io_ventilation))
        
        tasmota.set_timer(30000,/-> self.send_stored_setup())

        if(global.config["remote"] != "nok")
            self.subscribes_sensors(global.config["remote"])  # Subscribe to remote sensor topic
        end
    end

    # Poll IO inputs every 250ms and control relays accordingly
    def every_second()
        var marche = gpio.digital_read(global.io_marche)
        var arret = gpio.digital_read(global.io_arret)
        var chauffage = gpio.digital_read(global.io_chauffage)
        var ventilation = gpio.digital_read(global.io_ventilation)
        
        if arret == 1
            # Stop: both relays OFF
            gpio.digital_write(global.relay1, 0)  # Relay 1 OFF
            gpio.digital_write(global.relay2, 0)  # Relay 2 OFF
        elif marche == 1 && global.power == 1 && global.setup['onoff'] == 1
            # Start: both relays ON
            gpio.digital_write(global.relay1, 1)  # Relay 1 ON
            gpio.digital_write(global.relay2, 1)  # Relay 2 ON
        elif chauffage == 1
            # Heating: Relay 1 OFF, Relay 2 ON
            gpio.digital_write(global.relay1, 0)  # Relay 1 OFF
            gpio.digital_write(global.relay2, 1)  # Relay 2 ON
        elif ventilation == 1
            # Ventilation: Relay 1 ON, Relay 2 OFF
            gpio.digital_write(global.relay1, 1)  # Relay 1 ON
            gpio.digital_write(global.relay2, 0)  # Relay 2 OFF
        end
    end

    def send_stored_setup()
        var file
        var myjson        
        file = open("setup.json", "rt")
        if file == nil
            mqttprint("Error: Failed to open setup.json")
            return
        end
        myjson = file.read()
        file.close()
        var newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        var payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}',
                global.device, global.device, myjson)
        mqtt.publish(newtopic, payload, true)
    end

    # Function to subscribe to MQTT topics
    def subscribes()
        var topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.acknowledge_mysetup(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to SETUP: " + global.device)
    end

    # Function to execute every minute
    def every_minute()
        var now = tasmota.rtc()
        var rtc = tasmota.time_dump(now["local"])
        var hour = rtc["hour"]
        var day_of_week = rtc["weekday"]  # 0=Sunday, 1=Monday, ..., 6=Saturday
        var jour = self.day_list[day_of_week]

        var payload
        var topic

        self.check_gpio()

        # Check if any IO input is active - if so, IO mode takes precedence
        var marche = gpio.digital_read(global.io_marche)
        var arret = gpio.digital_read(global.io_arret)
        var chauffage = gpio.digital_read(global.io_chauffage)
        var ventilation = gpio.digital_read(global.io_ventilation)
                
        if marche == 1
            # No IO input active - use scheduled temperature control
            if(global.tempsource[0] == "ds")
                self.poll("ds")
            elif(global.tempsource[0] == "dsin")
                self.poll("dsin")
            elif(global.tempsource[0] == "pt")
                global.temperature = global.average_temperature
            elif(global.tempsource[0] == "remote")
                global.temperature = global.remote_temp[0]
            else
                global.temperature = 99
            end

            if (hour >= global.setup[jour]['debut'] && hour < global.setup[jour]['fin'])
                global.target = global.setup['ouvert']
                if (global.temperature < global.target && global.setup['onoff'] == 1)
                    gpio.digital_write(global.relay1, 1)
                    gpio.digital_write(global.relay2, 1)
                    global.power = 1
                else
                    gpio.digital_write(global.relay1, 0)
                    gpio.digital_write(global.relay2, 0)
                    global.power = 0
                end
            else
                global.target = global.setup['ferme']
                if (global.temperature < global.target && global.setup['onoff'] == 1)
                    gpio.digital_write(global.relay1, 1)
                    gpio.digital_write(global.relay2, 1)
                    global.power = 1
                else
                    gpio.digital_write(global.relay1, 0)
                    global.power = 0
                end
            end
        end

        payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"ouvert":%.1f,"ferme":%.1f,"offset":%.1f,"location":"%s","Target":%.1f,"source":"%s","Power":%d,"onoff":%d,"Marche":%d}', 
            global.device, global.device, global.temperature-global.setup['offset'], global.setup['ouvert'], global.setup['ferme'], global.setup['offset'], global.location, global.target, global.tempsource[0], global.power, global.setup['onoff'], gpio.digital_read(global.io_marche))
        topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        mqtt.publish(topic, payload, true)
    end


    def remote_sensor(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        print("remote sensor data received: " + payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end
        if myjson.contains("Temperature")
            global.remote_temp[0] = real(myjson["Temperature"])
        else
            mqttprint("Error: Temperature data not found in payload")
        end
    end
    # Function to subscribe to MQTT topics
    def subscribes_sensors(sensor)
        var topic
        topic = string.format("gw/%s/%s/zb-%s/tele/SENSOR", global.client, global.ville, sensor)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.remote_sensor(topic, idx, payload_s, payload_b))
        print("subscribed to remote sensor:" + topic)
    end
    

end

var aerotherme = AEROTHERME()
global.aerotherme = aerotherme  # Add this line to make aerotherme accessible globally
tasmota.add_driver(aerotherme)

# Calculate cron second from device identity to distribute polling
var cron_second = get_cron_second()
print("Cron second for device " + global.device + " is " + str(cron_second))
var cron_pattern = string.format("%d * * * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> aerotherme.every_minute(), "every_min_@0_s")