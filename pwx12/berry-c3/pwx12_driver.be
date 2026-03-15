var version = "2.0.0 avec cron specifique"

import mqtt
import string
import json
import math

def get_cron_second()
    var combined = string.format("%s|%s", global.ville, global.device)
    var sum = 0
    for i : 0 .. size(combined) - 1
        sum += string.byte(combined[i])
    end
    print("cron for " + combined + " is " + str(sum % 60))
    return sum % 60
end


class PWX12
    var rx_partial

    var logger
    var root
    var topic 
    var conso

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
        import conso
        self.conso = conso
        import logger
        self.logger = logger
        self.rx_partial = ""

        print('DRIVER: serial init done')
        print('heap:', tasmota.get_free_heap())
    end

    def fast_loop()
        self.read_uart(2)
    end

    def read_uart(timeout)
        if global.serial.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = global.serial.read()
            global.serial.flush()
            var mystring = self.rx_partial + buffer.asstring()
            var mylist = string.split(mystring, '\n')
            var numitem = size(mylist)
            self.rx_partial = mylist[numitem - 1]
            var topic
            var split
            var ligne
            var line
            for i: 0..numitem-2
                line = mylist[i]
                if size(line) == 0
                    continue
                end

                # normalize CRLF from STM32
                split = string.split(line, '\r')
                line = split[0]
                if size(line) == 0
                    continue
                end

                if line[0] == 'C'
                    split = string.split(line, ':')
                    if size(split) >= 4 && size(split[1]) > 0 && size(split[2]) > 0 && size(split[3]) > 0
                        self.conso.update(line)
                        topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                        mqtt.publish(topic, line, true)
                    else
                        print('PWX12-> malformed C frame:', line)
                    end
                elif line[0] == 'W'
                    # self.logger.log_data(mylist[i])
                    split = string.split(line, ':')
                    if size(split) >= 4
                        for j: 0..2
                            if global.configjson[global.device]["root"][j] != "*"
                                topic = string.format("gw/%s/%s/%s-%d/tele/POWER", global.client, global.ville, global.device, j + 1)
                                ligne = string.format('{"Device": "%s","Name":"%s","ActivePower":%.1f}', global.device, global.configjson[global.device]["root"][j], real(split[j + 1]))
                                mqtt.publish(topic, ligne, true)
                            end
                        end
                    else
                        print('PWX12-> malformed W frame:', line)
                    end
                else
                    print('PWX12->', line)
                end
            end
        end
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

    def testlog()
        self.logger.store()
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
        var topic = string.format("gw/%s/%s/%s/tele/HEARTBEAT", global.client, global.ville, global.device)
        var payload = string.format('{"Device":"%s","Name":"%s","Time":"%s","AccessPoint":"%s","IpAddress":"%s"}', global.device, global.device, timestamp, ap, ip)
        mqtt.publish(topic, payload, true)
    end

    def sync_time()
        var now = tasmota.rtc()
        if now == nil || !now.contains("utc")
            print("sync: rtc utc unavailable")
            return
        end

        var epoch = int(now["utc"])
        var cmd = string.format("SET TIME %d\r\n", epoch)
        global.serial.flush()
        global.serial.write(bytes().fromstring(cmd))
        print("sync sent: " + cmd)
    end

end



global.pwx12 = PWX12()
tasmota.add_driver(global.pwx12)
var now = tasmota.rtc()

tasmota.add_fast_loop(/-> global.pwx12.fast_loop())

var cron_second = get_cron_second()
# set midnight cron
var cron_pattern = string.format("%d 59 23 * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> global.pwx12.midnight(), "every_day")
print("cron midnight:" + cron_pattern)
# set hour cron
cron_pattern = string.format("%d 59 * * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> global.pwx12.hour(), "every_hour")
print("cron hour:" + cron_pattern)
# set heartbeat cron
cron_pattern = string.format("%d %d * * * *", cron_second, cron_second)
tasmota.add_cron(cron_pattern, /-> global.pwx12.heartbeat(), "every_hour")
print("cron heartbeat:" + cron_pattern)
# set 4 hours cron
cron_pattern = string.format("%d 0 */4 * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> global.pwx12.every_4hours(), "every_4_hours")
print("cron every 4 hours:" + cron_pattern)

# set 5 minutes sync cron
cron_pattern = string.format("%d */5 * * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> global.pwx12.sync_time(), "every_5_minutes_sync")
print("cron every 5 minutes sync:" + cron_pattern)

# return pwx12