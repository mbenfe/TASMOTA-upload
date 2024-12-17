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

class CHX
    var aht20
    var gate
    var day_list
    var thermostat

    def onoff(topic, idx, payload_s, payload_b)

        print('onoff:',topic,' ', payload_s)
        gpio.digital_write(self.gate, 0)
    end

    def mode(topic, idx, payload_s, payload_b)
        print('mode:',topic,' ', payload_s)
    end

    def isemaine(topic, idx, payload_s, payload_b)

        print('isemaine:',topic,' ', payload_s)

        var myjson = json.load(string.tolower(payload_s))

        self.thermostat['offset'] = myjson['offset']
        self.thermostat['ouvert'] = myjson['ouvert']
        self.thermostat['ferme'] = myjson['ferme']
        self.thermostat['lundi'] = myjson['lundi']
        self.thermostat['mardi'] = myjson['mardi']
        self.thermostat['mercredi'] = myjson['mercredi']
        self.thermostat['jeudi'] = myjson['jeudi']
        self.thermostat['vendredi'] = myjson['vendredi']
        self.thermostat['samedi'] = myjson['samedi']
        self.thermostat['dimanche'] = myjson['dimanche']
        
        var buffer = json.dump(self.thermostat)
        var file = open("thermostat_intermarche.json", "wt")
        file.write(buffer)
        file.close()
    end

    def init()
        var file = open("thermostat_intermarche.json", "rt")
        var myjson = file.read()
        file.close()
        self.thermostat = json.load(myjson)  
        print(self.thermostat) 
        self.gate = 19
        self.day_list = ["dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"]
        mqttprint("subscription MQTT")
        self.subscribes()
        gpio.pin_mode(self.gate, gpio.OUTPUT)
        gpio.digital_write(self.gate, 1)    
    end

    def subscribes()
        var topic 
        # chauffages
        topic = string.format("app/%s/%s/%s/set/ONOFF", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.onoff(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to ONOFF")
        topic = string.format("app/%s/%s/%s/set/MODE", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mode(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to MODE")
        topic = string.format("app/%s/%s/%s/set/ISEMAINE", global.client, global.ville,global.device)
        mqtt.subscribe(topic, /topic, idx, payload_s, payload_b -> self.isemaine(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to ISEMAINE")
    end

    def every_minute()
        var now = tasmota.rtc()
        var rtc=tasmota.time_dump(now["local"])
        var second = rtc["sec"]
        var minute = rtc["min"]
        var hour = rtc["hour"]
        var day = rtc["day"]
        var month = rtc["month"]
        var year = rtc["year"]
        var day_of_week = rtc["weekday"]  # 0=Sunday, 1=Monday, ..., 6=Saturday
        var jour = self.day_list[day_of_week]
        var data = aht20.poll()
        if(data == nil)
            return
        end
        var temperature = data[0]
        var humidity = data[1]
        var payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"Humidity":%.2f,"ouvert":%.1f,"ferme":%1.f,"offset":%.1f,"location":"%s"}', 
                global.device, global.device, temperature, humidity,self.thermostat['ouvert'],self.thermostat['ferme'],self.thermostat['offset'],global.location)
        var topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        mqtt.publish(topic, payload, true)
        topic = string.format("gw/%s/%s/%s/tele/STATE", global.client, global.ville, global.device)
        if( hour >= self.thermostat[jour]['debut'] && hour < self.thermostat[jour]['fin'] )
            if (temperature < self.thermostat['ouvert']+self.thermostat['offset'])
                gpio.digital_write(self.gate, 0)
                payload = string.format('{"Device":"%s","Name":"%s","Power":1}', global.device, global.device)
                mqtt.publish(topic, payload, true)
            else
                gpio.digital_write(self.gate, 1)
                payload = string.format('{"Device":"%s","Name":"%s","Power":0}', global.device, global.device)
                mqtt.publish(topic, payload, true)
            end
        else
            if (temperature < self.thermostat['ferme']+self.thermostat['offset'])
                gpio.digital_write(self.gate, 0)
                payload = string.format('{"Device":"%s","Name":"%s","Power":1}', global.device, global.device)
                mqtt.publish(topic, payload, true)
            else
                gpio.digital_write(self.gate, 1)
                payload = string.format('{"Device":"%s","Name":"%s","Power":0}', global.device, global.device)
                mqtt.publish(topic, payload, true)
            end
        end        
    end

    def every_second()
    end
end

chx = CHX()
chx.init()
tasmota.add_driver(chx)
tasmota.add_cron("0 * * * * *", /-> chx.every_minute(), "every_min_@0_s")