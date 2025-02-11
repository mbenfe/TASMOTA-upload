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

class RDX
    var gate
    var day_list
    var horaires

    def setup(topic, idx, payload_s, payload_b)
        print('setup:',topic,' ', payload_s)
        gpio.digital_write(self.gate, 0)
    end

    def init()
        var file = open("horaires.json", "rt")
        var myjson = file.read()
        file.close()
        self.horaires = json.load(myjson)  
        mqttprint(self.horaires) 
        self.gate = 19
        self.day_list = ["dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"]
        mqttprint("subscription MQTT")
        self.subscribes()
        gpio.pin_mode(self.gate, gpio.OUTPUT)
        gpio.digital_write(self.gate, 1)    
    end

    def subscribes()
        var topic 
        # rideaux
        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.setup(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to SETUP")
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
        if(data == nil)
            return
        end
        var temperature = data[0]
        var humidity = data[1]
        var payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"Humidity":%.2f,"ouvert":%.1f,"ferme":%1.f,"offset":%.1f,"location":"%s"}', 
                global.device, global.device, temperature, humidity,self.horaires['ouvert'],self.horaires['ferme'],self.horaires['offset'],global.location)
        var topic = string.format("app/%s/%s/%s/set/SETUPT", global.client, global.ville, global.device)
        mqtt.publish(topic, payload, true)
    end

    def every_second()
    end
end

rdx = RDX()
rdx.init()
tasmota.add_driver(rdx)
tasmota.add_cron("0 * * * * *", /-> rdx.every_minute(), "every_min_@0_s")