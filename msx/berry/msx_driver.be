var version = "1.0.0 avec couts"

import mqtt
import string
import json
import global
import math

class MSX

    var logger
    var root
    var topic 
    var conso
    var tick
    var previousPower 
    var Energy

    def loadconfig()
        import json
        var jsonstring
        var file 
        file = open("esp32.cfg", "rt")
        if file.size() == 0
            print('creat esp32 config file')
            file = open("esp32.cfg", "wt")
            jsonstring = string.format("{\"ville\":\"unknown\",\"client\":\"labo\",\"device\":\"unknown\"}")
            file.write(jsonstring)
            file.close()
            file = open("esp32.cfg", "rt")
        end
        var buffer = file.read()
        var jsonmap = json.load(buffer)
        global.client = jsonmap["client"]
        print('client:', global.client)
        global.ville = jsonmap["ville"]
        print('ville:', global.ville)
        global.device = jsonmap["device"]
        print('device:', global.device)
    end

    def init()
        self.loadconfig()
        print("global.ville:", global.ville)
        print("global.client:", global.client)
        print("load conso")
        import conso
        self.conso = conso
        print("conso loaded")
        self.previousPower = 0
        self.tick = 0
        self.Energy = 0
    end

    def midnight()
        self.conso.mqtt_publish('all')
    end

    def hour()
        var now = tasmota.rtc()
        var rtc = tasmota.time_dump(now["local"])
        var hour = rtc["hour"]
        # publish if not midnight
        if hour != 23
            self.conso.mqtt_publish('hours')
        end
        self.conso.sauvegarde()
    end


    def every_second()
        var topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client,global.ville, global.device)
        var data = tasmota.read_sensors()
        var etat = tasmota.get_power()

        if(etat[0] == false)
            tasmota.set_power(0,true)
        end
        var myjson = json.load(data)

        var power = myjson["ENERGY"]["Power"]
        self.Energy += real((power + self.previousPower) / 2)
        self.tick+=1
        self.previousPower = power
        if self.tick == 15
            self.tick = 0
            self.Energy=real(real(self.Energy)/real(240))
            self.conso.update(self.Energy)
            self.Energy = 0
            var payload = string.format('{"Device":"%s","Name":"%s","ActivePower":%.2f}', global.device, global.device, power)
            mqtt.publish(topic, payload, true)      
        end

    end
end

msx = MSX()
tasmota.add_driver(msx)
var now = tasmota.rtc()
var delay
var mycron
math.srand(size(global.device)*size(global.ville))
var random = math.rand()
delay = random % 10
# set midnight cron
mycron = string.format("59 %d 23 * * *", 50 + delay)
tasmota.add_cron(mycron, /-> msx.midnight(), "every_day")
mqttprint("cron midnight:" + mycron)
# set hour cron
mycron = string.format("59 %d * * * *", 50 + delay)
tasmota.add_cron(mycron, /-> msx.hour(), "every_hour")
mqttprint("cron hour:" + mycron)

return msx