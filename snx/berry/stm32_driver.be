#---------------------------------#
# VERSION SNX                     #
#---------------------------------#

import mqtt
import string
import json

class STM32
    var mapID
    var mapFunc
    var ser
    var rst_in  
    var bsl_in  
    var rst_out  
    var bsl_out   
    var ready
    var statistic
    var client 
    var ville
    var device
    var topic 

    def init()
        self.client = 'inter'
        self.ville  = 'spare'
        self.device = 'snx'

        self.rst_in=19   
        self.bsl_in=21   
        self.rst_out=33   
        self.bsl_out=32   
        self.statistic=14
        seld.ready=27
    
        self.mapID = {}
        self.mapFunc = {}

        print('DRIVER: serial init done')
        self.ser = serial(34,5,921600,serial.SERIAL_8N1)   # 5 = fake
    
        # setup boot pins for stm32: reset disable & boot normal

        gpio.pin_mode(self.rst_in,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_in,gpio.OUTPUT)
        gpio.pin_mode(self.rst_out,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_out,gpio.OUTPUT)
        gpio.pin_mode(self.statistic,gpio.OUTPUT)
        gpio.pin_mode(self.ready,gpio.OUTPUT)
        gpio.digital_write(self.bsl_in, 0)
        gpio.digital_write(self.rst_in, 1)
        gpio.digital_write(self.bsl_out, 0)
        gpio.digital_write(self.rst_out, 1)
        gpio.digital_write(self.statistic, 0)
        gpio.digital_write(self.ready,1)

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
        digital_write(self.ready,0)
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
                    else
                        topic=string.format("gw/%s/%s/s_%s/tele/STATISTIC",self.client,self.ville,str(myjson['Name']))
                        mqtt.publish(topic,mylist[i],true)
                    end
                end
            end
            if (buffer[0] == 42)     # * -> json statistic
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
             end
        end
        digital_write(self.ready,0)
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
