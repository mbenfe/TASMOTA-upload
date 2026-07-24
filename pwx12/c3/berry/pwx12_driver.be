var version = "23072028 json"

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
    var root
    var topic 
    var conso
    var last_cfg_mode
    var rx_tail

    def debug_ctx(tag)
        var has_cfg = (global.configjson != nil)
        var has_channels = false
        if has_cfg
            has_channels = global.configjson.contains("channels")
        end
        print(string.format("PWX12 DBG [%s] ville=%s device=%s client=%s cfg=%s cfg_has_channels=%s",
            tag,
            str(global.ville),
            str(global.device),
            str(global.client),
            str(has_cfg),
            str(has_channels)
        ))
    end

    def init()
        print('PWX12 LOAD: entering PWX12.init')
        print('PWX12 LOAD: before import conso')
        import conso
        print('PWX12 LOAD: after import conso')
        self.conso = conso

        print('DRIVER: serial init done')
        print('heap:', tasmota.get_free_heap())
        self.debug_ctx('init')
    end

    def fast_loop()
        self.read_uart(10)
    end

    def publish_power_json(myjson)
        if myjson == nil || !myjson.contains("power")
            return false
        end
        var power = myjson["power"]
        var logical_index = 0
        for slot: 0..self.conso.slot_count() - 1
            var slot_values = power[slot]
            var slot_mode = self.conso.slot_mode(slot)
            if slot_mode == "mono"
                for phase: 0..2
                    var channel_name = self.conso.slot_channel_name(slot, phase)
                    if channel_name != "*"
                        var topic = string.format("gw/%s/%s/%s-%d/tele/POWER", global.client, global.ville, global.device, logical_index + 1)
                        var value = real(slot_values[phase])
                        var ligne = string.format('{"Device": "%s","Name":"%s","ActivePower":%.1f}', global.device, channel_name, value)
                        mqtt.publish(topic, ligne, true)
                    end
                    logical_index += 1
                end
            else
                var channel_name = self.conso.slot_channel_name(slot, 0)
                if channel_name != "*"
                    var topic = string.format("gw/%s/%s/%s-%d/tele/POWER", global.client, global.ville, global.device, logical_index + 1)
                    var value = real(slot_values[0])
                    var ligne = string.format('{"Device": "%s","Name":"%s","ActivePower":%.1f}', global.device, channel_name, value)
                    mqtt.publish(topic, ligne, true)
                end
                logical_index += 1
            end
        end
        return true
    end

    def publish_config_json(myjson)
        var topic = string.format("gw/%s/%s/%s/tele/CONFIG", global.client, global.ville, global.device)
        mqtt.publish(topic, json.dump(myjson), true)
        print('PWX12 CONFIG->', json.dump(myjson))
    end

    def process_uart_line(line)
        var topic
        var split
        var myjson

        if string.find(line, 'BOOT:') == 0
            var boot_parts = string.split(line, 'BOOT:')
            if size(boot_parts) < 2 || size(boot_parts[1]) == 0
                print('PWX12-> malformed BOOT frame:', line)
                return
            end

            myjson = json.load(boot_parts[1])
            if myjson == nil
                print('PWX12-> invalid BOOT JSON:', line)
                return
            end

            topic = string.format("gw/%s/%s/%s/tele/INFO_STM32", global.client, global.ville, global.device)
            mqtt.publish(topic, boot_parts[1], true)
            return
        end

        if line[0] == 'D'
            split = string.split(line, ':')
            if size(split) >= 4 && size(split[1]) > 0 && size(split[2]) > 0 && size(split[3]) > 0
                topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                mqtt.publish(topic, line, true)
            else
                print('PWX12-> malformed D frame:', line)
            end
        elif line[0] == '{'
            myjson = json.load(line)
            if myjson == nil
                print('PWX12-> invalid JSON:', line)
                return
            end

            if myjson.contains("type") && myjson["type"] == "calibration"
                if string.find(line, '"group":"') != -1
                    topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                    mqtt.publish(topic, line, true)
                else
                    topic = string.format("gw/%s/%s/%s/tele/CALIBRATION", global.client, global.ville, global.device)
                    mqtt.publish(topic, line, true)
                end
            elif myjson.contains("slots")
                self.publish_config_json(myjson)
            elif myjson.contains("power")
                self.publish_power_json(myjson)
                topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                mqtt.publish(topic, line, true)
            elif myjson.contains("energy")
                self.conso.update_energy_payload(myjson)
                topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                mqtt.publish(topic, line, true)
            else
                topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                mqtt.publish(topic, line, true)
            end
        else
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
            if self.rx_tail != nil && size(self.rx_tail) > 0
                mystring = self.rx_tail + mystring
            end
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
            self.rx_tail = mylist[numitem - 1]
        end
    end

    def midnight()
        self.debug_ctx('midnight start')
        self.conso.mqtt_publish('all')
        print('PWX12 DBG [midnight] calling command: nightday')
        tasmota.cmd('nightday')
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



print('PWX12 LOAD: creating PWX12 instance')
global.pwx12 = PWX12()
print('PWX12 LOAD: PWX12 instance created')
print('PWX12 LOAD: before add_driver')
tasmota.add_driver(global.pwx12)
print('PWX12 LOAD: after add_driver')
var now = tasmota.rtc()

print('PWX12 LOAD: before add_fast_loop')
tasmota.add_fast_loop(/-> global.pwx12.fast_loop())
print('PWX12 LOAD: after add_fast_loop')

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
