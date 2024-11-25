var version "1.0.112024 initial"

import mqtt
import string
import json


class CHX
    var client 
    var ville
    var device
    var location 

    def loadconfig()
        import json
        var jsonstring
        var file 
        file = open("esp32.cfg","rt")
        if file.size() == 0
            print('creat esp32 config file')
            file = open("esp32.cfg","wt")
            jsonstring=string.format("{\"ville\":\"unknown\",\"client\":\"inter\",\"device\":\"unknown\"}")
            file.write(jsonstring)
            file.close()
            file=open("esp32.cfg","rt")
        end
        var buffer = file.read()
        var jsonmap = json.load(buffer)
        self.client=jsonmap["client"]
        print('client:',self.client)
        self.ville=jsonmap["ville"]
        print('ville:',self.ville)
        self.device=jsonmap["device"]
        print('device:',self.device)
        self.location=jsonmap["location"]
        print('location:',self.location)
    end

    def init()
        self.loadconfig()
        self.aht20 = AHT20()
        self.aht20.init()
       self.subscribes()
    end

    def subscribes()
        var topic 
        # chauffages
        topic = string.format("app/%s/%s/+/set/ONOFF",client,ville)
        mqtt.subscribe(topic, onoff)
        print("subscribed to ONOFF")
        topic = string.format("app/%s/%s/+/set/MODE",client,ville)
        mqtt.subscribe(topic, mode)
        print("subscribed to MODE")
        topic = string.format("app/%s/%s/+/set/ABSENCE",client,ville)
        mqtt.subscribe(topic, absence)
        print("subscribed to ABSENCE")
        topic = string.format("app/%s/%s/+/set/WEEKEND",client,ville)
        mqtt.subscribe(topic, weekend)
        print("subscribed to WEEKEND")
        topic = string.format("app/%s/%s/+/set/SEMAINE",client,ville)
        mqtt.subscribe(topic, semaine)
        print("subscribed to SEMAINE")
    end

    def every_minute()
        var data = self.aht20.read_temperature_humidity()
        var payload = string.format('{"Device":"%s","Name":"%s","Temperature":%f,"Humidity":%f}',self.device,self.device,data[0],data[1])
        var topic = string.format("gw/%s/%s/%s/tele/SENSOR",self.client,self.ville,self.device)
        mqtt.publish(topic,payload,true)
    end

    def every_second()
    end

    
end

chx = CHX()
tasmota.add_driver(chx)
tasmota.add_cron("0 * * * * *", /-> chx.every_minute(), "every_min_@0_s")
