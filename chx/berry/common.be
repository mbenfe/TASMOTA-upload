import mqtt
import string
import json

var device
var ville
var location

def mqttprint(texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", ville, device)
    mqtt.publish(topic, texte, true)
end

def loadconfig()
    var file = open("esp32.cfg", "rt")
    var buffer = file.read()
    file.close()
    var myjson = json.load(buffer)
    ville = myjson["ville"]
    device = myjson["device"]
    location = myjson["location"]
end

def init()
    loadconfig()
end

# Initialize the common module
init()