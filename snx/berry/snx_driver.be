var version = "1.0.042026 debug reorganized"

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


class STM32
    var errors
    var mapID
    var mapFunc
     var client 
    var ville
    var device
    var topic 
    var cout_values
    var cout_received
    var cout_required
    var cout_expected_name
    var cout_topic_to_key
    var cout_subscribed_topics
    var cout_pending_apply

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
        self.cout_values = {
            "cout_froid": 0.0,
            "cout_froid+": 0.0,
            "cout_froid-": 0.0
        }
        self.cout_received = {
            "cout_froid": true,
            "cout_froid+": true,
            "cout_froid-": true
        }
        self.cout_required = {
            "cout_froid": false,
            "cout_froid+": false,
            "cout_froid-": false
        }
        self.cout_expected_name = {}
        self.cout_topic_to_key = {}
        self.cout_subscribed_topics = {}
        self.cout_pending_apply = false

        self.loadconfig()

        print('DRIVER: serial init done')
    
        gpio.pin_mode(global.statistic_pin,gpio.OUTPUT)
        gpio.pin_mode(global.ready_pin,gpio.OUTPUT)

        # pin used as debuf from H7
        gpio.pin_mode(25,gpio.INPUT)
        gpio.pin_mode(26,gpio.INPUT)

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


    def reset_cout_state()
        self.cout_values["cout_froid"] = 0.0
        self.cout_values["cout_froid+"] = 0.0
        self.cout_values["cout_froid-"] = 0.0

        # If a key is not required for this city, it is considered received with default 0.
        self.cout_received["cout_froid"] = true
        self.cout_received["cout_froid+"] = true
        self.cout_received["cout_froid-"] = true

        self.cout_required["cout_froid"] = false
        self.cout_required["cout_froid+"] = false
        self.cout_required["cout_froid-"] = false

        self.cout_expected_name = {}
        self.cout_topic_to_key = {}
    end

    def prepare_cout_subscriptions_for_statistic()
        self.reset_cout_state()
        self.cout_pending_apply = true

        var file = open("config_cout.json", "rt")
        if file == nil
            self.send_stm32_cout_values()
            return
        end

        var raw = file.read()
        file.close()
        var cfg = json.load(raw)
        if cfg == nil || !cfg.contains(self.ville)
            self.send_stm32_cout_values()
            return
        end

        var city_cfg = cfg[self.ville]
        var owner_cfg = nil
        if city_cfg.contains("cout_owner")
            owner_cfg = city_cfg["cout_owner"]
        end

        var keys = ["cout_froid", "cout_froid+", "cout_froid-"]
        for k : keys
            var label = "none"
            if city_cfg.contains(k) && city_cfg[k] != nil
                label = str(city_cfg[k])
            end

            var owner = "none"
            if owner_cfg != nil && owner_cfg.contains(k) && owner_cfg[k] != nil
                owner = str(owner_cfg[k])
            end

            if label == "none" || owner == "none" || owner == "not_found" || size(label) == 0 || size(owner) == 0
                # Keep default 0 and mark as already resolved.
                self.cout_required[k] = false
                self.cout_received[k] = true
                continue
            end

            var expected_name = label
            if size(expected_name) >= 2
                if expected_name[0..1] != "c_"
                    expected_name = "c_" + expected_name
                end
            else
                expected_name = "c_" + expected_name
            end

            self.cout_required[k] = true
            self.cout_received[k] = false
            self.cout_expected_name[k] = expected_name

            var topic = string.format("gw/%s/%s/%s/tele/COUT", self.client, self.ville, owner)
            if !self.cout_topic_to_key.contains(topic)
                self.cout_topic_to_key[topic] = []
            end
            self.cout_topic_to_key[topic].push(k)
            if !self.cout_subscribed_topics.contains(topic)
                mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.on_cout_message(topic, idx, payload_s, payload_b))
                self.cout_subscribed_topics[topic] = true
            end
        end

        # If this city has no active COUT mapping, push default 0:0:0 immediately.
        self.try_apply_cout_values_to_stm32()
    end

    def on_cout_message(topic, idx, payload_s, payload_b)
        if !self.cout_pending_apply
            return
        end

        if !self.cout_topic_to_key.contains(topic)
            return
        end

        var data = json.load(payload_s)
        if data == nil || !data.contains("cout")
            return
        end

        if !data.contains("Name") || data["Name"] == nil
            return
        end
        var incoming_name = str(data["Name"])
        var keys = self.cout_topic_to_key[topic]
        for key : keys
            var expected_name = nil
            if self.cout_expected_name.contains(key)
                expected_name = self.cout_expected_name[key]
            end

            if expected_name != nil && incoming_name == expected_name
                self.cout_values[key] = real(data["cout"])
                self.cout_received[key] = true
            end
        end
        self.try_apply_cout_values_to_stm32()
    end

    def try_apply_cout_values_to_stm32()
        if !self.cout_pending_apply
            return
        end

        if !self.cout_received["cout_froid"] || !self.cout_received["cout_froid+"] || !self.cout_received["cout_froid-"]
            return
        end

        self.send_stm32_cout_values()
    end

    def send_stm32_cout_values()
        var x = real(self.cout_values["cout_froid"])
        var y = real(self.cout_values["cout_froid+"])
        var z = real(self.cout_values["cout_froid-"])

        var cmd = string.format("cout %.2f:%.2f:%.2f", x, y, z)
        if global.ser != nil
            global.ser.flush()
            global.ser.write(bytes().fromstring(cmd))
        end
        self.cout_pending_apply = false
        self.mqttprint("apply cout -> " + cmd)
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

stm32 = STM32()
global.stm32 = stm32
tasmota.add_driver(stm32)
var cron_second = get_cron_second()

var cron_pattern = string.format("%d %d 0 * * *", cron_second, cron_second)
tasmota.add_cron(cron_pattern, /-> stm32.get_statistic(), "every_day")
print("cron statistic:" + cron_pattern)

var cout_prepare_pattern = string.format("%d %d 0 * * *", cron_second, cron_second - 1)
tasmota.add_cron(cout_prepare_pattern, /-> stm32.prepare_cout_subscriptions_for_statistic(), "every_day_cout_prepare")
print("cron cout prepare:" + cout_prepare_pattern)

cron_pattern = string.format("%d %d * * * *", cron_second, cron_second)
tasmota.add_cron(cron_pattern, /-> stm32.heartbeat(), "every_hour")
print("cron heartbeat:" + cron_pattern)
