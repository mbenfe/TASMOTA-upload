var version = "2.0.0 avec cron specifique"

import mqtt
import string
import json
import math
import global

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

    var root
    var topic 
    var conso

    def init()
        import conso
        self.conso = conso

        print('DRIVER: serial init done')
        print('heap:', tasmota.get_free_heap())
    end

    def fast_loop()
        self.read_uart(2)
    end

    def process_uart_line(line)
        var topic
        var split
        var ligne

        if string.find(line, "CONFIG ") == 0
            var payload = line[7..]
            split = string.split(payload, ':')
            if size(split) >= 17
                topic = string.format("gw/%s/%s/%s/tele/CONFIG", global.client, global.ville, global.device)
                ligne = string.format(
                    '{"device":"%s","root":["%s","%s","%s"],"produit":"%s","techno":["%s","%s","%s"],"ratio":[%s,%s,%s],"pga":[%s,%s,%s],"mode":["%s","%s","%s"]}',
                    split[0],
                    split[1], split[2], split[3],
                    split[4],
                    split[5], split[6], split[7],
                    split[8], split[9], split[10],
                    split[11], split[12], split[13],
                    split[14], split[15], split[16]
                )
                mqtt.publish(topic, ligne, true)
                print('PWX12 CONFIG->', ligne)
            else
                print('PWX12-> malformed CONFIG frame:', line)
            end
            return
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
        elif line[0] == 'D'
            split = string.split(line, ':')
            if size(split) >= 4 && size(split[1]) > 0 && size(split[2]) > 0 && size(split[3]) > 0
                topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                mqtt.publish(topic, line, true)
            else
                print('PWX12-> malformed D frame:', line)
            end
        elif line[0] == 'W'
            split = string.split(line, ':')
            if size(split) >= 4 && size(split[1]) > 0 && size(split[2]) > 0 && size(split[3]) > 0
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
        elif line[0] == '{'
            if string.find(line, '"type":"calibration"') != -1
                if string.find(line, '"group":"') != -1
                    topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                    mqtt.publish(topic, line, true)
                else
                    topic = string.format("gw/%s/%s/%s/tele/CALIBRATION", global.client, global.ville, global.device)
                    mqtt.publish(topic, line, true)
                end
            else
                topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                mqtt.publish(topic, line, true)
                print('PWX12->', line)
            end
        else
            topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
            mqtt.publish(topic, line, true)
            if string.find(line, "config done") != -1
                print("CFG: STM32 acknowledged")
            end
            print('PWX12->', line)
        end
    end

    def read_uart(timeout)
        if global.ser.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = global.ser.read()
            global.ser.flush()
            var mystring = buffer.asstring()
            var mylist = string.split(mystring, '\n')
            var numitem = size(mylist)
            var line
            for i: 0..numitem-2
                line = mylist[i]
                if size(line) == 0
                    continue
                end
                self.process_uart_line(line)
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

        global.ser.flush()
        global.ser.write(bytes().fromstring("GET ENERGY\n"))
    end

    def every_4hours()
        self.conso.sauvegarde()
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

# return pwx12