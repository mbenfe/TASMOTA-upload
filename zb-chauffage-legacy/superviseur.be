import zigbee
import string
import mqtt
import strict

import global
 
class superviseur
  var message
 var hexa
  var token
  var listeSensors
  var listeConfigs

  ###############################################################################
  #
  ###############################################################################
  def init()
    global.mapSensors = {}
    global.mapConfigs = {}
  end

  ###############################################################################
  #
  ###############################################################################
  def exist(liste,key)
    for i:0..liste.size()-1
        if liste.item(i).key == key
            return true
        end
    end
    return false
  end

  ###############################################################################
  #
  ###############################################################################
  def removeAll(liste)
    while liste.size()!=0
        liste.remove(0)
    end
  end

  ###############################################################################
  #
  ###############################################################################
  def attributes_refined(event_type, frame, attr_list, idx)

    var device

    self.hexa = string.format("0x%04X",idx)

    device = zigbee[number(self.hexa)]
    
     # ajoute le device a la listeSensors si il n'y est pas
    if !global.mapSensors.contains(device.name)
        global.mapSensors.insert(device.name,{})
    end

    if !global.mapConfigs.contains(device.name)
        global.mapConfigs.insert(device.name,{})
    end
    
    self.listeSensors = global.mapSensors[device.name]
    self.listeConfigs = global.mapConfigs[device.name]
    # !!! attention necessaire pour enlever les bugs
    tasmota.delay(5)
    for i:0..size(attr_list)-1
        if self.listeSensors.contains(attr_list.item(i).key)
            self.listeSensors[attr_list.item(i).key] = attr_list.item(i).val
        else
           if attr_list.item(i).key == 'Temperature' || attr_list.item(i).key == 'Humidity' 
            || attr_list.item(i).key == 'Mode' || attr_list.item(i).key == 'Target' 
            || attr_list.item(i).key == 'Power' || attr_list.item(i).key == 'AwayHum' 
            || attr_list.item(i).key == 'AwayHum' || attr_list.item(i).key == 'OffsetTemp' 
               self.listeSensors.insert(attr_list.item(i).key,attr_list.item(i).val)
           end
        end
        if self.listeConfigs.contains(attr_list.item(i).key)
            self.listeConfigs[attr_list.item(i).key] = attr_list.item(i).val
        else
            if attr_list.item(i).key == 'SemaineMatin' || attr_list.item(i).key == 'SemaineJournee' || attr_list.item(i).key == 'SemaineSoir' || attr_list.item(i).key == 'SemaineNuit' 
                || attr_list.item(i).key == 'WeMatin' || attr_list.item(i).key == 'WeJournee' || attr_list.item(i).key == 'WeSoir' || attr_list.item(i).key == 'WeNuit' 
                || attr_list.item(i).key == 'AwayTemp' || attr_list.item(i).key == 'AwayHum' || attr_list.item(i).key == 'LocalTime'
                self.listeConfigs.insert(attr_list.item(i).key,attr_list.item(i).val)
            end
        end
    end

     # efface tous les attribus pour annuler l'envoi mqtt automatique
     self.removeAll(attr_list)
  end

  ###############################################################################
  #
  ###############################################################################
  def sauvegarde(jsonpayload,nomFichier)
     var buffer
     var logmap
     var file = open(nomFichier,'rt')
     if size(file) == 0
        logmap = {}
     else
        buffer = file.read(file.size()) 
        logmap = json.load(buffer)
     end
     file.close()
     if logmap.contains(jsonpayload["Name"])
        logmap.setitem(jsonpayload["Name"],jsonpayload)
     else
        logmap.insert(jsonpayload["Name"],jsonpayload)
     end
     file = open(nomFichier,'wt')
     file.write(json.dump(logmap))
     file.close()
  end
  ###############################################################################
  #
  ###############################################################################
  def every_minute_sensors() 
    var Name
    var payload
    var topic
     var listeSensors

    if global.mapSensors.size()==0
       print('listeSensors vide')
       return
    end
    print('liste setup',global.listSetup.size())
    print('sensors')
    for k:global.mapSensors.keys()
        payload = string.format('{"Device":"%s","Name":"%s"',k,k)
        listeSensors = global.mapSensors[k]
      # !!! attention necessaire pour enlever les bugs
      tasmota.delay(5)
        for cle:listeSensors.keys()
            payload+=',"'+cle+'":'+str(listeSensors[cle])
        end
        payload+='}'
        topic = "gw/"+global.client+"/"+global.ville+"/"+k+"/tele/SENSOR"
        self.sauvegarde(json.load(payload),'back_sensors.json')
        mqtt.publish(topic,payload,true)
        # print('sensor:',payload)
    end
  end


  ###############################################################################
  #
  ###############################################################################
  def every_minute_configs() 
    var Name
    var payload
    var topic
    var listeConfigs

    if global.mapConfigs.size()==0
       print('listeConfigs vide')
       return
    end
    print('configs')
    for k:global.mapConfigs.keys()
        payload = string.format('{"Device":"%s","Name":"%s"',k,k)
        listeConfigs = global.mapConfigs[k]
      # !!! attention necessaire pour enlever les bugs
      tasmota.delay(5)
        for cle:listeConfigs.keys()
            payload+=',"'+cle+'":'+str(listeConfigs[cle])
        end
        payload+='}'
        topic = "gw/"+global.client+"/"+global.ville+"/"+k+"/tele/SENSOR"
        self.sauvegarde(json.load(payload),'back_configs.json')
        # mqtt.publish(topic,payload,true)
        print('configs:',size(listeConfigs),' ',payload)
    end
  end

  ###############################################################################
  #
  ###############################################################################
  def every_minute_hum() 
    var payload
    if global.mapSensors.size()==0
       print('listeSensors vide')
       return
    end
    for k:global.mapSensors.keys()
        payload = string.format('ZbSend {"Device":"%s","Name":"%s","cluster":"0x0006","read":"0x1039"}',k,k)
        tasmota.delay(500)
        tasmota.cmd(payload)
    end
  end


  ###############################################################################
  #
  ###############################################################################
  def zbtime() 

    var device 
    var command
    for k:global.mapSensors.keys()
       device = zigbee[number(k)]
       command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x000A","Read":"0x0007"}',device.name) # ok
       tasmota.cmd(command)
    end
  end


end


var superviseur = superviseur()
zigbee.add_handler(superviseur)

tasmota.add_cron("0 * * * * *", /-> superviseur.every_minute_sensors(), "every_min_@0_s")
tasmota.add_cron("10 * * * * *", /-> superviseur.every_minute_configs(), "every_min_@10_s")
tasmota.add_cron("15 * * * * *", /-> superviseur.every_minute_hum(), "every_min_@15_s")

tasmota.add_cmd('zbtime',/->superviseur.zbtime())