import mqtt
import string
import json
import global

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client,global.ville, global.device)
    mqtt.publish(topic, texte, true)
    return true
end

class CHX
    var gate
    var day_list
    var setup_device
    var setup_general


    def mysetup_device(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end

        print("-----------------------------------------------------------------")
        print(myjson)

        var newtopic
        var payload
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)

        self.setup_device['linked'] = myjson['DATA']['linked']
        # attention ne pas changer offset !!!!!!!!
        self.setup_device['semaine'] = myjson['DATA']['semaine']
        self.setup_device['weekend'] = myjson['DATA']['weekend']
        
        var buffer = json.dump(self.setup_device)
        var name = "setup_device.json"
        var file = open(name, "wt")
        if file == nil
            mqttprint("Error: Failed to open file for writing")
            return
        end
        file.write(buffer)
        file.close()
        payload = string.format('{"Device":"%s","Name":"%s","TYPE":"SETUP","DATA":%s}', 
        global.device, global.device, buffer)
        mqtt.publish(newtopic, payload, true)
    end

    def mysetup_general(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end

        var newtopic
        var payload

        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)


        self.setup_general['mode'] = myjson['DATA']['mode']
        self.setup_device['mode'] = myjson['DATA']['mode']
        self.setup_general['semaine'] = myjson['DATA']['semaine']
        self.setup_general['weekend'] = myjson['DATA']['weekend']
        self.setup_general['absence'] = myjson['DATA']['absence']
        
        var buffer = json.dump(self.setup_general)
        var name = "setup_general.json"
        var file = open(name, "wt")
        if file == nil
            mqttprint("Error: Failed to open file for writing")
            return
        end
        file.write(buffer)
        file.close()

        payload = string.format('{"Device":"%s","Name":"chauffage_general","TYPE":"SETUP","DATA":%s}', 
        global.device, buffer)
        mqtt.publish(newtopic, payload, true)

        self.every_minute()

        # gpio.digital_write(self.gate, self.setup_general['mode'] == 'MANUEL' ? 0 : 1)
    end

    def init()
        var file
        var myjson
        # read setup_device.json
        file = open("setup_device.json", "rt")
        myjson = file.read()
        file.close()
        self.setup_device = json.load(myjson)  
        # read setup_general.json
        file = open("setup_general.json", "rt")
        myjson = file.read()
        file.close()
        self.setup_general = json.load(myjson)  
        
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
        var name
        var  newtopic
        var payload

        name = "setup_device.json"
        file = open(name, "rt")
        if file == nil
            mqttprint("Error: Failed to open file " + name)
            return
        end
        myjson = file.read()
        file.close()
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device )
        payload = string.format('{"Device":"%s","Name":"%s","TYPE":"SETUP","DATA":%s}',
                global.device, global.device, myjson)
        mqtt.publish(newtopic, payload, true)

        name = "setup_general.json"
        file = open(name, "rt")
        if file == nil
            mqttprint("Error: Failed to open file " + name)
            return
        end
        myjson = file.read()
        file.close()
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device )
        payload = string.format('{"Device":"%s","Name":"chauffage_general","TYPE":"SETUP","DATA":%s}',
                global.device, myjson)
        mqtt.publish(newtopic, payload, true)
    end

    # Function to subscribe to MQTT topics
    def subscribes()
        var topic 
        # chauffage

        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mysetup_device(topic, idx, payload_s, payload_b))
        topic = string.format("app/%s/%s/chauffage_general/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mysetup_general(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to device SETUP and generale SETUP for : "+global.device)
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
        var data = tasmota.read_sensors()
        var slot
        if(data == nil)
            return
        end
        if(hour >= 6 && hour <9)
            slot = "matin"
        elif(hour >= 9 && hour < 17)
            slot = "journee"
        elif(hour >= 17 && hour < 23)
            slot = "soir"
        else
            slot = "nuit"
        end
        if (day_of_week == 0 || day_of_week == 6)
            jour = "weekend"
        else
            jour = "semaine"
        end   
        var myjson = json.load(data)
        if(!myjson.contains("AHT2X"))
            return
        end
        var temperature = myjson["AHT2X"]["Temperature"]
        var humidity = myjson["AHT2X"]["Humidity"]    
        var target
        var payload
        var power
        var topic

        if(self.setup_general['mode']=='AUTO')
            if (self.setup_device['linked'] == true)
                target = self.setup_general[jour][slot]
            else
                target = self.setup_device[jour][slot]
            end
            if (temperature < target+self.setup_device['offset'])
                gpio.digital_write(self.gate, 0)
                power = 1
            else
                gpio.digital_write(self.gate, 1)
                power = 0
            end
        elif(self.setup_general['mode']=='ABSENCE')
            target = self.setup_general['absence']['temperature']
            if (temperature < target+self.setup_device['offset'])
                gpio.digital_write(self.gate, 0)
                power = 1
            else
                gpio.digital_write(self.gate, 1)
                power = 0
            end
        else # mode MANUEL
            target = 99
            gpio.digital_write(self.gate, 0)
            power = 1
        end  
        topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"aht20":%.2f,"Humidity":%.2f,"slot":"%s","offset":%.1f,"location":"%s","Target":%.1f,"Power":%d,"mode":"%s","linked":%s}',
                global.device, global.device, temperature-self.setup_device['offset'], temperature,humidity,slot,self.setup_device['offset'],global.location,target,power,self.setup_general['mode'],self.setup_device['linked'])
        mqtt.publish(topic, payload, true)
    end

    def every_second()
    end
end

chx = CHX()
tasmota.add_driver(chx)
tasmota.add_cron("0 * * * * *", /-> chx.every_minute(), "every_min_@0_s")