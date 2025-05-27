import mqtt
import string
import json
import global
import math

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

    var previous_state
    var current_state

    var Energy
    var previousPower
    var tick
    var conso


    def ack_setup_device(topic, idx, payload_s, payload_b)
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
        self.every_minute()
    end

    def ack_setup_general(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end

        var newtopic
        var payload



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

        newtopic = string.format("gw/%s/%s/chauffage_general/set/SETUP", global.client, global.ville)
        payload = string.format('{"Device":"%s","Name":"chauffage_general","TYPE":"SETUP","DATA":%s}', 
        global.device, buffer)
        mqtt.publish(newtopic, payload, true)

        self.every_minute()

        # gpio.digital_write(self.gate, self.setup_general['mode'] == 'MANUEL' ? 0 : 1)
    end

    def init()
        var file
        var myjson
        print('-----------------------------------------')
        print('- CHX Driver init                       -')
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
        self.previous_state = 0
        self.current_state = 0
        tasmota.set_timer(30000,/-> self.push_device_general_setup())
        
        import conso
        self.conso = conso
        self.previousPower = 0
        self.tick = 0
        self.Energy = 0
        print('-----------------------------------------')
    end

    def push_device_general_setup()
        var file
        var myjson        
        var name
        var  newtopic
        var payload
        print('-----------------------------------------')
        print('- push_device_general_setup             -')

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
        newtopic = string.format("gw/%s/%s/chauffage_general/set/SETUP", global.client, global.ville, global.device )
        payload = string.format('{"Device":"%s","Name":"chauffage_general","TYPE":"SETUP","DATA":%s}',
                global.device, myjson)
        mqtt.publish(newtopic, payload, true)
        print('-----------------------------------------')
    end

    # Function to subscribe to MQTT topics
    def subscribes()
        var topic 
        # chauffage

        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.ack_setup_device(topic, idx, payload_s, payload_b))
        topic = string.format("app/%s/%s/chauffage_general/set/SETUP", global.client, global.ville)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.ack_setup_general(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to device SETUP and generale SETUP for : "+global.device)
    end

    def every_hour()
        var now = tasmota.rtc()
        var rtc = tasmota.time_dump(now["local"])
        var hour = rtc["hour"]
        # publish if not midnight
        if hour != 23
            self.conso.mqtt_publish('hours')
        end
        self.conso.sauvegarde()
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
        if(data == nil)
            return
        end
        if(hour >= 6 && hour <9)
            global.slot = "matin"
        elif(hour >= 9 && hour < 17)
            global.slot = "journee"
        elif(hour >= 17 && hour < 23)
            global.slot = "soir"
        else
            global.slot = "nuit"
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
        global.temperature = myjson["AHT2X"]["Temperature"]
        global.humidity = myjson["AHT2X"]["Humidity"]    
        var payload
        var topic

        global.targetHum = self.setup_general['absence']['humidite']


        if(self.setup_general['mode']=='AUTO')
            if (self.setup_device['linked'] == true)
                global.target = self.setup_general[jour][global.slot]
            else
                global.target = self.setup_device[jour][global.slot]
            end
            if (global.temperature < global.target+self.setup_device['offset'])
                gpio.digital_write(self.gate, 0)
                global.power = 1
                tasmota.delay(2000)
            else
                gpio.digital_write(self.gate, 1)
                global.power = 0
                tasmota.delay(2000)
            end
            if self.current_state != global.power
                self.setup_device['alarm'] = true
            else
                self.setup_device['alarm'] = false
            end
        elif(self.setup_general['mode']=='ABSENCE')
            global.target = self.setup_general['absence']['temperature']
            if (global.temperature < global.target+self.setup_device['offset'] || global.humidity > global.targetHum)
                gpio.digital_write(self.gate, 0)
                global.power = 1
                tasmota.delay(2000)
            else
                gpio.digital_write(self.gate, 1)
                global.power = 0
                tasmota.delay(2000)
            end
            if self.current_state != global.power
                self.setup_device['alarm'] = true
            else
                self.setup_device['alarm'] = false
            end
        else # mode MANUEL
            global.target = 99
            gpio.digital_write(self.gate, 0)
            global.power = self.current_state

        end  

        topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"aht20":%.2f,"Humidity":%.2f,"slot":"%s","offset":%.1f,"location":"%s","Target":%.1f,"TargetHum":%d,"Power":%d,"mode":"%s","linked":%s,"puissance":%d,"alarm":%s}',
                global.device, global.device, global.temperature-self.setup_device['offset'], global.temperature,global.humidity,global.slot,self.setup_device['offset'],global.location,global.target,global.targetHum,global.power,self.setup_general['mode'],self.setup_device['linked'],self.setup_device['puissance'],self.setup_device['alarm'])
        mqtt.publish(topic, payload, true)
    end

    def every_second()
        var data = tasmota.read_sensors()
        var myjson = json.load(data)
        var measured_power = myjson["ENERGY"]["Power"]
        if(measured_power > 50)
            # sauvegarde de la puissance du chauffage
            if(self.setup_device['puissance'] == 0)
                self.setup_device['puissance'] = int((myjson['ENERGY']['Power']+250) / 500)*500
                var file = open("setup_device.json", "wt")
                file.write(json.dump(self.setup_device))
                file.close()
            end
            self.current_state = 1
        else
            self.current_state = 0
        end
        if(self.current_state != self.previous_state)
            self.previous_state = self.current_state
            self.every_minute()
        end
        # sauvegarde de l'energie
        self.Energy += real((measured_power + self.previousPower) / 2)
        self.tick+=1
        self.previousPower = measured_power
        if self.tick == 15
            self.tick = 0
            self.Energy=real(real(self.Energy)/real(3600))
            self.conso.update(self.Energy)
            self.Energy = 0
        end
    end
end

chx = CHX()
tasmota.add_driver(chx)
var now = tasmota.rtc()
var delay
var mycron
math.srand(size(global.device)*size(global.ville))
var random = math.rand()
delay = random % 10
# set midnight cron
mycron = string.format("59 %d 23 * * *", 50 + delay)
tasmota.add_cron(mycron, /-> chx.midnight(), "every_day")
mqttprint("cron midnight:" + mycron)
# set hour cron
mycron = string.format("59 %d * * * *", 50 + delay)
tasmota.add_cron(mycron, /-> chx.every_hour(), "every_hour")
mqttprint("cron hour:" + mycron)

tasmota.add_cron("0 * * * * *", /-> chx.every_minute(), "every_min_@0_s")