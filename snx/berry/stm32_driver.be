#---------------------------------#
# VERSION MODBUS/LONWORKS         #
#---------------------------------#

import mqtt
import string
import json

class STM32
    var mapID
    var mapFunc
    var ser
    var rx
    var tx
    var bsl
    var rst
    var statistic
    var client 
    var ville
    var device
    var topic 

    def init()
        self.rx=3
        self.tx=1
        self.rst=2
        self.bsl=13
        self.statistic = 15

        self.client = 'inter'
        self.ville  = 'test'
        self.device = 'modbus2'

        self.mapID = {}
        self.mapFunc = {}

        self.ser = serial(self.rx,self.tx,921600,serial.SERIAL_8N1)
        print('DRIVER: serial init done')

        # setup boot pins for stm32: reset disable & boot normal
        gpio.pin_mode(self.rst,gpio.OUTPUT)
        gpio.pin_mode(self.bsl,gpio.OUTPUT)
        gpio.pin_mode(self.statistic,gpio.OUTPUT)
        gpio.digital_write(self.bsl, 0)
        gpio.digital_write(self.rst, 1)
        gpio.digital_write(self.statistic, 0)
        # reset STM32
        tasmota.delay(10)
        gpio.digital_write(self.rst, 0)
        tasmota.delay(10)
        gpio.digital_write(self.rst, 1)
        tasmota.delay(10)
        print('DRIVER: reset stm32 done')
        tasmota.add_fast_loop(/-> self.fast_loop())
    end

    def fast_loop()
        self.read_uart(2)
    end

    def read_uart(timeout)
        var mystring
        var mylist
        var numitem
        var myjson
        var topic
        if self.ser.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = self.ser.read()
            self.ser.flush()
            if(buffer[0]==123)         # { -> json tele metry
                mystring = buffer.asstring()
                mylist = string.split(mystring,'\n')
                numitem = size(mylist)
                for i:0..numitem-2
                    myjson = json.load(mylist[i])
                    if myjson.contains('ID')
                        if myjson['ID'] == 0
                            topic=string.format("monitor/%s/%s/%s",self.client,self.ville,self.device)
                        else
                            topic=string.format("gw/%s/%s/%s/tele/DANFOSS",self.client,self.ville,str(myjson['ID']))
                        end
                        mqtt.publish(topic,mylist[i],true)
                    end
                end
            end
            if (buffer[0] == 42)     # * -> json satistic
                mystring = buffer[1..-1].asstring()
                mylist = string.split(mystring,'\n')
                numitem = size(mylist)
                for i:0..numitem-2
                    myjson = json.load(mylist[i])
                    topic=string.format("gw/%s/%s/stat_%s/tele/STATISTIC",self.client,self.ville,str(myjson['ID']))
                    mqtt.publish(topic,mylist[i],true)
                end
            end
            if (buffer[0] == 58)     # : -> debug text
                mystring = buffer.asstring()
                print(mystring)        
            end
        end
    end

    def get_statistic()
         gpio.digital_write(self.statistic, 1)
         tasmota.delay(1)
         gpio.digital_write(self.statistic, 0)
    end
end

stm32 = STM32()
tasmota.add_driver(stm32)
tasmota.add_fast_loop(/-> stm32.fast_loop())
tasmota.add_cron("59 59 23 * * *",  /-> stm32.get_statistic(), "every_day")

