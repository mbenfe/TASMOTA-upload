import mqtt
import string
import json
import global


def mqttprint(texte)
    var payload =string.format("{\"texte\":\"%s\"}", texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.esp_device)
    mqtt.publish(topic, payload, true)
    return true
end

class AEROTHERME
    var day_list
    var count

    def mysetup(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end
        var arguments = string.split(topic, '/')
        var index = 99
        for i:0..size(global.config)-1
            if global.devices[i] == arguments[3]
                index = i
                break
            end
        end
        if(index == 99)
            mqttprint("Error: Device " + arguments[3] + " not found in device list")
            return
        end
        var newtopic
        var payload
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, arguments[3])

        global.setups[index]['onoff'] = myjson['DATA']['onoff']
        # attention ne pas changer offset !!!!!!!!
        global.setups[index]['ouvert'] = myjson['DATA']['ouvert']
        global.setups[index]['ferme'] = myjson['DATA']['ferme']
        global.setups[index]['lundi'] = myjson['DATA']['lundi']
        global.setups[index]['mardi'] = myjson['DATA']['mardi']
        global.setups[index]['mercredi'] = myjson['DATA']['mercredi']
        global.setups[index]['jeudi'] = myjson['DATA']['jeudi']
        global.setups[index]['vendredi'] = myjson['DATA']['vendredi']
        global.setups[index]['samedi'] = myjson['DATA']['samedi']
        global.setups[index]['dimanche'] = myjson['DATA']['dimanche']
       
        var buffer = json.dump(global.setups[index])
        var name = "setup_" + str(index + 1) + ".json"
        var file = open(name, "wt")
        if file == nil
            mqttprint("Error: Failed to open file for writing")
            return
        end
        file.write(buffer)
        file.close()
        
        payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}', 
        global.esp_device, arguments[3], buffer)
        mqtt.publish(newtopic, payload, true)

        # switch on/off leds
        global.pcf.onoff(global.setups[index]['onoff'],index)
        self.every_minute()  # Update the state immediately
    end

    # Initialization function
    def init()
        var file
        var myjson        
        global.setups = list()
        for i:0..global.nombre-1
            var name = "setup_" + str(i + 1) + ".json"
            file = open(name, "rt")
            if file == nil
                mqttprint("Error: Failed to open file " + name)
                continue
            end
            myjson = file.read()
            file.close()
            var json_data = json.load(myjson)
            print(json_data)
            if json_data == nil
                mqttprint("Error: Failed to parse JSON from file " + name)
                continue
            end
            global.setups.insert(i,json_data)  
        end 
        self.day_list = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
        mqttprint("subscription MQTT...")
        self.subscribes()
        mqttprint('MQTT subscription done')
        global.relay = list()
        global.relay.insert(0, 19)
        global.relay.insert(1, 18)
        gpio.pin_mode(global.relay[0], gpio.OUTPUT)
        gpio.pin_mode(global.relay[1], gpio.OUTPUT)
        gpio.digital_write(global.relay[0], 0)  # Set relay 1 to OFF
        gpio.digital_write(global.relay[1], 0)  # Set relay 2 to OFF
        tasmota.set_timer(30000,/-> self.mypush())

        for i:0..global.nombre-1
            if(global.config[i]["remote"] != "nok")
                self.subscribes_sensors(global.config[i]["remote"])  # Subscribe to remote sensor topic
            end
        end       
    end

    def mypush()
        var file
        var myjson        
        for i:0..global.nombre-1
            var name = "setup_" + str(i + 1) + ".json"
            file = open(name, "rt")
            if file == nil
                mqttprint("Error: Failed to open file " + name)
                continue
            end
            myjson = file.read()
            file.close()
            var  newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.devices[i])
            var payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}',
                    global.esp_device, global.devices[i], myjson)
            mqtt.publish(newtopic, payload, true)
        end 
    end

    # Function to subscribe to MQTT topics
    def subscribes()
        var topic 
        # aerotherme
        for i:0..global.nombre-1
            topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.devices[i])
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mysetup(topic, idx, payload_s, payload_b))
            mqttprint("subscribed to SETUP:"+global.devices[i])
        end
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
        var temperature = [99,99]

        for i:0..global.nombre-1
            if(global.tempsource[i][0] == "ds")
                temperature[i] = ds18b20.poll("ds")
            elif(global.tempsource[i][0] == "dsin")
                temperature[i] = ds18b20.poll("dsin")
            elif(global.tempsource[i][0] == "pt")
                temperature[i] = global.average_temperature
            elif(global.tempsource[i][0] == "remote")
                temperature[i] = global.remote_temp[i]
            else
                temperature[i] = 99
            end
        end

        for i:0..global.nombre-1
            if (hour >= global.setups[i][jour]['debut'] && hour < global.setups[i][jour]['fin'])
                target = global.setups[i]['ouvert']

                if (temperature[i] < target && global.setups[i]['onoff'] == 1)
                    gpio.digital_write(global.relay[i], 1)
                    power = 1
                else
                    gpio.digital_write(global.relay[i], 0)
                    power = 0
                end
            else
                target = global.setups[i]['ferme']
                if (temperature[i] < target && global.setups[i]['onoff'] == 1)
                    gpio.digital_write(global.relay[i], 1)
                    power = 1
                else
                    gpio.digital_write(global.relay[i], 0)
                    power = 0
                end
            end

            payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"ouvert":%.1f,"ferme":%.1f,"offset":%.1f,"location":"%s","Target":%.1f,"source":"%s","Power":%d,"onoff":%d}', 
                global.esp_device, global.devices[i], temperature[i]-global.setups[i]['offset'], global.setups[i]['ouvert'], global.setups[i]['ferme'], global.setups[i]['offset'], global.location[i], target, global.tempsource[i][0], power,global.setups[i]['onoff'])
            topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.devices[i])
            mqtt.publish(topic, payload, true)
        end
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
        var index = 99
        for i:0..size(global.config)-1
            if global.config[i]["remote"] == sensor
                index = i
                break
            end
        end
        if index == 99
            mqttprint("Error: Device " + sensor + " not found in config")
            return
        end
        if myjson.contains("Temperature")
            global.remote_temp[index] = real(myjson["Temperature"])
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
    

end

var aerotherme = AEROTHERME()
global.aerotherme = aerotherme  # Add this line to make aerotherme accessible globally
tasmota.add_driver(aerotherme)
tasmota.add_cron("0 * * * * *", /-> aerotherme.every_minute(), "every_min_@0_s")