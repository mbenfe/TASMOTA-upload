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

class RDX
    var day_list
    var count

    def mysetup(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end
        var arguments = string.split(topic, '/')

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

        # switch on/off leds
        global.pcf.onoff(global.setup['onoff'])
        self.every_minute()  # Update the state immediately
    end

    # Initialization function
    def init()
        var file
        var myjson        


        var name = "setup.json"
        file = open(name, "rt")
        if file == nil
            mqttprint("Error: Failed to open file " + name)
        end
        myjson = file.read()
        file.close()
        global.setup = json.load(myjson)
        if global.setup == nil
            mqttprint("Error: Failed to parse JSON from file " + name)
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
        print("set relay to ON")
        gpio.digital_write(global.relay[0], 1)  # Set relay 1 to ON
        gpio.digital_write(global.relay[1], 1)  # Set relay 2 to ON
        tasmota.delay(500)
        gpio.digital_write(global.relay[0], 0)  # Set relay 1 to OFF
        gpio.digital_write(global.relay[1], 0)  # Set relay 2 to OFF
        tasmota.delay(500)
        print("relay ON")
        gpio.digital_write(global.relay[0], 1)  # Set relay 1 to ON
        gpio.digital_write(global.relay[1], 1)  # Set relay 2 to ON

        tasmota.set_timer(30000,/-> self.mypush())


#        if(global.config["remote"] != "nok")
#            self.subscribes_sensors(global.config["remote"])  # Subscribe to remote sensor topic
#        end
    end

    def mypush()
        var file
        var myjson        
        var name = "setup.json"
        file = open(name, "rt")
        if file == nil
            mqttprint("Error: Failed to open file " + name)
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
        # aerotherme
        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mysetup(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to SETUP:"+global.device)
    end

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





        if (hour >= global.setup[jour]['debut'] && hour < global.setup[jour]['fin'])
                target = global.setup['ouvert']

            if (temperature < target && global.setup['onoff'] == 1)
#malek                gpio.digital_write(global.relay[i], 1)
                power = 1
            else
#malek                gpio.digital_write(global.relay[i], 0)
                power = 0
            end
            else
                target = global.setup['ferme']
                if (temperature < target && global.setup['onoff'] == 1)
#malek                    gpio.digital_write(global.relay[i], 1)
                    power = 1
                else
#malek                    gpio.digital_write(global.relay[i], 0)
                    power = 0
                end


            payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"ouvert":%.1f,"ferme":%.1f,"fandspeed":%d,"heatpower":%d,"location":"%s","Target":%.1f,"source":"%s","Power":%d}', 
                global.device, global.device, temperature, global.setup['ouvert'], global.setup['ferme'], global.setup['fanspeed'], global.setup['heatpower'], global.location, target, global.tempsource[0], power)
            topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
            mqtt.publish(topic, payload, true)
        end
    end

    # Function to execute every second
    def every_second()
    end

    def remote_sensor(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end
        var sensor = myjson["Name"]

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
    end
    

end

var rdx = RDX()
global.rdx = rdx  # Add this line to make rdx accessible globally
tasmota.add_driver(rdx)
tasmota.add_cron("0 * * * * *", /-> rdx.every_minute(), "every_min_@0_s")