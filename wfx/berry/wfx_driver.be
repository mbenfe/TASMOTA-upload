#---------------------------------#
# VERSION SNX                     #
#---------------------------------#

import mqtt
import string
import json

class WFX
    var mapID
    var mapFunc
    var ser
    var rst_1  
    var bsl_1  
    var rst_2  
    var bsl_2   
    var client 
    var ville
    var device1
    var device2
    var topic 

    def loadconfig()
        import json
        var jsonstring
        var file 
        file = open("esp32.cfg","rt")
        if file.size() == 0
            print('creat esp32 config file')
            file = open("esp32.cfg","wt")
            jsonstring=string.format("{\"ville\":\"unknown\",\"client\":\"inter\",\"device\":\"unknown\"}")
            file.write(jsonstring)
            file.close()
            file=open("esp32.cfg","rt")
        end
        var buffer = file.read()
        var jsonmap = json.load(buffer)
        self.client=jsonmap["client"]
        print('client:',self.client)
        self.ville=jsonmap["ville"]
        print('ville:',self.ville)
        self.device1=jsonmap["device1"]
        print('device1:',self.device1)
        self.device2=jsonmap["device2"]
        print('device2:',self.device2)
    end

    def init()
        self.rst_1=19   
        self.bsl_1=21   
        self.rst_2=33   
        self.bsl_2=32   
    

        print('DRIVER: serial init done')
        self.ser = serial(36,1,115200,serial.SERIAL_8N1)
    
        # setup boot pins for stm32: reset disable & boot normal

        gpio.pin_mode(self.rst_1,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_1,gpio.OUTPUT)
        gpio.pin_mode(self.rst_2,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_2,gpio.OUTPUT)
        gpio.digital_write(self.bsl_1, 0)
        gpio.digital_write(self.rst_1, 1)
        gpio.digital_write(self.bsl_2, 0)
        gpio.digital_write(self.rst_2, 1)
        gpio.digital_write(self.ready,1)

    #    tasmota.add_fast_loop(/-> self.fast_loop())
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
        gpio.digital_write(self.ready,0)
        if self.ser.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = self.ser.read()
            self.ser.flush()
        end
    end

end

wfx = WFX()
tasmota.add_driver(wfx)
tasmota.add_fast_loop(/-> wfx.fast_loop())
