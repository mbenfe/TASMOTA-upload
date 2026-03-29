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
    var pending_cfg_cmd
    var cfg_next_send_ms
    var cfg_attempts
    var cfg_ack

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
         self.rx_partial = ""
        self.pending_cfg_cmd = nil
        self.cfg_next_send_ms = 0
        self.cfg_attempts = 0
        self.cfg_ack = false

        self.prepare_config_push()

        print('DRIVER: serial init done')
        print('heap:', tasmota.get_free_heap())
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
            "SET CONFIG %s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s_%s\\n",
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

        # Ensure STM32 is released from reset before sending config.
        tasmota.cmd("start")
        tasmota.delay(120)
        global.ser.flush()
        global.ser.write(bytes().fromstring(self.pending_cfg_cmd))
        self.cfg_attempts += 1
        self.cfg_next_send_ms = tasmota.millis() + 800
        print("CFG: sent attempt " + str(self.cfg_attempts))
    end

    def fast_loop()
        self.try_push_config()
        self.read_uart(2)
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
                    print('PWX12->', mylist[i])
                end
            end
        end
    end

    def midnight()
        self.conso.mqtt_publish('all')
    end

    def hour()
        self.conso.mqtt_publish('hours')

        # Additional hourly request for hardware energy delta (returned as raw D frame).
        global.ser.flush()
        global.ser.write(bytes().fromstring("GET ENERGY"))
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