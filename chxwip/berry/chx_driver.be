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
    var aht20
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

    def every_minute()
        var now = tasmota.rtc()
        var rtc=tasmota.time_dump(now["local"])
        var second = rtc["sec"]
        var minute = rtc["min"]
        var hour = rtc["hour"]
        var day = rtc["day"]
        var month = rtc["month"]
        var year = rtc["year"]
        var day_of_week = rtc["weekday"]  # 0=Sunday, 1=Monday, ..., 6=Saturday
        var jour = self.day_list[day_of_week]
        var data = aht20.poll()
        if(data == nil)
            return
        end
        var target
        if (hour >= self.setups[jour]['debut'] && hour < self.setups[jour]['fin'])
            target = self.setups['ouvert']
        else
            target = self.setups['ferme']
        end
        var temperature = data[0]
        var humidity = data[1]
        var payload
        var power
        var topic
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
        topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"Humidity":%.2f,"ouvert":%.1f,"ferme":%1.f,"offset":%.1f,"location":"%s","Target":%.1f,"Power":%d,"mode":%d}',
                global.device, global.device, temperature, humidity,self.setups['ouvert'],self.setups['ferme'],self.setups['offset'],global.location,target,power,self.setups['mode'])
        mqtt.publish(topic, payload, true)
    end

    def every_second()
    end
end

chx = CHX()
chx.init()
tasmota.add_driver(chx)
tasmota.add_cron("0 * * * * *", /-> chx.every_minute(), "every_min_@0_s")