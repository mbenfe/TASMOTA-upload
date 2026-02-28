import mqtt
import string
import json
import global


def mqttprint(texte)
    var payload =string.format("{\"texte\":\"%s\"}", texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, payload, true)
    return true
end

def get_cron_second()
    var combined = string.format("%s|%s", global.ville, global.device)
    var sum = 0
    for i : 0 .. size(combined) - 1
        sum += string.byte(combined[i])
    end
    print("Debug: Sum of ASCII values for " + combined + " is " + str(sum))
    return sum % 60
end


class CLIMAIR
    var day_list
    var count

    def check_gpio()

        # Check if GPIOs are configured correctly
        var gpio_result = tasmota.cmd("Gpio")
        
        if gpio_result != nil
            # Check GPIO8 (DS18x20-1 - 1312)
            if gpio_result['GPIO8'] != nil
                if !gpio_result['GPIO8'].contains('DS18x201')
                    mqttprint("WARNING: GPIO8 not DS18x20-1! Reconfiguring...")
                    tasmota.cmd("Gpio8 1312")
                end
            end
            
            # Check GPIO20 (DS18x20-2 - 1313)
            if gpio_result['GPIO20'] != nil
                if !gpio_result['GPIO20'].contains('DS18x202')
                    mqttprint("WARNING: GPIO20 not DS18x20-2! Reconfiguring...")
                    tasmota.cmd("Gpio20 1313")
                end
            end
        else
            mqttprint("ERROR: Cannot read GPIO configuration")
            return false
        end
        
        return true
    end

    def mysetup(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end
        print( "mysetup called")
        print( "Topic: " + topic)
        print( "SETUP data received: " + payload_s)
        var arguments = string.split(topic, '/')
        if global.device != arguments[3]
            mqttprint("Error: Device " + arguments[3] + " not matching " + global.device)
            return
        end
        var newtopic
        var payload
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)

        global.setup['onoff'] = myjson['DATA']['onoff']
        # attention ne pas changer offset !!!!!!!!
        global.setup['ouvert'] = myjson['DATA']['ouvert']
        global.setup['ferme'] = myjson['DATA']['ferme']
        global.setup['lundi'] = myjson['DATA']['lundi']
        global.setup['mardi'] = myjson['DATA']['mardi']
        global.setup['mercredi'] = myjson['DATA']['mercredi']
        global.setup['jeudi'] = myjson['DATA']['jeudi']
        global.setup['vendredi'] = myjson['DATA']['vendredi']
        global.setup['samedi'] = myjson['DATA']['samedi']
        global.setup['dimanche'] = myjson['DATA']['dimanche']
       
        var buffer = json.dump(global.setup)
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
        self.every_minute()  # Update the state immediately
    end

    def update_app_with_mysetup(topic, idx, payload_s, payload_b)
        var arguments = string.split(topic, '/')
        if global.device != arguments[3]
            mqttprint("Error: Device " + arguments[3] + " not matching " + global.device)
            return
        end
        var newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        var buffer = json.dump(global.setup)
        var payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}', 
        global.device, global.device, buffer)
        mqtt.publish(newtopic, payload, true)
        tasmota.delay(5)
        self.every_minute()
    end

    # Initialization function
    def init()
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
        global.setup = json.load(myjson)
        print(global.setup)
        if global.setup == nil
            mqttprint("Error: Failed to parse JSON from file " + name)
            return
        end
        self.day_list = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
        mqttprint("subscription MQTT...")
        self.subscribes()
        mqttprint('MQTT subscription done')
        global.relay = 19
        gpio.pin_mode(global.relay, gpio.OUTPUT)
        gpio.digital_write(global.relay, 0)
        tasmota.set_timer(30000,/-> self.mypush())

        if(global.config["remote"] != "nok")
            self.subscribes_sensors(global.config["remote"])
        end
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
        var  newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        var payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}',
            global.device, global.device, myjson)
        mqtt.publish(newtopic, payload, true)
    end

    # Function to subscribe to MQTT topics
    def subscribes()
        var topic 
        # climair
        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mysetup(topic, idx, payload_s, payload_b))
        topic = string.format("app/%s/%s/%s/get/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.update_app_with_mysetup(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to SETUP:"+global.device)
    end

    # Function to execute every minute
    # Function to execute every minute
    def every_minute()
        var now = tasmota.rtc()
        var rtc = tasmota.time_dump(now["local"])
        var second = rtc["sec"]
        var minute = rtc["min"]
        var hour = rtc["hour"]
        var day = rtc["day"]
        var month = rtc["month"]
        var year = rtc["year"]
        var day_of_week = rtc["weekday"]  # 0=Sunday, 1=Monday, ..., 6=Saturday
        var jour = self.day_list[day_of_week]

        var payload
        var topic
        var target
        var power
        var temperature = 99

        self.check_gpio()

        if(global.tempsource[0] == "ds")
            temperature = ds18b20.poll("ds")
        elif(global.tempsource[0] == "dsin")
            temperature = ds18b20.poll("dsin")
        elif(global.tempsource[0] == "remote")
            temperature = global.remote_temp
        else
            temperature = 99
        end

        if (hour >= global.setup[jour]['debut'] && hour < global.setup[jour]['fin'])
            target = global.setup['ouvert']

            if (temperature < target && global.setup['onoff'] == 1)
                gpio.digital_write(global.relay, 1)
                power = 1
            else
                gpio.digital_write(global.relay, 0)
                power = 0
            end
        else
            target = global.setup['ferme']
            if (temperature < target && global.setup['onoff'] == 1)
                gpio.digital_write(global.relay, 1)
                power = 1
            else
                gpio.digital_write(global.relay, 0)
                power = 0
            end
        end

        payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"ouvert":%.1f,"ferme":%.1f,"offset":%.1f,"location":"%s","Target":%.1f,"source":"%s","Power":%d,"onoff":%d}', 
            global.device, global.device, temperature-global.setup['offset'], global.setup['ouvert'], global.setup['ferme'], global.setup['offset'], global.location, target, global.tempsource[0], power,global.setup['onoff'])
        topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        mqtt.publish(topic, payload, true)
    end

    # Function to execute every second
    def every_second()
    end

    def remote_sensor(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        print("remote sensor data received: " + payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end
        var sensor = myjson["Name"]
        if global.config["remote"] != sensor
            mqttprint("Error: Device " + sensor + " not found in config")
            return
        end
        if myjson.contains("Temperature")
            global.remote_temp = real(myjson["Temperature"])
        else
            mqttprint("Error: Temperature data not found in payload for device " + sensor)
        end
    end
    # Function to subscribe to MQTT topics
    def subscribes_sensors(sensor)
        var topic
        topic = string.format("gw/%s/%s/zb-%s/tele/SENSOR", global.client, global.ville, sensor)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.remote_sensor(topic, idx, payload_s, payload_b))
        print("subscribed to remote sensor:" + topic)
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

var climair = CLIMAIR()
global.climair = climair
tasmota.add_driver(climair)
var cron_second = get_cron_second()
print("Cron second for device " + global.device + " is " + str(cron_second))
var cron_pattern = string.format("%d * * * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> climair.every_minute(), "every_min_@0_s")
cron_pattern = string.format("%d %d * * * *", cron_second, cron_second)
tasmota.add_cron(cron_pattern, /-> climair.heartbeat(), "every_hour_@0_s")