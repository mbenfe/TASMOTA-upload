import mqtt
import string
import json

class Common
    var device
    var ville
    var location
    var client

    def mqttprint(texte)
        var topic = string.format("gw/inter/%s/%s/tele/PRINT", self.ville, self.device)
        mqtt.publish(topic, texte, true)
    end

    def loadconfig()
        var file = open("esp32.cfg", "rt")
        var buffer = file.read()
        file.close()
        var myjson = json.load(buffer)
        self.ville = myjson["ville"]
        self.device = myjson["device"]
        self.location = myjson["location"]
        self.client = myjson["client"]
    end

    def init()
        self.loadconfig()
    end
end

var common = Common()
common.init()
global.common = common
print("common initialization done")