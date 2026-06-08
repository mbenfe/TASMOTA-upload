var version = "8.0.052026 versions"

import mqtt
import string
import json
import global

def get_cron_second()
    var combined = string.format("%s|%s", global.ville, global.device)
    var sum = 0
    for i : 0 .. size(combined) - 1
        sum += string.byte(combined[i])
    end
    var sec = sum % 60
    if sec == 0
        sec = 1
    end
    print("cron for " + combined + " is " + str(sec))
    return sec
end


class SNX
    var errors
    var mapID
    var mapFunc
     var client 
    var ville
    var device
    var topic 

    def mqttprint(texte)
        import mqtt
        var topic = string.format("gw/%s/%s/%s/tele/DEBUG2", self.client, self.ville, self.device)
        mqtt.publish(topic, texte, true)
    end


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
    end

    def init()
        self.mapID = {}
        self.mapFunc = {}
        self.errors = {}
        self.loadconfig()

        print('DRIVER: serial init done')
    
        gpio.pin_mode(global.statistic_pin,gpio.OUTPUT)
        gpio.pin_mode(global.ready_pin,gpio.OUTPUT)

        gpio.digital_write(global.statistic_pin, 0)
        gpio.digital_write(global.ready_pin,1)
    end

    def save()
        var file = open("error.json","wt")
        if file == nil
           return
        end
        var buffer = json.dump(self.errors)
        file.write(buffer)
        file.close()
    end

    def getcout()
        print("getcout: trigger native SNXCOUT ville=" + self.ville + " device=" + self.device)
        tasmota.cmd("snxcout")
    end

    def get_statistic()
         gpio.digital_write(global.statistic_pin, 1)
         tasmota.delay(1)
         gpio.digital_write(global.statistic_pin, 0)
    end

    def stm32reset()
        # Keep compatibility helper without touching rst; rst is managed by autoexec Stm32Reset.
        gpio.digital_write(global.ready_pin, 0)
        tasmota.delay(100)
        gpio.digital_write(global.ready_pin, 1)
        tasmota.delay(100)
    end

    def heartbeat()
        var now = tasmota.rtc()
        var timestamp = tasmota.time_str(now["local"])
        var wifi = tasmota.wifi()
        var ap = "unknown"
        var ip = "unknown"
        if wifi != nil
            if wifi.contains("ssid") && wifi["ssid"] != nil
                ap = str(wifi["ssid"])
            end
            if wifi.contains("ip") && wifi["ip"] != nil
                ip = str(wifi["ip"])
            end
        end
        var topic = string.format("gw/%s/%s/%s/tele/HEARTBEAT", self.client, self.ville, self.device)
        var payload = string.format('{"Device":"%s","Name":"%s","Time":"%s","AccessPoint":"%s","IpAddress":"%s"}', self.device, self.device, timestamp, ap, ip)
        mqtt.publish(topic, payload, true)
    end
end

snx = SNX()
global.snx = snx
global.stm32 = snx
tasmota.add_driver(snx)
var cron_second = get_cron_second()

var cron_pattern = string.format("%d %d 0 * * *", cron_second, cron_second)
tasmota.add_cron(cron_pattern, /-> snx.get_statistic(), "every_day")
print("cron statistic:" + cron_pattern)

var cout_prepare_pattern = string.format("%d %d 0 * * *", cron_second, cron_second - 1)
tasmota.add_cron(cout_prepare_pattern, /-> snx.getcout(), "every_day_cout_prepare")
print("cron cout prepare:" + cout_prepare_pattern)

cron_pattern = string.format("%d %d * * * *", cron_second, cron_second)
tasmota.add_cron(cron_pattern, /-> snx.heartbeat(), "every_hour")
print("cron heartbeat:" + cron_pattern)
