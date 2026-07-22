var version = "2.0.0 avec cron specifique"

import mqtt
import string
import json

def get_cron_second()
    var combined = string.format("%s|%s", global.ville, global.device)
    var sum = 0
    for i : 0 .. size(combined) - 1
        sum += string.byte(combined[i])
    end
    print("cron for " + combined + " is " + str(sum % 60))
    return sum % 60
end


class PWX4
    var root
    var topic 
    var conso

    def init()
        import conso
        self.conso = conso

        print('heap:', tasmota.get_free_heap())
    end

    def _arr_get(arr, idx, fallback)
        if arr != nil && size(arr) > idx && arr[idx] != nil
            return str(arr[idx])
        end
        return fallback
    end

    def process_uart_line(line)
        var topic
        var split
        var ligne

        if string.find(line, "CONFIG ") == 0
            var payload = line[7..]
            split = string.split(payload, ':')
            var device_name = global.device
            var offset = 0
            var mode_value = "tri"
            if size(split) >= 7
                device_name = split[0]
                offset = 1
            end
            if size(split) >= offset + 6
                mode_value = string.tolower(str(split[offset + 5]))
                topic = string.format("gw/%s/%s/%s/tele/CONFIG", global.client, global.ville, global.device)
                if mode_value == "mono" && size(split) >= offset + 9
                    ligne = string.format(
                        '{"device":"%s","root":["%s"],"produit":"%s","techno":["%s"],"ratio":[%s],"PGA":[%s],"mode":["%s"],"phaseA_label":["%s"],"phaseB_label":["%s"],"phaseC_label":["%s"]}',
                        device_name,
                        split[offset + 0],
                        split[offset + 1],
                        split[offset + 2],
                        split[offset + 3],
                        split[offset + 4],
                        split[offset + 5],
                        split[offset + 6],
                        split[offset + 7],
                        split[offset + 8]
                    )
                else
                    ligne = string.format(
                        '{"device":"%s","root":["%s"],"produit":"%s","techno":["%s"],"ratio":[%s],"PGA":[%s],"mode":["%s"]}',
                        device_name,
                        split[offset + 0],
                        split[offset + 1],
                        split[offset + 2],
                        split[offset + 3],
                        split[offset + 4],
                        split[offset + 5]
                    )
                end
                mqtt.publish(topic, ligne, true)
                print('PWX4 CONFIG->', ligne)
            else
                print('PWX4-> malformed CONFIG frame:', line)
            end
            return
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
                var channels = global.configjson[global.device]["channels"]
                var mode_value = "tri"
                if channels != nil && size(channels) > 0 && channels[0].contains("mode")
                    mode_value = string.tolower(str(channels[0]["mode"]))
                end

                topic = string.format("gw/%s/%s/%s/tele/POWER", global.client, global.ville, global.device)
                if mode_value == "mono" && size(split) >= 4
                    var mono_idx = 0
                    for i : 0 .. size(channels) - 1
                        if string.tolower(str(channels[i]["mode"])) == "mono"
                            var channel_name = str(channels[i]["name"])
                            if channel_name != "*" && mono_idx + 1 < size(split)
                                ligne = string.format('{"Device": "%s","Name":"%s","ActivePower":%.1f}', global.device, channel_name, real(split[mono_idx + 1]))
                                mqtt.publish(topic, ligne, true)
                            end
                            mono_idx += 1
                            if mono_idx >= 3
                                break
                            end
                        end
                    end
                else
                    var channel_name = channels[0]["name"]
                    if channel_name != "*"
                        ligne = string.format('{"Device": "%s","Name":"%s","ActivePower":%.1f}', global.device, channel_name, real(split[1]))
                        mqtt.publish(topic, ligne, true)
                    end
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
            print('PWX4->', line)
        end
    end

    def midnight()
        self.conso.mqtt_publish('all')
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


def pwx4line(cmd, idx, payload, payload_json)
    if payload == nil || size(payload) == 0
        tasmota.resp_cmnd_done()
        return
    end
    if global.pwx4 != nil
        global.pwx4.process_uart_line(payload)
    end
    tasmota.resp_cmnd_done()
end



global.pwx4 = PWX4()
tasmota.add_driver(global.pwx4)
tasmota.add_cmd("pwx4line", pwx4line)
var now = tasmota.rtc()

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

# return pwx4
