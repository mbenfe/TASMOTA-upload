#---------------------------------#
# VERSION 1.0 SNX                 #
#---------------------------------#
import string
import global
import mqtt
import json
import gpio

var ser                # serial object
var debug                   # verbose logs?

var rx=4    
var tx=5    
var rst_in=21   
var bsl_in=19   
var rst_out=33   
var bsl_out=32   


#-------------------------------- COMMANDES -----------------------------------------#
def SerialSendTime()
    # put EPOC to string
    var now = tasmota.rtc()
    var time_raw = now['local']
    var token = string.format('CAL TIME EPOC:%d',time_raw)

    # initialise UART Rx = GPIO3 and TX=GPIO1
    # send data to serial
    gpio.pin_mode(rx,gpio.INPUT)
    gpio.pin_mode(tx,gpio.OUTPUT)
    ser = serial(rx,tx,115200,serial.SERIAL_8N1)
    ser.flush()
    ser.write(bytes().fromstring(token))
    tasmota.resp_cmnd_done()
    print('SENDTIME:',token)
end

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

tasmota.cmd("seriallog 0")
print("serial log disabled")

print('AUTOEXEC: create commande SerialSendTime')
tasmota.add_cmd('SerialSendTime',SerialSendTime)

print('AUTOEXEC: create commande Stm32Reset')
tasmota.add_cmd('Stm32reset',Stm32Reset)

print('load stm32_driver& loader')
tasmota.load('stm32_driver.be')
tasmota.load('loader.be')
