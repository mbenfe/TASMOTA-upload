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
    var ser
    var rx
    var tx
    var bsl
    var rst
    var rx_partial
    var pending_cfg_cmd
    var cfg_next_send_ms
    var cfg_attempts
    var cfg_ack

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
        self.rx_partial = ""
        self.pending_cfg_cmd = nil
        self.cfg_next_send_ms = 0
        self.cfg_attempts = 0
        self.cfg_ack = false

        print('DRIVER: serial init done')
        print('heap:', tasmota.get_free_heap())
        self.ser = serial(self.rx, self.tx, 115200, serial.SERIAL_8N1) 
        # setup boot pins for stm32: reset disable & boot normal
        gpio.pin_mode(self.rst, gpio.OUTPUT)
        gpio.pin_mode(self.bsl, gpio.OUTPUT)
        gpio.digital_write(self.bsl, 0)
        gpio.digital_write(self.rst, 1)

        self.prepare_config_push()
    end

    def _arr_get(arr, idx, fallback)
        if arr != nil && size(arr) > idx && arr[idx] != nil
            return str(arr[idx])
        end
        return fallback
    end

    def prepare_config_push()
        import json
        import string
        var file_name = string.format("p_%s.json", global.ville)
        var file = open(file_name, "rt")
        if file == nil
            print("CFG: missing file " + file_name)
            return
        end

        var buffer = file.read()
        file.close()
        var all_cfg = json.load(buffer)
        if all_cfg == nil || !all_cfg.contains(global.device)
            print("CFG: missing device entry " + global.device)
            return
        end

        var dev = all_cfg[global.device]
        var produit = str(dev["produit"])

        var r0 = self._arr_get(dev["root"], 0, "*")
        var r1 = self._arr_get(dev["root"], 1, "*")
        var r2 = self._arr_get(dev["root"], 2, "*")

        var t0 = self._arr_get(dev["techno"], 0, "ct")
        var t1 = self._arr_get(dev["techno"], 1, "ct")
        var t2 = self._arr_get(dev["techno"], 2, "ct")

        var q0 = self._arr_get(dev["ratio"], 0, "1000")
        var q1 = self._arr_get(dev["ratio"], 1, "1000")
        var q2 = self._arr_get(dev["ratio"], 2, "1000")

        var p0 = self._arr_get(dev["PGA"], 0, "1")
        var p1 = self._arr_get(dev["PGA"], 1, "1")
        var p2 = self._arr_get(dev["PGA"], 2, "1")

        var m0 = self._arr_get(dev["mode"], 0, "tri")
        var m1 = self._arr_get(dev["mode"], 1, "tri")
        var m2 = self._arr_get(dev["mode"], 2, "tri")

        self.pending_cfg_cmd = string.format(
            "SET CONFIG %s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s\\r\\n",
            global.device,
            r0, r1, r2,
            produit,
            t0, t1, t2,
            q0, q1, q2,
            p0, p1, p2,
            m0, m1, m2
        )

        self.cfg_attempts = 0
        self.cfg_ack = false
        self.cfg_next_send_ms = tasmota.millis() + 1200
        print("CFG: prepared for STM32")
    end

    def try_push_config()
        if self.pending_cfg_cmd == nil || self.cfg_ack
            return
        end
        if self.cfg_attempts >= 4
            return
        end
        if !tasmota.time_reached(self.cfg_next_send_ms)
            return
        end

        tasmota.cmd("start")
        tasmota.delay(120)
        self.ser.flush()
        self.ser.write(bytes().fromstring(self.pending_cfg_cmd))
        self.cfg_attempts += 1
        self.cfg_next_send_ms = tasmota.millis() + 800
        print("CFG: sent attempt " + str(self.cfg_attempts))
    end

    def fast_loop()
        self.try_push_config()
        self.read_uart(2)
    end

    def read_uart(timeout)
        if self.ser.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = self.ser.read()
            self.ser.flush()
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
                elif line[0] == '{'
                    if string.find(line, '"type":"calibration"') != -1
                        topic = string.format("gw/%s/%s/%s/tele/CALIBRATION", global.client, global.ville, global.device)
                        mqtt.publish(topic, line, true)
                    else
                        topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                        mqtt.publish(topic, line, true)
                    end
                else
                    if string.find(line, "config done") != -1
                        self.cfg_ack = true
                        self.pending_cfg_cmd = nil
                        print("CFG: STM32 acknowledged")
                    end
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

        self.ser.flush()
        self.ser.write(bytes().fromstring("GET ENERGY"))
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
        self.ser.flush()
        self.ser.write(bytes().fromstring(cmd))
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