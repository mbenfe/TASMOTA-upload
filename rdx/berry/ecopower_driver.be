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
    var setups

    def setup(topic, idx, payload_s, payload_b)
        print('setup:',topic,' ', payload_s)
    end

    def init()
        mqttprint('init')
        var file = open("horaires.json", "rt")
        if(file == nil)
            mqttprint("file not found: horaires.json")
            return
        end
        var myjson = file.read()
        self.setups = map()
        self.setups.insert("onoff",0)
        self.setups.insert("mode",0)
        self.setups.insert("fanspeed",0)
        self.setups.insert("power",0)
        file.close()
        self.horaires = json.load(myjson)  
        mqttprint(self.horaires) 
        self.gate = 19
        self.day_list = ["dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"]
        mqttprint("subscription MQTT")
        self.subscribes()
        gpio.pin_mode(self.gate, gpio.OUTPUT)
        gpio.digital_write(self.gate, 1)    
        mqttprint("init done")
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
        var payload = string.format('{"Device":"%s","Name":"%s","onoff":%d,"mode":%d,"fanspeed":%d,"power":%d,"location":"%s"}', 
                global.device, global.device, self.setups["onoff"], self.setups["mode"],self.setups["fanspeed"],self.setups["power"],global.location)
        var topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.publish(topic, payload, true)
    end

    def every_second()
    end
end

rdx = RDX()
rdx.init()
tasmota.add_driver(rdx)
tasmota.add_cron("0 * * * * *", /-> rdx.every_minute(), "every_min_@0_s")