#---------------------------------#
# AUTOEXEC.BE 1.0 SNX             #
#---------------------------------#
import string
import global
import mqtt
import json
import gpio

var device
var ville

var ser                # serial object

var rx=4    
var tx=5    
var rst_in=19   
var bsl_in=21   
var rst_out=33   
var bsl_out=32   

#-------------------------------- FONCTIONS -----------------------------------------#
def init()
    import json
    var file = open("esp32.cfg","rt")
    var buffer = file.read()
    file.close()
    var myjson=json.load(buffer)
    ville=myjson["ville"]
    device=myjson["device"]
end

def mqttprint(texte)
    import mqtt
    var topic = string.format("gw/inter/%s/%s/tele/PRINT",ville,device)
    mqtt.publish(topic,texte,true)
end

#-------------------------------- COMMANDES -----------------------------------------#
def Stm32Reset(cmd, idx, payload, payload_json)
    if (payload=='in')
        gpio.pin_mode(rst_in,gpio.OUTPUT)
        gpio.pin_mode(bsl_in,gpio.OUTPUT)
        gpio.digital_write(rst_in, 1)
        gpio.digital_write(bsl_in, 0)
  
        gpio.digital_write(rst_in, 0)
        tasmota.delay(100)               # wait 10ms
        gpio.digital_write(rst_in, 1)
        tasmota.delay(100)               # wait 10ms
        tasmota.resp_cmnd('STM32 IN reset')
    end
    if (payload=='out')
        gpio.pin_mode(rst_out,gpio.OUTPUT)
        gpio.pin_mode(bsl_out,gpio.OUTPUT)
        gpio.digital_write(rst_out, 1)
        gpio.digital_write(bsl_out, 0)
  
        gpio.digital_write(rst_out, 0)
        tasmota.delay(100)               # wait 10ms
        gpio.digital_write(rst_out, 1)
        tasmota.delay(100)               # wait 10ms
        tasmota.resp_cmnd('STM32 OUT reset')
    end
end

def ville(cmd, idx,payload, payload_json)
    import json
    var file = open("esp32.cfg","rt")
    var buffer = file.read()
    var myjson=json.load(buffer)
    myjson["ville"]=payload
    buffer = json.dump(myjson)
    file.close()
    file = open("esp32.cfg","wt")
    file.write(buffer)
    file.close()
    tasmota.resp_cmnd('done')
end

def device(cmd, idx,payload, payload_json)
    import json
    var file = open("esp32.cfg","rt")
    var buffer = file.read()
    var myjson=json.load(buffer)
    myjson["device"]=payload
    buffer = json.dump(myjson)
    file.close()
    file = open("esp32.cfg","wt")
    file.write(buffer)
    file.close()
    tasmota.resp_cmnd('done')
end


def getfile(cmd, idx,payload, payload_json)
    import string
    import path
    var nom_fichier
    nom_fichier=string.split(payload,'/').pop()
    mqttprint(nom_fichier)
    var filepath = 'https://raw.githubusercontent.com//mbenfe/upload/main/'
    filepath+=payload
    mqttprint(filepath)
    var wc=webclient()
    wc.set_follow_redirects(true)
    wc.begin(filepath)
    var st=wc.GET()
    if st!=200 
        raise 'erreur','code: '+str(st) 
    end
    st='Fetched '+str(wc.write_file(nom_fichier))
    mqttprint(st)
    wc.close()
    var message = 'uploaded:'+nom_fichier
    tasmota.resp_cmnd(message)
    return st
end

