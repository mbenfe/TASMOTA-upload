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
    var relay
    var day_list
    var count

    def check_gpio()
        # Check if GPIOs are configured correctly
        var gpio_result = tasmota.cmd("Gpio")
        
        if gpio_result != nil
            # Check GPIO7 (DS18x20-1 - 1312)
            if gpio_result['GPIO7'] != nil
                if !gpio_result['GPIO7'].contains('1312')
                    mqttprint("WARNING: GPIO7 not DS18x20-1! Reconfiguring...")
                    tasmota.cmd("Gpio7 1312")
                end
            end
            
            # Check GPIO8 (SDA-1 - 640)
            if gpio_result['GPIO8'] != nil
                if !gpio_result['GPIO8'].contains('640')
                    mqttprint("WARNING: GPIO8 not SDA-1! Reconfiguring...")
                    tasmota.cmd("Gpio8 640")
                end
            end
            
            # Check GPIO18 (SCL-1 - 608)
            if gpio_result['GPIO18'] != nil
                if !gpio_result['GPIO18'].contains('608')
                    mqttprint("WARNING: GPIO18 not SCL-1! Reconfiguring...")
                    tasmota.cmd("Gpio18 608")
                end
            end
            
            # Check GPIO19 (DS18x20-2 - 1313) - LAST
            if gpio_result['GPIO19'] != nil
                if !gpio_result['GPIO19'].contains('1313')
                    mqttprint("WARNING: GPIO19 not DS18x20-2! Reconfiguring...")
                    tasmota.cmd("Gpio19 1313")
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
        var arguments = string.split(topic, '/')

        var newtopic
        var payload
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)

        global.setup['onoff'] = myjson['DATA']['onoff']
        global.setup['fanspeed'] = myjson['DATA']['fanspeed']
        global.setup['heatpower'] = myjson['DATA']['heatpower']
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

        # Update both LEDs and relays when setup changes via MQTT
        if global.pcf != nil
            global.pcf.update_onoff_led()
            global.pcf.update_heat_power_leds()
            global.pcf.update_fan_speed_leds()
            global.pcf.update_relays()  # ← Add this line
            mqttprint("LEDs and relays updated from MQTT")
        else
            mqttprint("Warning: PCF driver not available")
        end
        
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
        tasmota.set_timer(30000,/-> self.mypush())

        # Initialize relays based on loaded setup (with delay to ensure PCF is ready)
        tasmota.set_timer(2000, /-> self.init_relays())

        if(global.config["remote"] != "nok")
            self.subscribes_sensors(global.config["remote"])  # Subscribe to remote sensor topic
        end

    end

    def init_relays()
        if global.pcf != nil
            global.pcf.update_relays()
            mqttprint("Relays initialized from setup")
        else
            mqttprint("Warning: PCF driver not ready, retrying...")
            tasmota.set_timer(1000, /-> self.init_relays())  # Retry in 1 second
        end
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
        var day_of_week = rtc["weekday"]
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
        elif(global.tempsource[0] == "pt")
            temperature = global.average_temperature
        elif(global.tempsource[0] == "remote")
            temperature = global.remote_temp[0]
        else
            temperature = 99
        end

        if (hour >= global.setup[jour]['debut'] && hour < global.setup[jour]['fin'])
            target = global.setup['ouvert']

            if (temperature < target && global.setup['onoff'] == 1)
                power = 1  # Heating ON
            else
                power = 0  # Heating OFF
            end
        else
            power = 0  # Outside schedule
            target = global.setup['ferme']
        end

        # # Only update relays if power state has changed (0→1 or 1→0)
         #         if global.pcf != nil
        #             global.pcf.update_relays()
        #         end
        
        payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"ouvert":%.1f,"ferme":%.1f,"fanspeed":%d,"heatpower":%d,"location":"%s","Target":%.1f,"source":"%s","Power":%d}', 
                global.device, global.device, temperature, global.setup['ouvert'], global.setup['ferme'], global.setup['fanspeed'], global.setup['heatpower'], global.location, target, global.tempsource[0], power)
        topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        mqtt.publish(topic, payload, true)
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