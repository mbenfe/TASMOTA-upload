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

    def loadconfig()
        import json
        var jsonstring
        var file 
        file = open("esp32.cfg", "rt")
        if file.size() == 0
            print('creat esp32 config file')
            file = open("esp32.cfg", "wt")
            jsonstring = string.format("{\"ville\":\"unknown\",\"client\":\"inter\",\"device\":\"unknown\"}")
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
    end

    def every_4hours()
        self.conso.sauvegarde()
    end

    def every_minutes()
        tasmota.cmd("power 1")
    end


    def every_second()
        var topic = string.format("gw/inter/%s/%s/tele/SENSOR", global.ville, global.device)
        var data = tasmota.read_sensors()
        var myjson = json.load(data)
        var power = myjson["ENERGY"]["ApparentPower"]
        var Energy = power - self.previousPower
        Energy/=3600
#        self.conso.update(Energy)
        self.tick+=1
        self.previousPower = power
        if self.tick == 15
            self.tick = 0
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
# set 4 hours cron
tasmota.add_cron("01 01 */4 * * *", /-> msx.every_4hours(), "every_4_hours")
# set power ON every minute
tasmota.add_cron("* * * * * *", /-> msx.every_minutes(), "every_minutes")

return msx