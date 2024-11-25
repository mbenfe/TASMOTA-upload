var version = "1.0.112024 initial"

import mqtt
import string
import json
import common  # Import the common module

class CHX
    var aht20

    def init()
        self.aht20 = AHT20()
        self.aht20.init()
        self.subscribes()
    end

    def subscribes()
        var topic 
        # chauffages
        topic = string.format("app/%s/%s/+/set/ONOFF", common.client, common.ville)
        mqtt.subscribe(topic, onoff)
        mqttprint("subscribed to ONOFF")
        topic = string.format("app/%s/%s/+/set/MODE", common.client, common.ville)
        mqtt.subscribe(topic, mode)
        mqttprint("subscribed to MODE")
        topic = string.format("app/%s/%s/+/set/ABSENCE", common.client, common.ville)
        mqtt.subscribe(topic, absence)
        mqttprint("subscribed to ABSENCE")
        topic = string.format("app/%s/%s/+/set/WEEKEND", common.client, common.ville)
        mqtt.subscribe(topic, weekend)
        mqttprint("subscribed to WEEKEND")
        topic = string.format("app/%s/%s/+/set/SEMAINE", common.client, common.ville)
        mqtt.subscribe(topic, semaine)
        mqttprint("subscribed to SEMAINE")
    end

    def every_minute()
        var data = self.aht20.read_temperature_humidity()
        var payload = string.format('{"Device":"%s","Name":"%s","Temperature":%f,"Humidity":%f}', common.device, common.device, data[0], data[1])
        var topic = string.format("gw/%s/%s/%s/tele/SENSOR", common.client, common.ville, common.device)
        mqtt.publish(topic, payload, true)
    end

    def every_second()
    end
end

chx = CHX()
tasmota.add_driver(chx)
tasmota.add_cron("0 * * * * *", /-> chx.every_minute(), "every_min_@0_s")