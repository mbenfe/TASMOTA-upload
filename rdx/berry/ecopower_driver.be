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

    def mysetup(topic, idx, payload_s, payload_b)
        var myjson
        var newtopic
        var payload
        var file
        var buffer

        myjson = json.load(payload_s)
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        self.setups["onoff"] = myjson["onoff"]
        self.setups["mode"] = myjson["mode"]
        self.setups["fanspeed"] = myjson["fanspeed"]
        self.setups["heat_power"] = myjson["heat_power"]
        payload = string.format('{"Device":"%s","Name":"%s","onoff":%d,"mode":%d,"fanspeed":%d,"heat_power":%d,"location":"%s"}', 
                global.device, global.device, self.setups["onoff"], self.setups["mode"],self.setups["fanspeed"],self.setups["heat_power"],global.location)
        print('setup:',topic,' ', payload_s)
        mqtt.publish(newtopic, payload, true)
        file = open("setup.json", "wt")
        buffer = json.dump(self.setups)
        file.write(buffer)
        file.close()
    end

    def init()
        import path
        mqttprint('init')
        var file
        var myjson
        file = open("horaires.json", "rt")
        if(file == nil)
            mqttprint("file not found: horaires.json")
            return
        end
        myjson = file.read()
        file.close()
        self.horaires = json.load(myjson)  
        mqttprint(str(self.horaires))

        if(!path.exists("setup.json"))
            print("n'exsite pas")
            self.setups = map()
            self.setups.insert("onoff",0)
            self.setups.insert("mode",0)
            self.setups.insert("fanspeed",0)
            self.setups.insert("heat_power",0)
            file = open("setup.json", "wt")
            file.write(json.dump(self.setups))
            file.close()
        else
            file = open("setup.json", "rt")
            myjson = file.read()
            file.close()
            self.setups = json.load(myjson)
        end
        mqttprint(str(self.setups))
        self.gate = 19
        self.day_list = ["dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"]
        self.subscribes()
        gpio.pin_mode(self.gate, gpio.OUTPUT)
        gpio.digital_write(self.gate, 1)    
    end

    def subscribes()
        var topic 
        # rideaux
        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mysetup(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to SETUP")
    end

    def every_minute()
        var topic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        var payload = string.format('{"Device":"%s","Name":"%s","onoff":%d,"mode":%d,"fanspeed":%d,"heat_power":%d,"location":"%s"}', 
                global.device, global.device, self.setups["onoff"], self.setups["mode"],self.setups["fanspeed"],self.setups["heat_power"],global.location)
        mqtt.publish(topic, payload, true)
    end

    def every_second()
    end
end

rdx = RDX()
#rdx.init()
tasmota.add_driver(rdx)
tasmota.add_cron("0 * * * * *", /-> rdx.every_minute(), "every_min_@0_s")