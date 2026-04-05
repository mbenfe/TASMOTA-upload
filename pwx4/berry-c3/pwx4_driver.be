var version = "1.0.0 avec couts"

import mqtt
import string
import json

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
        self.ser = global.ser
        if self.ser == nil
            print('DRIVER ERROR: global.ser is nil, Init() must run in autoexec before loading driver')
            return
        end
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

        var root_name = self._arr_get(dev["root"], 0, "*")
        var sensor_techno = self._arr_get(dev["techno"], 0, "ct")
        var current_ratio = self._arr_get(dev["ratio"], 0, "1000")
        var pga_gain = self._arr_get(dev["PGA"], 0, "1")
        var mode = self._arr_get(dev["mode"], 0, "tri")

        # PWX4 compact config payload: single-channel parameters only.
        self.pending_cfg_cmd = string.format(
            "SET CONFIG %s:%s:%s:%s:%s:%s\n",
            root_name,
            produit,
            sensor_techno,
            current_ratio,
            pga_gain,
            mode
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
        print("CFG: cmd=" + self.pending_cfg_cmd)
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
            var mystring = buffer.asstring()
            var mylist = string.split(mystring, '\n')
            var numitem = size(mylist)
            var topic
            var split
            var ligne
            for i: 0..numitem-2
                var line = mylist[i]
                if size(line) == 0
                    continue
                end
                if line[0] == 'C'
                    split = string.split(line, ':')
                    if size(split) >= 2 && size(split[1]) > 0
                        self.conso.update(line)
                        topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                        mqtt.publish(topic, line, true)
                    else
                        print('PWX4-> malformed C frame:', line)
                    end
                elif line[0] == 'D'
                    split = string.split(line, ':')
                    if size(split) >= 2 && size(split[1]) > 0
                        topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                        mqtt.publish(topic, line, true)
                    else
                        print('PWX4-> malformed D frame:', line)
                    end
                elif line[0] == 'W'
                    split = string.split(line, ':')
                    if size(split) >= 2
                        if global.configjson[global.device]["root"][0] != "*"
                            topic = string.format("gw/%s/%s/%s/tele/POWER", global.client, global.ville, global.device)
                            ligne = string.format('{"Device": "%s","Name":"%s","ActivePower":%.1f}', global.device, global.configjson[global.device]["root"][0], real(split[1]))
                            mqtt.publish(topic, ligne, true)
                        end
                    else
                        print('PWX4-> malformed W frame:', line)
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
                    end
                else
                    if string.find(line, "config done") != -1
                        self.cfg_ack = true
                        self.pending_cfg_cmd = nil
                        print("CFG: STM32 acknowledged")
                    end
                    print('PWX4->', line)
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
        self.ser.write(bytes().fromstring("GET ENERGY\n"))
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

global.pwx4 = PWX4()
tasmota.add_driver(global.pwx4)
var now = tasmota.rtc()
tasmota.add_fast_loop(/-> global.pwx4.fast_loop())

var cron_second = get_cron_second()
# set midnight cron
var cron_pattern = string.format("%d 59 23 * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> global.pwx4.midnight(), "every_day")
print("cron midnight:" + cron_pattern)
# set hour cron
cron_pattern = string.format("%d 59 * * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> global.pwx4.hour(), "every_hour")
print("cron hour:" + cron_pattern)
# set heartbeat cron
cron_pattern = string.format("%d %d * * * *", cron_second, cron_second)
tasmota.add_cron(cron_pattern, /-> global.pwx4.heartbeat(), "every_hour")
print("cron heartbeat:" + cron_pattern)
# set 4 hours cron
cron_pattern = string.format("%d 0 */4 * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> global.pwx4.every_4hours(), "every_4_hours")
print("cron every 4 hours:" + cron_pattern)
