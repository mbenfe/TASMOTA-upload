#---------------------------------#
# AUTOXEC.BE 1.0 WFX              #
#---------------------------------#
import string
import global
import mqtt
import json
import gpio

  

var bsl_1=0   
var rst_1=22   
var bsl_2=2   
var rst_2=14   

#-------------------------------- COMMANDES -----------------------------------------#
def Calibration(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload)," ")
    if(argument[0]!="VA" && argument[0]!="VB" && argument[0] !="VC" && argument[0] != "IA" && argument[0] != "IB" && argument[0] != "IC" && argument[0] != "IN" 
        || argument[1] == "")
        print("AUTOEXEC:erreur arguments")
        return
    end
    var token
    if(argument[0] =="VA" || argument[0] =="VB" || argument[0] =="VC")
        token = string.format("CAL %s %s",argument[0],argument[1])
    else
        token = string.format("CAL %s %s %s",argument[0],argument[1],argument[2])
    end
    global.serialSend.flush()
    global.serialSend.write(bytes().fromstring(token))
    print('AUTOEXEC:',token)
    tasmota.resp_cmnd_done()
end

def readcal()
    global.serialSend.flush()
    global.serialSend.write(bytes().fromstring("CAL READ"))
    print('CAL READ')
    tasmota.resp_cmnd_done()
end

def storecal()
    global.serialSend.flush()
    global.serialSend.write(bytes().fromstring("CAL STORE"))
    print('AUTOEXEC:CAL STORE')
    tasmota.resp_cmnd_done()
end

def Init()
    var rx1=3    
    var tx1=1    
    var rx2=13    
    var tx2=12    

    gpio.pin_mode(rx1,gpio.INPUT_PULLUP)
    gpio.pin_mode(tx1,gpio.PULLUP)
    gpio.pin_mode(rx2,gpio.INPUT_PULLUP)
    gpio.pin_mode(tx2,gpio.PULLUP)

    global.serial1 = serial(rx1,tx1,115200,serial.SERIAL_8N1)
    global.serial2 = serial(rx2,tx2,115200,serial.SERIAL_8N1)
    print("AUTOEXEC:serial initialised")
    tasmota.resp_cmnd_done()
end


def BlReset(cmd, idx, payload, payload_json)
    var ser
    var argument = string.split(string.toupper(payload)," ")
    if argument.size() < 2
        print("AUTOEXEC:erreur d'arguments")
        return
    end
    if argument[0] == '1'
        ser = global.serial1
    else
        ser = global.serial2
    end
    ser.flush()
    ser.write(bytes().fromstring("SET RESET"))
    print("AUTOEXEC:SET RESET")
    tasmota.resp_cmnd_done()
end

def BlMode(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload)," ")
    if argument.size() < 2
        print("AUTOEXEC:erreur d'arguments")
        return
    end
    if(argument[1]!="CAL" && argument[1] !="LOG" )
        print("AUTOEXEC:erreur arguments")
        return
    end
    if argument[0] == '1'
        global.serial1.flush()
       if(argument[1]=="CAL")
          global.serial1.write(bytes().fromstring("SET MODE CAL"))
          print("AUTOEXEC:SET MODE CAL device 1")
       else
          global.serial1.write(bytes().fromstring("SET MODE LOG"))
          print("AUTOEXEC:SET MODE LOG device 1")
       end
    else
        global.serial2.flush()
       if(argument[1]=="CAL")
          global.serial2.write(bytes().fromstring("SET MODE CAL"))
          print("AUTOEXEC:SET MODE CAL device 2")
       else
          global.serial2.write(bytes().fromstring("SET MODE LOG"))
          print("AUTOEXEC:SET MODE LOG device 2")
       end
    end
    tasmota.resp_cmnd_done()
end

def BlType(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload),' ')
    if(argument[0]!='MONO' && argument[0] !='TRI' )
        print('AUTOEXEC:erreur arguments')
        return
    end
    if(argument[0]=='MONO')					 
        global.serialSend.write(bytes().fromstring('SET TYPE MONO'))
    else		 
        global.serialSend.write(bytes().fromstring('SET TYPE TRI'))
    end
    tasmota.delay(500)
    tasmota.resp_cmnd_done()
end


