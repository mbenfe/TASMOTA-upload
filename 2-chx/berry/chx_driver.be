import mqtt
import string
import json
import global

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, texte, true)
    return true
end

class CHX
    var gate
    var day_list
    var setups

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
            self.setups['mode'] = myjson['data']['mode']
            # attention ne pas changer offset !!!!!!!!
            self.setups['ouvert'] = myjson['data']['ouvert']
            self.setups['ferme'] = myjson['data']['ferme']
            self.setups['lundi'] = myjson['data']['lundi']
            self.setups['mardi'] = myjson['data']['mardi']
            self.setups['mercredi'] = myjson['data']['mercredi']
            self.setups['jeudi'] = myjson['data']['jeudi']
            self.setups['vendredi'] = myjson['data']['vendredi']
            self.setups['samedi'] = myjson['data']['samedi']
            self.setups['dimanche'] = myjson['data']['dimanche']
        else
            self.setups['mode'] = myjson['mode']
            # attention ne pas changer offset !!!!!!!!
            self.setups['ouvert'] = myjson['ouvert']
            self.setups['ferme'] = myjson['ferme']
            self.setups['lundi'] = myjson['lundi']
            self.setups['mardi'] = myjson['mardi']
            self.setups['mercredi'] = myjson['mercredi']
            self.setups['jeudi'] = myjson['jeudi']
            self.setups['vendredi'] = myjson['vendredi']
            self.setups['samedi'] = myjson['samedi']
            self.setups['dimanche'] = myjson['dimanche']
        end
        
        var buffer = json.dump(self.setups)
        var name = "thermostat_intermarche.json"
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
        var file = open("thermostat_intermarche.json", "rt")
        var myjson = file.read()
        file.close()
        self.setups = json.load(myjson)  
        self.gate = 19
        self.day_list = ["dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"]
        mqttprint("subscription MQTT")
        self.subscribes()
        gpio.pin_mode(self.gate, gpio.OUTPUT)
        gpio.digital_write(self.gate, 0)    # allumé gete is inverted
        tasmota.set_timer(30000,/-> self.mypush())
    end

    def mypush()
        var file
        var myjson        
        var name = "thermostat_intermarche.json"
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

        def check_gpio()
        # Check if GPIOs are configured correctly
        var gpio_result = tasmota.cmd("Gpio")
        
        if gpio_result != nil
             
            # Check GPI21 (SDA-1 - 640)
            if gpio_result['GPIO21'] != nil
                if !gpio_result['GPIO21'].contains('640')
                    mqttprint("WARNING: GPIO21 not SDA-1! Reconfiguring...")
                    tasmota.cmd("Gpio21 640")
                end
            end
            
            # Check GPIO09 (SCL-1 - 608)
            if gpio_result['GPIO9'] != nil
                if !gpio_result['GPIO9'].contains('608')
                    mqttprint("WARNING: GPIO9 not SCL-1! Reconfiguring...")
                    tasmota.cmd("Gpio9 608")
                end
            end
        else
            mqttprint("ERROR: Cannot read GPIO configuration")
            return false
        end
        
        return true
    end


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
        var data

        self.check_gpio()

        data = tasmota.read_sensors()
        if(data == nil)
            return
        end
        var myjson = json.load(data)
        if(!myjson.contains("AHT2X"))
            return
        end
        var temperature = myjson["AHT2X"]["Temperature"]
        var humidity = myjson["AHT2X"]["Humidity"]    
        var target
        if (hour >= self.setups[jour]['debut'] && hour < self.setups[jour]['fin'])
            target = self.setups['ouvert']
        else
            target = self.setups['ferme']
        end
        var payload
        var power
        var topic
        if(self.setups['mode']==1)
            if( hour >= self.setups[jour]['debut'] && hour < self.setups[jour]['fin'] )
                if (temperature < self.setups['ouvert']+self.setups['offset'])
                    gpio.digital_write(self.gate, 0)
                    power = 1
                else
                    gpio.digital_write(self.gate, 1)
                    power = 0
                end
            else
                if (temperature < self.setups['ferme']+self.setups['offset'])
                    gpio.digital_write(self.gate, 0)
                    power = 1
                else
                    gpio.digital_write(self.gate, 1)
                    power = 0
                end
            end    
        else
            gpio.digital_write(self.gate, 0)
            power = 1
        end    
        topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"aht20":%.2f,"Humidity":%.2f,"ouvert":%.1f,"ferme":%1.f,"offset":%.1f,"location":"%s","Target":%.1f,"Power":%d,"mode":%d}',
                global.device, global.device, temperature-self.setups['offset'], temperature,humidity,self.setups['ouvert'],self.setups['ferme'],self.setups['offset'],global.location,target,power,self.setups['mode'])
        mqtt.publish(topic, payload, true)
    end

    def every_second()
    end
end

chx = CHX()
tasmota.add_driver(chx)
tasmota.add_cron("0 * * * * *", /-> chx.every_minute(), "every_min_@0_s")