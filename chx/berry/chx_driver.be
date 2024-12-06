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

    def onoff(topic, idx, payload_s, payload_b)

        print('onoff:',topic,' ', payload_s)
        gpio.digital_write(self.gate, 0)
    end

    def mode(topic, idx, payload_s, payload_b)
        print('mode:',topic,' ', payload_s)
    end

    def isemaine(topic, idx, payload_s, payload_b)
        print('isemaine:',topic,' ', payload_s)
    end

    def init()
        self.gate = 19
        mqttprint("subscription MQTT")
        self.subscribes()
        gpio.pin_mode(self.gate, gpio.OUTPUT)
        gpio.digital_write(self.gate, 1)    
    end

    def subscribes()
        var topic 
        # chauffages
        topic = string.format("app/%s/%s/%s/set/ONOFF", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.onoff(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to ONOFF")
        topic = string.format("app/%s/%s/%s/set/MODE", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.mode(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to MODE")
        topic = string.format("app/%s/%s/%s/set/ISEMAINE", global.client, global.ville,global.device)
        mqtt.subscribe(topic, /topic, idx, payload_s, payload_b -> self.isemaine(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to ISEMAINE")
    end

    def every_minute()
        var data = aht20.poll()
        if(data == nil)
            return
        end
        var payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"Humidity":%.2f}', global.device, global.device, data[0], data[1])
        var topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        mqtt.publish(topic, payload, true)
    end

    def every_second()
    end
end

chx = CHX()
chx.init()
tasmota.add_driver(chx)
tasmota.add_cron("0 * * * * *", /-> chx.every_minute(), "every_min_@0_s")