#---------------------------------#
# VERSION 1.0 WFX                 #
#---------------------------------#
import string
import global
import mqtt
import json
import gpio

var ser                # serial object

var rx1=3    
var tx1=1    
var rx1=13    
var tx1=12    

var rst_1=22   
var bsl_1=0   
var rst_2=2   
var bsl_2=14   


-------------------------------- COMMANDES -----------------------------------------#
def Stm32Reset(cmd, idx, payload, payload_json)
    var argument = string.split(payload,' ')
    if argument.size() < 2
        print("erreur d'arguments")
        return
    end
    if (argument[0]=='1')
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
    if (argument[0]=='2')
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
    if argument.size < 2
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

 tasmota.cmd("seriallog 0")
 print("serial log disabled")
 tasmota.cmd("timezone 2")
 print("timezone set")
  
# tasmota.add_cmd('Stm32reset',Stm32Reset)
tasmota.add_cmd('getfile',getfile)
tasmota.add_cmd('ville',ville)
tasmota.add_cmd('device',device)

tasmota.load("wfx_driver.be")
