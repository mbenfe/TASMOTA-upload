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
    print("cron for " + combined + " is " + str(sum % 60))
    return sum % 60
end

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, texte, true)
    return true
end

class PLUGX
    var gate
    var setups

    def in_window(hour, window)
        if window == nil
            return false
        end
        return hour >= window['debut'] && hour < window['fin']
    end

    def is_active(hour)
        return self.in_window(hour, self.setups['am']) || self.in_window(hour, self.setups['pm'])
    end

    def set_power(is_on)
        gpio.digital_write(self.gate, is_on ? 0 : 1)
    end

    def load_setup_from_json(myjson)
        if myjson == nil
            return
        end

        self.setups['mode'] = myjson['mode']
        self.setups['am'] = myjson['am']
        self.setups['pm'] = myjson['pm']
    end

    def mysetup(topic, idx, payload_s, payload_b)
        var myjson = json.load(string.tolower(payload_s))
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end

        print("-----------------------------------------------------------------")
        print(myjson)

        var newtopic
        var payload
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)

        if(myjson.contains("data"))
            self.load_setup_from_json(myjson['data'])
        else
            self.load_setup_from_json(myjson)
        end
        
        var buffer = json.dump(self.setups)
        var name = "setup.json"
        var file = open(name, "wt")
        if file == nil
            mqttprint("Error: Failed to open file for writing")
            return
        end
        file.write(buffer)
        file.close()
        payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}', 
        global.device, global.device, buffer)
        mqtt.publish(newtopic, payload, true)

        gpio.digital_write(self.gate, self.setups['mode'] == 0 ? 1 : 0)
    end

    def init()
        var file = open("setup.json", "rt")
        var myjson = file.read()
        file.close()
        self.setups = json.load(myjson)  
        self.gate = 19
        mqttprint("subscription MQTT")
        self.subscribes()
        gpio.pin_mode(self.gate, gpio.OUTPUT)
        gpio.digital_write(self.gate, 0)    # allumé gete is inverted
        tasmota.set_timer(30000,/-> self.mypush())
    end

    def mypush()
        var file
        var myjson        
        var name = "setup.json"
        file = open(name, "rt")
        if file == nil
            mqttprint("Error: Failed to open file " + name)
            return
        end
        myjson = file.read()
        file.close()
        var  newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device )
        var payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}',
                global.device, global.device, myjson)
        mqtt.publish(newtopic, payload, true)
    end

    # Function to subscribe to MQTT topics
    def subscribes()
        var topic 
        # chauffage

        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mysetup(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to SETUP:"+global.device)
    end


    def every_minute()
        var now = tasmota.rtc()
        var rtc = tasmota.time_dump(now["local"])
        var hour = rtc["hour"]
        var data

        data = tasmota.read_sensors()
        var myjson = nil
        var temperature = 0
        var humidity = 0
        if(data != nil)
            myjson = json.load(data)
            if(myjson != nil && myjson.contains("AHT2X"))
                temperature = myjson["AHT2X"]["Temperature"]
                humidity = myjson["AHT2X"]["Humidity"]
            end
        end    
        var active = self.setups['mode'] == 1 && self.is_active(hour)
        var power = active ? 1 : 0
        self.set_power(power == 1)
        topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        payload = string.format('{"Device":"%s","Name":"%s","aht20":%.2f,"Humidity":%.2f,"location":"%s","Target":%d,"Power":%d,"mode":%d,"am":{"debut":%.1f,"fin":%.1f},"pm":{"debut":%.1f,"fin":%.1f}}',
                global.device, global.device, temperature, humidity, global.location, power, power, self.setups['mode'], self.setups['am']['debut'], self.setups['am']['fin'], self.setups['pm']['debut'], self.setups['pm']['fin'])
        mqtt.publish(topic, payload, true)
    end

    def every_second()
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

plugx = PLUGX()
tasmota.add_driver(plugx)
var cron_second = get_cron_second()
var cron_pattern = string.format("%d * * * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> plugx.every_minute(), "every_minute")
print("cron minute:" + cron_pattern)

cron_pattern = string.format("%d %d * * * *", cron_second, cron_second)
tasmota.add_cron(cron_pattern, /-> plugx.heartbeat(), "every_hour")
print("cron heartbeat:" + cron_pattern)