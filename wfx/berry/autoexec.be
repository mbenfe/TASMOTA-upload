#---------------------------------#
# VERSION 1.0 WFX                 #
#---------------------------------#
import string
import global
import mqtt
import json
import gpio

# var ser                # serial object

# var rx=4    
# var tx=5    
# var rst_in=19   
# var bsl_in=21   
# var rst_out=33   
# var bsl_out=32   


#-------------------------------- COMMANDES -----------------------------------------#
# def Stm32Reset(cmd, idx, payload, payload_json)
#     if (payload=='1')
#         gpio.pin_mode(rst_in,gpio.OUTPUT)
#         gpio.pin_mode(bsl_in,gpio.OUTPUT)
#         gpio.digital_write(rst_in, 1)
#         gpio.digital_write(bsl_in, 0)
  
#         gpio.digital_write(rst_in, 0)
#         tasmota.delay(100)               # wait 10ms
#         gpio.digital_write(rst_in, 1)
#         tasmota.delay(100)               # wait 10ms
#         tasmota.resp_cmnd('STM32 IN reset')
#     end
#     if (payload=='2')
#         gpio.pin_mode(rst_out,gpio.OUTPUT)
#         gpio.pin_mode(bsl_out,gpio.OUTPUT)
#         gpio.digital_write(rst_out, 1)
#         gpio.digital_write(bsl_out, 0)
  
#         gpio.digital_write(rst_out, 0)
#         tasmota.delay(100)               # wait 10ms
#         gpio.digital_write(rst_out, 1)
#         tasmota.delay(100)               # wait 10ms
#         tasmota.resp_cmnd('STM32 OUT reset')
#     end
# end

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
