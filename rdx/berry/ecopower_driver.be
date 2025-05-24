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
    var temperature
    var status
    var scheduler
    var reglage
    var day_list

    def acknowlege(topic, idx, payload_s, payload_b)
        var myjson
        var newtopic
        var payload
        var file
        var buffer

        myjson = json.load(payload_s)
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.publish(newtopic, payload_s, true)
        file = open("setup.json", "wt")
        file.write(payload_s)
        file.close()
        self.temperature = myjson["temperature"]
        self.status = myjson["status"]
        self.scheduler = myjson["scheduler"]
        self.reglage = myjson["reglage"]
    end

    def mypush()
        var file
        var myjson        
            
        file = open("setup.json", "rt")
        if file == nil
            mqttprint("Error: Failed to open file setup.json")
            return
        end
        myjson = file.read()
        file.close()
        var  newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        var payload = string.format('{"Device":"%s","Name":"%s","DATA":%s}',
                    global.device, global.device, myjson)
        print('setup:', newtopic, ' ', payload)
        mqtt.publish(newtopic, payload, true) 
    end


    def init()
        import path
        mqttprint('init')
        var file
        var buffer
        var myjson
        var topic
        file = open("setup.json", "rt")
        if(file == nil)
            mqttprint("file not found: setup.json")
            return
        end
        buffer = file.read()
        myjson = json.load(buffer)
        print('------------------------------------------')
        print(myjson)
        file.close()
        self.scheduler = myjson["scheduler"]
        self.status = myjson["status"]
        self.reglage = myjson["reglage"]
        self.temperature = myjson["temperature"]
        self.day_list = ["dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"]
        self.subscribes()   
        tasmota.set_timer(30000,/-> self.mypush())

    end

    def subscribes()
        var topic 
        # rideaux
        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.acknowlege(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to SETUP")
    end

    def every_minute()
        if(self.reglage ==0)
        else
        end
    end  

    def every_second()
    end
end

rdx = RDX()

tasmota.add_driver(rdx)
tasmota.add_cron("0 * * * * *", /-> rdx.every_minute(), "every_min_@0_s")