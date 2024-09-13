#---------------------------------#
# VERSION 1.1                     #
#---------------------------------#
import string
import global
import mqtt
import json
import gpio

var ser                # serial object
var debug                   # verbose logs?

# rev A pinout
# STM32    -> ESP32
# UART3_TX -> RX0 GPIO3
# UART3_RX -> TX0 GPIO1
# UART1_TX <- RX GPIO16
# UART1_RX <- TX GPIO17 
# BSL = ESP32 GPIO33
# RESET = ESP32 GPIO32 

# rev B,C,D pinout
# STM32    -> ESP32
# UART3_TX -> RX0 GPIO3
# UART3_RX -> TX0 GPIO1
# UART1_TX <- RX GPIO16
# UART1_RX <- TX GPIO17 
# BSL = ESP32 GPIO13
# RESET = ESP32 GPIO02 

var rx=16    # rx = GPI03
var tx=17    # tx = GPIO1
var rst=2   # rst = GPIO2
var bsl=13   # bsl = GPIO13

#-------------------------------- FUNCTIONS -----------------------------------------#
def recv_raw(timeout)
    var due = tasmota.millis() + timeout
    while !tasmota.time_reached(due)
      if ser.available()
        var b = ser.read()
        if debug print("b:",b) end
        while size(b) > 0 && b[0] == 0
          b = b[1..]
        end
        return b
      end
      tasmota.delay(5)        # check every 5ms
    end
    return 'serial timeout'
end

#-------------------------------- COMMANDES -----------------------------------------#
def Stm32Write(cmd, idx, payload, payload_json)
    var token = string.format('CMD READ CONFIG')

    # initialise UART Rx = GPI03 and TX=GPIO1
    # send data to serial
    ser = serial(rx,tx,115200,serial.SERIAL_8N1)
    ser.write(bytes().fromstring(payload))
    tasmota.resp_cmnd_done()
    print('WRITE:',payload)
end 

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
    ser.write(bytes().fromstring(token))
    tasmota.resp_cmnd_done()
    print('SENDTIME:',token)
end

# A -> nom phase A
# B -> nom phase B
# C -> nom phase C
# N -> nom neutral
# ROOT -> nom root device appliqué sur le total & les phases
# RATIO -> ration des current transformer (1000,2000,4000 etc ...)
# LOGTYPE -> type triphase (defaut) monophasé
# LOGFREQ -> frequence d'envoi en seconde (defaut = 5s)
def SerialSetup(cmd, idx, payload, payload_json)
    var argument = string.split(payload,' ')
    if(argument[0]!='A' && argument[0]!='B' && argument[0] !='C' && argument[0] != 'N' && argument[0] != 'ROOT' && argument[0] != 'RATIO' 
        && argument[0] != 'LOGTYPE' && argument[0] != 'LOGFREQN' || argument[1] == '')
        print('erreur arguments')
        return
    end
    var token
    if(argument[0]=='A' || argument[0]=='B' || argument[0] =='C' || argument[0] == 'N')
        if(argument[0]=='N')
            token = string.format('SET Neutral %s',argument[1])
        else
            token = string.format('SET Phase_%s %s',argument[0],argument[1])
        end
    else
        token = string.format('SET %s %s',argument[0],argument[1])
    end
    # initialise UART Rx = GPIO3 and TX=GPIO1
    # send data to serial
    gpio.pin_mode(rx,gpio.INPUT)
    gpio.pin_mode(tx,gpio.OUTPUT)
    ser = serial(rx,tx,115200,serial.SERIAL_8N1)
    ser.write(bytes().fromstring(token))
    tasmota.resp_cmnd_done()
    print('SET:',token)
end

def Flash(cmd, idx, payload, payload_json)
    var argument = string.split(payload,' ')
    if(argument[0] != 'FLASHERASE' && argument[0] != 'FLASHBACKUP' && argument[0] != 'FLASHRESTORE')
        print('erreur arguments')
        return
    end
    var token
    token = string.format('SET %s',argument[0])

    # initialise UART Rx = GPIO3 and TX=GPIO1
    # send data to serial
    gpio.pin_mode(rx,gpio.INPUT)
    gpio.pin_mode(tx,gpio.OUTPUT)
    ser = serial(rx,tx,115200,serial.SERIAL_8N1)
    ser.write(bytes().fromstring(token))
    tasmota.resp_cmnd_done()
    print('SET:',token)
end


