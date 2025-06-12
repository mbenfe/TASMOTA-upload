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

class AEROTHERME
    var ds18b20
    var relay
    var day_list
    var setups
    var count

    def mysetup(topic, idx, payload_s, payload_b)
        var myjson = json.load(string.tolower(payload_s))
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end

        print("-----------------------------------------------------------------")

        var arguments = string.split(topic, '/')
        var device = string.split(arguments[3], '_')
        var i = int(device[1]) - 1
        var newtopic
        var payload
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, arguments[3])

        self.setups[i]['onoff'] = myjson['onoff']
        # attention ne pas changer offset !!!!!!!!
        self.setups[i]['ouvert'] = myjson['ouvert']
        self.setups[i]['ferme'] = myjson['ferme']
        self.setups[i]['lundi'] = myjson['lundi']
        self.setups[i]['mardi'] = myjson['mardi']
        self.setups[i]['mercredi'] = myjson['mercredi']
        self.setups[i]['jeudi'] = myjson['jeudi']
        self.setups[i]['vendredi'] = myjson['vendredi']
        self.setups[i]['samedi'] = myjson['samedi']
        self.setups[i]['dimanche'] = myjson['dimanche']
        
        var buffer = json.dump(self.setups[i])
        var name = "setup_" + str(i + 1) + ".json"
        var file = open(name, "wt")
        if file == nil
            mqttprint("Error: Failed to open file for writing")
            return
        end
        file.write(buffer)
        file.close()
        payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}', 
        global.device, arguments[3], buffer)
        mqtt.publish(newtopic, payload, true)

        gpio.digital_write(self.relay[i], self.setups[i]['onoff'])
    end

    # Initialization function
    def init()
        var file
        var myjson        
        self.setups = list()
        print("init setups")
        print(global.nombre)
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
            if json_data == nil
                mqttprint("Error: Failed to parse JSON from file " + name)
                continue
            end
            self.setups.insert(i,json_data)  
        end 
        print("init setups done")
        self.day_list = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
        mqttprint("subscription MQTT")
        self.subscribes()
        self.relay = list()
        self.relay.insert(0, 18)
        self.relay.insert(1, 19)
        gpio.pin_mode(self.relay[0], gpio.OUTPUT)
        gpio.digital_write(self.relay[0], 0)    
        gpio.pin_mode(self.relay[1], gpio.OUTPUT)
        gpio.digital_write(self.relay[1], 0)  
        self.count = 0  
        tasmota.set_timer(30000,/-> self.mypush())
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
            var  newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device + "_" + str(i + 1))
            var payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}',
                    global.device, global.device + "_" + str(i + 1), myjson)
            print('setup:', newtopic, ' ', payload)
            mqtt.publish(newtopic, payload, true)
        end 
    end

    # Function to subscribe to MQTT topics
    def subscribes()
        var topic 
        # aerotherme
        for i:0..global.nombre-1
            topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device + "_" + str(i + 1))
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mysetup(topic, idx, payload_s, payload_b))
            mqttprint("subscribed to SETUP:"+global.device + "_" + str(i + 1))
        end
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

        var temperature = ds18b20.poll()
        if (temperature == nil || temperature == -99)
            mqttprint("Error: Failed to read temperature from DS18B20")

        end

        print("--------------------------------------------------")
        print("PT1: ", global.average_temperature1, "°C   PT2: ", global.average_temperature2, "°C  heap: ", tasmota.get_free_heap())


        for i:0..global.nombre-1
            if (hour >= self.setups[i][jour]['debut'] && hour < self.setups[i][jour]['fin'])
                target = self.setups[i]['ouvert']
            else
                target = self.setups[i]['ferme']
            end

            payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"ouvert":%.1f,"ferme":%1.f,"offset":%.1f,"location":"%s","Target":%.f}', 
                    global.device, global.device+'_'+str(i+1), temperature-self.setups[i]['offset'], self.setups[i]['ouvert'], self.setups[i]['ferme'], self.setups[i]['offset'], global.location[i], target)
            topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device+"_"+str(i + 1))
            mqtt.publish(topic, payload, true)
            topic = string.format("gw/%s/%s/%s/tele/STATE", global.client, global.ville, global.device+"_"+str(i + 1))
            if (hour >= self.setups[i][jour]['debut'] && hour < self.setups[i][jour]['fin'])
                if (temperature < self.setups[i]['ouvert'] + self.setups[i]['offset'])
                    gpio.digital_write(self.relay[i], 0)
                    payload = string.format('{"Device":"%s","Name":"%s","Power":1}', global.device, global.device+"_"+str(i + 1))
                    mqtt.publish(topic, payload, true)
                else
                    gpio.digital_write(self.relay[i], 1)
                    payload = string.format('{"Device":"%s","Name":"%s","Power":0}', global.device, global.device+"_"+str(i + 1))
                    mqtt.publish(topic, payload, true)
                end
            else
                if (temperature < self.setups[i]['ferme'] + self.setups[i]['offset'])
                    gpio.digital_write(self.relay[i], 0)
                    payload = string.format('{"Device":"%s","Name":"%s","Power":1}', global.device, global.device+"_"+str(i + 1))
                    mqtt.publish(topic, payload, true)
                else
                    gpio.digital_write(self.relay[i], 1)
                    payload = string.format('{"Device":"%s","Name":"%s","Power":0}', global.device, global.device+"_"+str(i + 1))
                    mqtt.publish(topic, payload, true)
                end
            end        
        end
    end

    # Function to execute every second
    def every_second()
        # if (self.count == 5)
        #     var temperature = pt1000.poll(0)
        #     self.count = 0
        # else
        #     self.count = self.count + 1
        # end
#        print(temperature)
    end
end

var aerotherme = AEROTHERME()
tasmota.add_driver(aerotherme)
tasmota.add_cron("0 * * * * *", /-> aerotherme.every_minute(), "every_min_@0_s")