#---------------------------------#
# VERSION 1.0 WFX                 #
#---------------------------------#
import string
import global
import mqtt
import json
import gpio

var ser1                # serial object
var ser2                # serial object
var rx1=3    
var tx1=1    
var rx2=13    
var tx2=12    

var bsl_1=0   
var rst_1=22   
var bsl_2=2   
var rst_2=14   


def Init()
    # gpio.pin_mode(rx1,gpio.INPUT_PULLUP)
    # gpio.pin_mode(tx1,gpio.PULLUP)
    # gpio.pin_mode(rx2,gpio.INPUT_PULLUP)
    # gpio.pin_mode(tx2,gpio.PULLUP)
    ser1 = serial(rx1,tx1,115200,serial.SERIAL_8N1)
    ser2 = serial(rx2,tx2,115200,serial.SERIAL_8N1)
    print("serial initialised")
    tasmota.resp_cmnd_done()
end


#-------------------------------- COMMANDES -----------------------------------------#
def BlReset(cmd, idx, payload, payload_json)
    var ser
    var argument = string.split(string.toupper(payload)," ")
    if argument.size() < 2
        print("erreur d'arguments")
        return
    end
    if argument[0] == '1'
        ser = ser1
    else
        ser = ser2
    end
    ser.flush()
    ser.write(bytes().fromstring("SET RESET"))
    print("SET RESET")
    tasmota.resp_cmnd_done()
end

def BlMode(cmd, idx, payload, payload_json)
    var argument = string.split(string.toupper(payload)," ")
    if argument.size() < 2
        print("erreur d'arguments")
        return
    end
    if(argument[1]!="CAL" && argument[1] !="LOG" )
        print("erreur arguments")
        return
    end
    if argument[0] == '1'
       ser1.flush()
       if(argument[1]=="CAL")
          ser1.write(bytes().fromstring("SET MODE CAL"))
          print("SET MODE CAL device 1")
          print(ser1)
       else
          ser1.write(bytes().fromstring("SET MODE LOG"))
          print("SET MODE LOG device 1")
          print(ser1)
       end
    else
       ser2.flush()
       if(argument[1]=="CAL")
          ser2.write(bytes().fromstring("SET MODE CAL"))
          print("SET MODE CAL device 2")
          print(ser2)
       else
          ser2.write(bytes().fromstring("SET MODE LOG"))
          print("SET MODE LOG device 2")
          print(ser2)
       end
    end
    tasmota.resp_cmnd_done()
end

def Stm32Reset(cmd, idx, payload, payload_json)
    print('reset:',payload)

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
        print("erreur d'arguments")
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
    print(path)
    var file=string.split(path,'/').pop()
    print(file)
    var wc=webclient()
    wc.set_follow_redirects(true)
    wc.begin(path)
    var st=wc.GET()
    if st!=200 
        raise 'erreur','code: '+str(st) 
    end
    st='Fetched '+str(wc.write_file(file))
    print(path,st)
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
        print("erreur d'arguments")
        return
    end
    print("send:",argument[1])
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
        print("fichier non existant:",payload)
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
        print(total)
        tasmota.resp_cmnd("config sent")
    else
        print("device ",device," non touvé")
        tasmota.resp_cmnd("config not sent")
    end
end


 tasmota.cmd("seriallog 0")
 print("serial log disabled")
 tasmota.cmd("timezone 2")
 print("timezone set")
  
 tasmota.add_cmd("Init",Init)
 tasmota.add_cmd('Stm32reset',Stm32Reset)
tasmota.add_cmd("BlReset",BlReset)
tasmota.add_cmd("BlMode",BlMode)
tasmota.add_cmd("sendconfig",sendconfig)
tasmota.add_cmd('getfile',getfile)
tasmota.add_cmd('ville',ville)
tasmota.add_cmd('device',device)

tasmota.load("wfx_driver.be")
tasmota.cmd("Init")
tasmota.delay(500)
tasmota.cmd("Teleperiod 0")
