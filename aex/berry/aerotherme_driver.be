import mqtt
import string
import json
import global

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, texte, true)
    return true
end

class AEROTHERME
    var ds18b20
    var relay
    var day_list
    var thermostat
    var count

    # Function to handle ON/OFF commands
    def onoff(topic, idx, payload_s, payload_b)
        var arguments = string.split(topic, '/')
        var device = string.split(arguments[4], '_')
        var i = int(device[1]) - 1

        print('onoff:', topic, ' ', payload_s)
        gpio.digital_write(self.relay[i], 0)
    end

    # Function to handle mode commands
    def mode(topic, idx, payload_s, payload_b)
        print('mode:', topic, ' ', payload_s)
    end

    # Function to handle weekly schedule commands
    def isemaine(topic, idx, payload_s, payload_b)
        var myjson = json.load(string.tolower(payload_s))
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end

        print("debug 1")
        var arguments = string.split(topic, '/')
        var device = string.split(arguments[3], '_')
        var i = int(device[1]) - 1
        print("debug 2")

        self.thermostat[i]['offset'] = myjson['offset']
        self.thermostat[i]['ouvert'] = myjson['ouvert']
        self.thermostat[i]['ferme'] = myjson['ferme']
        self.thermostat[i]['lundi'] = myjson['lundi']
        self.thermostat[i]['mardi'] = myjson['mardi']
        self.thermostat[i]['mercredi'] = myjson['mercredi']
        self.thermostat[i]['jeudi'] = myjson['jeudi']
        self.thermostat[i]['vendredi'] = myjson['vendredi']
        self.thermostat[i]['samedi'] = myjson['samedi']
        self.thermostat[i]['dimanche'] = myjson['dimanche']
        
        var buffer = json.dump(self.thermostat[i])
        var name = "thermostat_" + str(i + 1) + ".json"
        var file = open(name, "wt")
        if file == nil
            mqttprint("Error: Failed to open file for writing")
            return
        end
        file.write(buffer)
        file.close()
    end

    # Initialization function
    def init()
        var file
        var myjson        
        self.thermostat = list()
        print("init thermostat")
        print(global.nombre)
        for i:0..global.nombre-1
            var name = "thermostat_" + str(i + 1) + ".json"
            file = open(name, "rt")
            if file == nil
                mqttprint("Error: Failed to open file " + name)
                continue
            end
            myjson = file.read()
            file.close()
            var json_data = json.load(myjson)
            if json_data == nil
                mqttprint("Error: Failed to parse JSON from file " + name)
                continue
            end
            self.thermostat.insert(i,json_data)  
            print(self.thermostat[i]) 
        end 
        print("init thermostat done")
        self.day_list = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
        mqttprint("subscription MQTT")
        self.subscribes()
        self.relay = list()
        self.relay.insert(0, 18)
        self.relay.insert(1, 19)
        gpio.pin_mode(self.relay[0], gpio.OUTPUT)
        gpio.digital_write(self.relay[0], 0)    
        gpio.pin_mode(self.relay[1], gpio.OUTPUT)
        gpio.digital_write(self.relay[1], 0)  
        self.count = 0  
    end

    # Function to subscribe to MQTT topics
    def subscribes()
        var topic 
        # aerotherme
        for i:0..global.nombre-1
            topic = string.format("app/%s/%s/%s/set/ONOFF", global.client, global.ville, global.device + "_" + str(i + 1))
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.onoff(topic, idx, payload_s, payload_b))
            mqttprint("subscribed to ONOFF")
            topic = string.format("app/%s/%s/%s/set/MODE", global.client, global.ville, global.device + "_" + str(i + 1))
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mode(topic, idx, payload_s, payload_b))
            mqttprint("subscribed to MODE")
            topic = string.format("app/%s/%s/%s/set/ISEMAINE", global.client, global.ville, global.device + "_" + str(i + 1))
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.isemaine(topic, idx, payload_s, payload_b))
            mqttprint("subscribed to ISEMAINE")
        end
    end

    # Function to execute every minute
    def every_minute()
        var now = tasmota.rtc()
        var rtc = tasmota.time_dump(now["local"])
        var second = rtc["sec"]
        var minute = rtc["min"]
        var hour = rtc["hour"]
        var day = rtc["day"]
        var month = rtc["month"]
        var year = rtc["year"]
        var day_of_week = rtc["weekday"]  # 0=Sunday, 1=Monday, ..., 6=Saturday
        var jour = self.day_list[day_of_week]

        var payload
        var topic

        var target

        var temperature = ds18b20.poll()
        if (temperature == nil || temperature == -99)
            mqttprint("Error: Failed to read temperature")
            return
        end

        for i:0..global.nombre-1
            if (hour >= self.thermostat[i][jour]['debut'] && hour < self.thermostat[i][jour]['fin'])
                target = self.thermostat[i]['ouvert']
            else
                target = self.thermostat[i]['ferme']
            end

            payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"ouvert":%.1f,"ferme":%1.f,"offset":%.1f,"location":"%s","Target":%.f}', 
                    global.device, global.device+'_'+str(i+1), temperature, self.thermostat[i]['ouvert'], self.thermostat[i]['ferme'], self.thermostat[i]['offset'], global.location[i], target)
            topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device+"_"+str(i + 1))
            mqtt.publish(topic, payload, true)
            topic = string.format("gw/%s/%s/%s/tele/STATE", global.client, global.ville, global.device+"_"+str(i + 1))
            if (hour >= self.thermostat[i][jour]['debut'] && hour < self.thermostat[i][jour]['fin'])
                if (temperature < self.thermostat[i]['ouvert'] + self.thermostat[i]['offset'])
                    gpio.digital_write(self.relay[i], 0)
                    payload = string.format('{"Device":"%s","Name":"%s","Power":1}', global.device, global.device+"_"+str(i + 1))
                    mqtt.publish(topic, payload, true)
                else
                    gpio.digital_write(self.relay[i], 1)
                    payload = string.format('{"Device":"%s","Name":"%s","Power":0}', global.device, global.device+"_"+str(i + 1))
                    mqtt.publish(topic, payload, true)
                end
            else
                if (temperature < self.thermostat[i]['ferme'] + self.thermostat[i]['offset'])
                    gpio.digital_write(self.relay[i], 0)
                    payload = string.format('{"Device":"%s","Name":"%s","Power":1}', global.device, global.device+"_"+str(i + 1))
                    mqtt.publish(topic, payload, true)
                else
                    gpio.digital_write(self.relay[i], 1)
                    payload = string.format('{"Device":"%s","Name":"%s","Power":0}', global.device, global.device+"_"+str(i + 1))
                    mqtt.publish(topic, payload, true)
                end
            end        
        end
    end

    # Function to execute every second
    def every_second()
        if (self.count == 5)
            var temperature = pt1000.poll(0)
            self.count = 0
        else
            self.count = self.count + 1
        end
#        print(temperature)
    end
end

var aerotherme = AEROTHERME()
tasmota.add_driver(aerotherme)
tasmota.add_cron("0 * * * * *", /-> aerotherme.every_minute(), "every_min_@0_s")