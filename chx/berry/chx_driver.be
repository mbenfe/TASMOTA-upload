import mqtt
import string
import json

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, texte, true)
end

def onoff(topic, idx, payload_s, payload_b)
end

def mode(topic, idx, payload_s, payload_b)
end

def absence(topic, idx, payload_s, payload_b)
end

def weekend(topic, idx, payload_s, payload_b)
end

def semaine(topic, idx, payload_s, payload_b)
end


class CHX
    var aht20

    def init()
        mqttprint("subscription MQTT")
        self.subscribes()
    end

    def subscribes()
        var topic 
        # chauffages
        topic = string.format("app/%s/%s/+/set/ONOFF", global.client, global.ville)
        mqtt.subscribe(topic, onoff)
        mqttprint("subscribed to ONOFF")
        topic = string.format("app/%s/%s/+/set/MODE", global.client, global.ville)
        mqtt.subscribe(topic, mode)
        mqttprint("subscribed to MODE")
        topic = string.format("app/%s/%s/+/set/ABSENCE", global.client, global.ville)
        mqtt.subscribe(topic, absence)
        mqttprint("subscribed to ABSENCE")
        topic = string.format("app/%s/%s/+/set/WEEKEND", global.client, global.ville)
        mqtt.subscribe(topic, weekend)
        mqttprint("subscribed to WEEKEND")
        topic = string.format("app/%s/%s/+/set/SEMAINE", global.client, global.ville)
        mqtt.subscribe(topic, semaine)
        mqttprint("subscribed to SEMAINE")
    end

    def every_minute()
        var data = aht20.read_temperature_humidity()
        if(data == nil)
            return
        end
        var payload = string.format('{"Device":"%s","Name":"%s","Temperature":%f,"Humidity":%f}', global.device, global.device, data[0], data[1])
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