def AdeReset(cmd, idx, payload, payload_json)
    gpio.pin_mode(rx,gpio.INPUT)
    gpio.pin_mode(tx,gpio.OUTPUT)
    ser = serial(rx,tx,115200,serial.SERIAL_8N1)
    ser.write(bytes().fromstring('SET RESET'))
    tasmota.delay(500)
    SerialSendTime()
    tasmota.resp_cmnd_done()
end

def AdeMode(cmd, idx, payload, payload_json)
    var argument = string.split(payload,' ')
    if(argument[0]!='MONO' && argument[0] !='TRI' )
        print('erreur arguments')
        return
    end
    gpio.pin_mode(rx,gpio.INPUT)
    gpio.pin_mode(tx,gpio.OUTPUT)
    ser = serial(rx,tx,115200,serial.SERIAL_8N1)
    if(argument[0]=='MONO')
        ser.write(bytes().fromstring('SET MODE MONO'))
    else
        ser.write(bytes().fromstring('SET MODE TRI'))
    end
    tasmota.delay(500)
    tasmota.resp_cmnd_done()
end

def Stm32Flash()
    print('FLASH:initialisation hardware')
    var ret
    ser = serial(rx,tx,115200,serial.SERIAL_8E1)
    ser.flush()
     # reset STM32
     gpio.pin_mode(rst,gpio.OUTPUT)
     gpio.pin_mode(bsl,gpio.OUTPUT)
    #------------- INTIALISE BOOT -------------------------#
    print('FLASH:initialise boot sequence')
    gpio.digital_write(rst, 0)    # trigger BSL
    tasmota.delay(10)               # wait 10ms
    gpio.digital_write(bsl, 1)    # trigger BSL
    tasmota.delay(10)               # wait 10ms
    gpio.digital_write(rst, 1)    # trigger BSL
    tasmota.delay(100)               # wait 10ms

    ser.write(0x7F)
    ret = recv_raw(50)
    
  #------------- GET INFO -------------------------#
     ser.write(bytes('00FF'))
     tasmota.delay(10)               # wait 10ms
     ret = recv_raw(50)
     print("FLASH:V & C=", ret)

     ser.write(bytes('01FE'))
     tasmota.delay(10)               # wait 10ms
     ret = recv_raw(50)
     print("FLASH:Protocol version=", ret)

     ser.write(bytes('02FD'))
     tasmota.delay(10)               # wait 10ms
     ret = recv_raw(50)
     print("FLASH:chip ID=", ret)
  

    gpio.digital_write(bsl, 0) 
    tasmota.delay(10)   # trigger BSL
    gpio.digital_write(rst, 0)    # trigger Reset
    tasmota.delay(10)
    gpio.digital_write(rst, 1)    # trigger Reset
    tasmota.delay(500)
    SerialSendTime()
    tasmota.resp_cmnd('STM32 test flash done')
end


def Stm32Reset()
    gpio.pin_mode(rst,gpio.OUTPUT)
    gpio.pin_mode(bsl,gpio.OUTPUT)
    gpio.digital_write(rst, 1)
    gpio.digital_write(bsl, 0)
  
    print('RESET:reset STM32')
    gpio.digital_write(rst, 0)
    tasmota.delay(100)               # wait 10ms
    gpio.digital_write(rst, 1)
    tasmota.delay(500)
    SerialSendTime()
    tasmota.resp_cmnd('STM32 reset')
  #      tasmota.load('stm32_driver.be')
    print('RESET:free heap:',tasmota.get_free_heap())
end

tasmota.cmd("seriallog 0")
print("serial log disabled")

print('AUTOEXEC: create commande SerialSendTime')
tasmota.add_cmd('SerialSendTime',SerialSendTime)

print('AUTOEXEC: create commande Stm32Write')
tasmota.add_cmd('Stm32Write',Stm32Write)

print('AUTOEXEC: create commande Stm32Flash')
tasmota.add_cmd('Stm32Flash',Stm32Flash)

print('AUTOEXEC: create commande Stm32Reset')
tasmota.add_cmd('Stm32reset',Stm32Reset)

print('AUTOEXEC: create commande SerialSetup')
tasmota.add_cmd('SerialSetup',SerialSetup)

print('AUTOEXEC: create commande AdeReset')
tasmota.add_cmd('AdeReset',AdeReset)

print('AUTOEXEC: create commande AdeMode')
tasmota.add_cmd('AdeMode',AdeMode)

print('AUTOEXEC: create commande Flash')
tasmota.add_cmd('Flash',Flash)

tasmota.load('stm32_driver.be')

############################################################
tasmota.cmd('serialsendtime')
tasmota.delay(1000)
tasmota.cmd('serialsetup ROOT fpos')
tasmota.delay(1000)
