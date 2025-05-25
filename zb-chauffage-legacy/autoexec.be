import mqtt
import string
import json
import global
import zigbee

var client = 'benfeghoul'
var ville = 'marcq-en-baroeul'
var mapConfigs = {}
var mapSensors = {}
var mapThermostat = {}
var listSetup = []

# indicateurs readiness
var numSensors = 9  # znp lance
var subscribed = false
var ready = false

######################################################################
#  config & commands received from mobile application:
#  onoff: switch chauffage on/off
#  mode  : change chauffage mode
#  absence: get absence parameters
#  semaine: get semaine parameters
#  weekend: get weekend parameters
def onoff(topic, idx, payload_s, payload_b)
    var ts = string.split(topic,'/')       
    var json = json.load(payload_s)
    var command
     command = string.format("Zbsend {\"Device\":\"%s\",\"send\":{\"Power\":2}}",ts[3])
     tasmota.cmd(command)
     print(command)
     return true
end

def mode(topic, idx, payload_s, payload_b)
    var ts = string.split(topic,'/')       
    var json = json.load(payload_s)
    var command  = "PAS DE COMMAND"  
    if !mapThermostat.contains(ts[3])
        mapThermostat.insert(ts[3],{})
    end
    if !mapThermostat[ts[3]].contains('Mode')
        if json['MODE'] == 'MANUEL'
            mapThermostat[ts[3]].insert('Mode',0)
         end
         if json['MODE'] == 'AUTO'
            mapThermostat[ts[3]].insert('Mode',1)
         end
         if json['MODE'] == 'ABSENCE'
            mapThermostat[ts[3]].insert('Mode',2)
         end
       end
    if(json['MODE']=='MANUEL')
      command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/14102000\"}",ts[3])
      global.listSetup.push(command)
    end
    if(json['MODE']=='AUTO')
      command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/14102001\"}",ts[3])
      global.listSetup.push(command)
    end
    if(json['MODE']=='ABSENCE')
      command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/14102002\"}",ts[3])
      global.listSetup.push(command)
    end
    return true
end

def absence(topic, idx, payload_s, payload_b)
    var ts = string.split(topic,'/')       
    var json = json.load(payload_s)
    var command 
    # ajoute le device si pas encore enregistre
    if !mapThermostat.contains(ts[3])
        mapThermostat.insert(ts[3],{})
    end
    if !mapThermostat[ts[3]].contains('AwayTemp')
        mapThermostat[ts[3]].insert('AwayTemp',json['TEMPERATURE'])
    end
    if !mapThermostat[ts[3]].contains('AwayHum')
        mapThermostat[ts[3]].insert('AwayHum',json['HUMIDITE'])
    end
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/381020%02X\"}",ts[3],json['TEMPERATURE'])
    global.listSetup.push(command)
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/391020%02X\"}",ts[3],json['HUMIDITE'])
    global.listSetup.push(command)
    return true
end

def semaine(topic, idx, payload_s, payload_b)
    var ts = string.split(topic,'/')
    var json = json.load(payload_s)
    var command    
    if !mapThermostat.contains(ts[3])
        mapThermostat.insert(ts[3],{})
    end
 
    if !mapThermostat[ts[3]].contains('SemaineMatin')
        mapThermostat[ts[3]].insert('SemaineMatin',json['MATIN'])
    end
    if !mapThermostat[ts[3]].contains('SemaineJournee')
        mapThermostat[ts[3]].insert('SemaineJournee',json['JOURNEE'])
    end
    if !mapThermostat[ts[3]].contains('SemaineSoir')
        mapThermostat[ts[3]].insert('SemaineSoir',json['SOIR'])
    end
    if !mapThermostat[ts[3]].contains('SemaineNuit')
        mapThermostat[ts[3]].insert('SemaineNuit',json['NUIT'])
    end
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/301020%02X\"}",ts[3],json['MATIN'])
    global.listSetup.push(command)
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/311020%02X\"}",ts[3],json['JOURNEE'])
    global.listSetup.push(command)
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/321020%02X\"}",ts[3],json['SOIR'])
    global.listSetup.push(command)
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/331020%02X\"}",ts[3],json['NUIT'])
    global.listSetup.push(command)
    return true
end

def weekend(topic, idx, payload_s, payload_b)
    var ts = string.split(topic,'/')
    var json = json.load(payload_s)
    var command    
    if !mapThermostat.contains(ts[3])
        mapThermostat.insert(ts[3],{})
    end

    if !mapThermostat[ts[3]].contains('WeMatin')
        mapThermostat[ts[3]].insert('WeMatin',json['MATIN'])
    end
    if !mapThermostat[ts[3]].contains('WeJournee')
        mapThermostat[ts[3]].insert('WeJournee',json['JOURNEE'])
    end
    if !mapThermostat[ts[3]].contains('WeSoir')
        mapThermostat[ts[3]].insert('WeSoir',json['SOIR'])
    end
    if !mapThermostat[ts[3]].contains('WeNuit')
        mapThermostat[ts[3]].insert('WeNuit',json['NUIT'])
    end
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/341020%02X\"}",ts[3],json['MATIN'])
    global.listSetup.push(command)
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/351020%02X\"}",ts[3],json['JOURNEE'])
    global.listSetup.push(command)
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/361020%02X\"}",ts[3],json['SOIR'])
    global.listSetup.push(command)
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/371020%02X\"}",ts[3],json['NUIT'])
    global.listSetup.push(command)
   return true
end

def subscribes()
    var topic 
    # chauffages
    topic = string.format("app/%s/%s/+/set/ONOFF",client,ville)
    mqtt.subscribe(topic, onoff)
    print("subscribed to ONOFF")
    topic = string.format("app/%s/%s/+/set/MODE",client,ville)
    mqtt.subscribe(topic, mode)
    print("subscribed to MODE")
    topic = string.format("app/%s/%s/+/set/ABSENCE",client,ville)
    mqtt.subscribe(topic, absence)
    print("subscribed to ABSENCE")
    topic = string.format("app/%s/%s/+/set/WEEKEND",client,ville)
    mqtt.subscribe(topic, weekend)
    print("subscribed to WEEKEND")
    topic = string.format("app/%s/%s/+/set/SEMAINE",client,ville)
    mqtt.subscribe(topic, semaine)
    print("subscribed to SEMAINE")
end

tasmota.cmd('seriallog 0')

tasmota.load('readiness_driver.be')