def Stm32Reset(cmd, idx, payload, payload_json)
    print('AUTOEXEC:reset:',payload)

    if (payload=='1')
        gpio.pin_mode(rst_1,gpio.OUTPUT)
        gpio.pin_mode(bsl_1,gpio.OUTPUT)
        gpio.digital_write(rst_1, 1)
        gpio.digital_write(bsl_1, 0)
  
        gpio.digital_write(rst_1, 0)
        tasmota.delay(100)               # wait 10ms
        gpio.digital_write(rst_1, 1)
        tasmota.delay(100)               # wait 10ms
        tasmota.resp_cmnd('STM32 1 reset')
    end
    if (payload=='2')
        gpio.pin_mode(rst_2,gpio.OUTPUT)
        gpio.pin_mode(bsl_2,gpio.OUTPUT)
        gpio.digital_write(rst_2, 1)
        gpio.digital_write(bsl_2, 0)
  
        gpio.digital_write(rst_2, 0)
        tasmota.delay(100)               # wait 10ms
        gpio.digital_write(rst_2, 1)
        tasmota.delay(100)               # wait 10ms
        tasmota.resp_cmnd('STM32 2 reset')
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
    var argument = string.split(payload,' ')
    var file = open("esp32.cfg","rt")
    var buffer = file.read()
    var myjson=json.load(buffer)
    if argument.size() < 2
        print("AUTOEXEC:erreur d'arguments")
        return
    end
    if argument[0] == "1"
        myjson["device1"]=argument[1]
    else
        myjson["device2"]=argument[1]
    end
    buffer = json.dump(myjson)
    file.close()
    file = open("esp32.cfg","wt")
    file.write(buffer)
    file.close()
    tasmota.resp_cmnd('done')
end


def getfile(cmd, idx,payload, payload_json)
    import string
    var path = 'https://raw.githubusercontent.com//mbenfe/upload/main/'
    path+=payload
    print('AUTOEXEC:',path)
    var file=string.split(path,'/').pop()
    print('AUTOEXEC:',file)
    var wc=webclient()
    wc.set_follow_redirects(true)
    wc.begin(path)
    var st=wc.GET()
    if st!=200 
        raise 'erreur','code: '+str(st) 
    end
    st='Fetched '+str(wc.write_file(file))
    print('AUTOEXEC:',path,st)
    wc.close()
    var message = 'uploaded:'+file
    tasmota.resp_cmnd(message)
    return st
end

def sendconfig(cmd, idx,payload, payload_json)
    import string
    import json
    var file
    var buffer
    var myjson
    var device
    var total = "";
    var ser
    var header
    var trouve = false
    var argument = string.split(payload,' ')
    if argument.size() < 2
        print("AUTOEXEC:erreur d'arguments")
        return
    end
    print("AUTOEXEC:send:",argument[1])
    ############################ fichier config ###################
    file = open("esp32.cfg","rt")
    buffer = file.read()
    myjson=json.load(buffer)
    if argument[0]=='1'
        device = myjson["device1"]
    else
        device = myjson["device2"]
    end
    file.close()

    file = open(payload,"rt")
    if file == nil
        print("AUTOEXEC:fichier non existant:",payload)
        return
    end
    buffer = file.read()
    file.close()
    myjson = json.load(buffer)
    for key:myjson.keys()
        if key == device
            trouve = true
          total+="CONFIG"+" "+key+"_"
                    +myjson[key]["root"][0]+"_"+myjson[key]["root"][1]+"_"+myjson[key]["root"][2]+"_"+myjson[key]["root"][3]+"_"
                    +myjson[key]["produit"]+"_"
                    +myjson[key]["techno"][0]+"_"+myjson[key]["techno"][1]+"_"+myjson[key]["techno"][2]+"_"+myjson[key]["techno"][3]+"_"
                    +myjson[key]["ratio"][0]+"_"+myjson[key]["ratio"][1]+"_"+myjson[key]["ratio"][2]+"_"+myjson[key]["ratio"][3]
        end
    end
    if trouve == true
        # ser = serial(rx,tx,115200,serial.SERIAL_8N1)
        ser.flush()
        var mybytes=bytes().fromstring(total)
        ser.write(mybytes)
        print('AUTOEXEC:',total)
        tasmota.resp_cmnd("config sent")
    else
        print("AUTOEXEC:device ",device," non touvé")
        tasmota.resp_cmnd("config not sent")
    end
end


 tasmota.cmd("seriallog 0")
 print("AUTOEXEC:serial log disabled")

tasmota.add_cmd("cal",Calibration)
tasmota.add_cmd("readcal",readcal)
tasmota.add_cmd("storecal",storecal)
tasmota.add_cmd("Init",Init)
tasmota.add_cmd('Stm32reset',Stm32Reset)
tasmota.add_cmd("BlReset",BlReset)
tasmota.add_cmd("BlMode",BlMode)
tasmota.add_cmd("BlType",BlType)
tasmota.add_cmd('ville',ville)
tasmota.add_cmd('device',device)
tasmota.add_cmd('getfile',getfile)
tasmota.add_cmd("sendconfig",sendconfig)

tasmota.cmd("Init")
tasmota.load("wfx_driver.be")
tasmota.delay(500)
tasmota.cmd("Teleperiod 0")
