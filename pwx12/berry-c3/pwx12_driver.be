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

    def init()
        import conso
        self.conso = conso
        self.pending_cfg_cmd = nil
        self.cfg_next_send_ms = 0
        self.cfg_attempts = 0
        self.cfg_ack = false

        print('DRIVER: serial init done')
        print('heap:', tasmota.get_free_heap())

        self.prepare_config_push()
        self.push_config_once()
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
        var product_name = str(dev["produit"])

        var root_ch1 = self._arr_get(dev["root"], 0, "*")
        var root_ch2 = self._arr_get(dev["root"], 1, "*")
        var root_ch3 = self._arr_get(dev["root"], 2, "*")

        var techno_ch1 = self._arr_get(dev["techno"], 0, "ct")
        var techno_ch2 = self._arr_get(dev["techno"], 1, "ct")
        var techno_ch3 = self._arr_get(dev["techno"], 2, "ct")

        var ratio_ch1 = self._arr_get(dev["ratio"], 0, "1000")
        var ratio_ch2 = self._arr_get(dev["ratio"], 1, "1000")
        var ratio_ch3 = self._arr_get(dev["ratio"], 2, "1000")

        var pga_ch1 = self._arr_get(dev["PGA"], 0, "1")
        var pga_ch2 = self._arr_get(dev["PGA"], 1, "1")
        var pga_ch3 = self._arr_get(dev["PGA"], 2, "1")

        var mode_ch1 = self._arr_get(dev["mode"], 0, "tri")
        var mode_ch2 = self._arr_get(dev["mode"], 1, "tri")
        var mode_ch3 = self._arr_get(dev["mode"], 2, "tri")

        self.pending_cfg_cmd = string.format(
            "SET CONFIG %s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s:%s\n",
            global.device,
            root_ch1, root_ch2, root_ch3,
            product_name,
            techno_ch1, techno_ch2, techno_ch3,
            ratio_ch1, ratio_ch2, ratio_ch3,
            pga_ch1, pga_ch2, pga_ch3,
            mode_ch1, mode_ch2, mode_ch3
        )

        self.cfg_attempts = 0
        self.cfg_ack = false
        self.cfg_next_send_ms = tasmota.millis() + 1200
        print("CFG: prepared for STM32")
    end

    def push_config_once()
        if self.pending_cfg_cmd == nil
            return
        end

        # Ensure STM32 is released from reset before sending config.
        tasmota.cmd("start")
        tasmota.delay(1200)
        global.ser.flush()
        global.ser.write(bytes().fromstring(self.pending_cfg_cmd))
        self.cfg_attempts = 1
        print("CFG: cmd=" + self.pending_cfg_cmd)
        print("CFG: sent once at init")
    end

    def fast_loop()
        self.read_uart(2)
    end

    def process_uart_line(line)
        var topic
        var split
        var ligne

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
            if string.find(line, "config done") != -1
                self.cfg_ack = true
                self.pending_cfg_cmd = nil
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