def sendconfig(cmd, idx,payload, payload_json)
    import string
    import json
    var file
    var buffer
    var myjson
    var total = '';
    var ser
    var header
    mqttprint('send:'+payload)
    ############################ fichier config ###################
    file = open(payload,"rt")
    if file == nil
        mqttprint('fichier non existant:'+payload)
        return
    end
    mqttprint("read buffer")
    buffer = file.read()
    file.close()
    myjson = json.load(buffer)
    for key:myjson.keys()
        total+=key+' '+myjson[key]["Name"]+' '+myjson[key]["alias_sonde"]+' '+myjson[key]["alias_cutout"]+' '+myjson[key]["poste"]+' '+myjson[key]["categorie"]+' '+myjson[key]["genre"]+' '+myjson[key]["device"]+'\n'
    end
    header=string.format("config %d",myjson.size())
    header+='\n'
    header+=total
    ############################ fichier device ###################
    file = open("device.json","rt")
    if file == nil
        mqttprint('fichier device.json non existant:')
        return
    end
    buffer = file.read()
    file.close()
    myjson = json.load(buffer)
    total=''
    for key:myjson.keys()
        total+=key+' '+myjson[key]["name"]+' '+myjson[key]["type"]+' '+str(myjson[key]["ratio"])+' '+myjson[key]["categorie"]+'\n'
    end
    header+=string.format("device %d",myjson.size())
    header+='\n'
    header+=total
    ############################ fichier controler ###################
    file = open("controler.json","rt")
    if file == nil
        mqttprint('fichier controler non existant')
        return
    end
    buffer = file.read()
    file.close()
    myjson = json.load(buffer)
    total=''
    for key:myjson.keys()
        total+=key+' '+myjson[key]["name"]+' '+myjson[key]["type"]+' '+str(myjson[key]["ratio"])+' '+myjson[key]["categorie"]+'\n'
    end
    header+=string.format("controler %d",myjson.size())
    header+='\n'
    header+=total
    mqttprint('taille initiale:'+str(size(header)))
    var reste = 32 - ((size(header)+6) % 32)
    mqttprint('reste:'+str(reste))
    for i:0..reste-1
        header+='*'
    end
    var finalsend=string.format("%5d\n",size(header)+6)
    mqttprint('ajout header:'+str(size(finalsend)))
    finalsend+=header
    mqttprint('taille finale:'+(size(finalsend)))
    file=open('stm32.cfg',"wt")
    file.write(finalsend)
    file.close()
   
    ser=serial(25,26,230400,serial.SERIAL_8N1)
    var mybytes=bytes().fromstring(finalsend)
    ser.flush()
    ser.write(mybytes)
    tasmota.resp_cmnd("config sent")
end

def readconfig(cmd, idx,payload, payload_json)
    var file
    var buffer
    var split
    import path
    if(!path.exists("stm32.cfg"))
      mqttprint("fichier config non existant")
    else
        file = open("stm32.cfg")
        buffer=file.read()
        file.close()
        split = string.split(buffer,'\n')
        mqttprint(str(size(split))+" lignes")
        for i:0..size(split)-1
            if split[i][0]=='d' && split[i][1]=='e'   # detect device section to stop
                break
            else
                mqttprint(split[i])
            end
        end
    end
    tasmota.resp_cmnd_done()
end

def dir(cmd, idx,payload, payload_json)
    import path
    var liste
    var file
    var taille
    var date
    var timestamp
    liste = path.listdir("/")
    mqttprint(str(liste.size())+" fichiers")
    for i:0..(liste.size()-1)
        file = open(liste[i],"r")
        taille = file.size()
        file.close()
        timestamp = path.last_modified(liste[i])
        mqttprint(liste[i]+' '+tasmota.time_str(timestamp)+' '+str(taille))
    end
    tasmota.resp_cmnd_done()
end

# def stop
#     tasmota.remove(snx_driver.be)
# end

# def stop
#     tasmota.remove(snx_driver.be)
# end


def launch_driver()
    mqttprint('mqtt connected -> launch driver')
    tasmota.load('snx_driver.be')
 end


#-------------------------------- BASH -----------------------------------------#
tasmota.cmd("seriallog 0")
mqttprint("serial log disabled")

mqttprint('AUTOEXEC: create commande Stm32Reset')
tasmota.add_cmd('Stm32reset',Stm32Reset)

mqttprint('AUTOEXEC: create commande getfile')
tasmota.add_cmd('getfile',getfile)

mqttprint('AUTOEXEC: create commande sendconfig')
tasmota.add_cmd('sendconfig',sendconfig)
tasmota.add_cmd('readconfig',readconfig)
tasmota.add_cmd('dir',dir)

tasmota.add_cmd('ville',ville)
tasmota.add_cmd('device',device)

init()

mqttprint('load snx_driver & loader')
mqttprint('wait for 5 seconds ....')
tasmota.set_timer(5000,launch_driver)

