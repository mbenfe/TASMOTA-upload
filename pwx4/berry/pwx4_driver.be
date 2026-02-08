var version = "1.0.0 avec couts"

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
    print("cron for " + combined + " is " + str(sum%60))
    return sum % 60
end

class PWX4
    var ser
    var rx
    var tx
    var bsl
    var rst

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
        self.rx = 3
        self.tx = 1
        self.rst = 2
        self.bsl = 13

        print('DRIVER: serial init done')
        print('heap:', tasmota.get_free_heap())
        self.ser = serial(self.rx, self.tx, 115200, serial.SERIAL_8N1) 
        # setup boot pins for stm32: reset disable & boot normal
        gpio.pin_mode(self.rst, gpio.OUTPUT)
        gpio.pin_mode(self.bsl, gpio.OUTPUT)
        gpio.digital_write(self.bsl, 0)
        gpio.digital_write(self.rst, 1)
    end

    def fast_loop()
        self.read_uart(2)
    end

    def read_uart(timeout)
        if self.ser.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = self.ser.read()
            self.ser.flush()
            var mystring = buffer.asstring()
            var mylist = string.split(mystring, '\n')
            var numitem = size(mylist)
            var topic
            var split
			var ligne
            for i: 0..numitem-2
                if mylist[i][0] == 'C'
                    self.conso.update(mylist[i])
                    topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                    mqtt.publish(topic, mylist[i], true)
                elif mylist[i][0] == 'W'
                    # self.logger.log_data(mylist[i])
                    split = string.split(mylist[i], ':')
                    for j: 0..0
                        topic = string.format("gw/%s/%s/%s/tele/POWER", global.client, global.ville, global.device)
                        ligne = string.format('{"Device": "%s","Name":"%s","ActivePower":%.1f}', global.device, global.configjson[global.device]["root"][j], real(split[j + 1]))
                        mqtt.publish(topic, ligne, true)
                    end
                else
                    print('PWX4->', mylist[i])
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
        var topic = string.format("gw/%s/%s/%s/tele/HEARTBEAT", global.client, global.ville, global.device)
        var payload = string.format('{"Device":"%s","Name":"%s","Time":"%s"}', global.device, global.device, timestamp)
        mqtt.publish(topic, payload, true)
    end

end

pwx4 = PWX4()
tasmota.add_driver(pwx4)
var now = tasmota.rtc()
tasmota.add_fast_loop(/-> pwx4.fast_loop())
# set midnight cron
var cron_second = get_cron_second()
var mycron = string.format("%d 59 23 * * *", cron_second)
tasmota.add_cron(mycron, /-> pwx4.midnight(), "every_day")
print("cron midnight:" + mycron)
# set hour cron
mycron = string.format("%d 59 * * * *", cron_second)
tasmota.add_cron(mycron, /-> pwx4.hour(), "every_hour")
print("cron hour:" + mycron)
# set heartbeat cron
mycron = string.format("%d %d * * * *", cron_second, cron_second)
tasmota.add_cron(mycron, /-> pwx4.heartbeat(), "every_hour")
print("cron heartbeat:" + mycron)
# set 4 hours cron
mycron = string.format("%d 0 */4 * * *", cron_second)
tasmota.add_cron(mycron, /-> pwx4.every_4hours(), "every_4_hours")
print("cron every 4 hours:" + mycron)

return pwx4