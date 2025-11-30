#---------------------------------#
# VERSION 1.2                     #
#---------------------------------#

import mqtt
import json

class STM32
    var ser
    var rx
    var tx
    var bsl
    var rst
    var log
    var client 
    var ville
    var device
    var topic 

    def init()
        self.rx=3
        self.tx=1
        self.rst=2
        self.bsl=13
        self.log = 15

        self.client = 'inter'
        self.ville  = 'aulnay'
        self.device = 'dl-main'

        self.ser = serial(self.rx,self.tx,460800,serial.SERIAL_8N1)
        print('DRIVER: serial init done')

        # setup boot pins for stm32: reset disable & boot normal
        gpio.pin_mode(self.rst,gpio.OUTPUT)
        gpio.pin_mode(self.bsl,gpio.OUTPUT)
        gpio.pin_mode(self.log,gpio.OUTPUT)
        gpio.digital_write(self.log, 1)
        gpio.digital_write(self.bsl, 0)
        gpio.digital_write(self.rst, 1)
        # reset STM32
#        tasmota.delay(10)
#        gpio.digital_write(self.rst, 0)
#        tasmota.delay(10)
#        gpio.digital_write(self.rst, 1)
#        tasmota.delay(10)
#       print('DRIVER: reset stm32 done')
    end

    def read_uart(timeout)
        if self.ser.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = self.ser.read()
            self.ser.flush()
            var mystring = buffer.asstring()
            var mylist = string.split(mystring,'\n')
            var numitem= size(mylist)
            for i: 0..numitem-2
                if (mylist[i][0] == '{' )   # json received
                    var myjson=json.load(mylist[i])
                    if(myjson.contains('TYPE'))
                        self.topic = string.format("gw/%s/%s/%s/tele/%s",self.client,self.ville,myjson['Name'],myjson['TYPE'])
                    else
                        self.topic = string.format("gw/%s/%s/%s/tele/LOG",self.client,self.ville,myjson['Name'])
                    end
                    mqtt.publish(self.topic,mylist[i],true)
                else
                    var token = string.format('STM32-> %s',mylist[i])
                    print(token)
                end
            end
        end
    end

    def fast_loop()
        self.read_uart(10)
    end
    
    def every_15_minutes()
        tasmota.cmd('SERIALSENDTIME')
    end
end

stm32 = STM32()
tasmota.add_driver(stm32)
tasmota.add_fast_loop(/-> stm32.fast_loop())
tasmota.add_cron("0 */15 * * * *", /-> stm32.every_15_minutes(), "every_15_minutes")

