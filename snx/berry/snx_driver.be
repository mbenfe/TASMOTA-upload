#---------------------------------#
# SNX_DRIVER.BE 1.0 SNX           #
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
        self.device=jsonmap["device"]
        print('device:',self.device)
    end

    def init()
        self.rst_in=19   
        self.bsl_in=21   
        self.rst_out=33   
        self.bsl_out=32   
        self.statistic=14
        self.ready=27
    
        self.mapID = {}
        self.mapFunc = {}

        self.loadconfig()

        print('DRIVER: serial init done')
        # lecture STM32 IN pour debug
         self.ser = serial(36,1,921600,serial.SERIAL_8N1)
        # pinout flasher
        # serial speed limite (choisy)
        #self.ser = serial(17,16,921600,serial.SERIAL_8N1)
    
        # setup boot pins for stm32: reset disable & boot normal

        gpio.pin_mode(self.rst_in,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_in,gpio.OUTPUT)
        gpio.pin_mode(self.rst_out,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_out,gpio.OUTPUT)
        gpio.pin_mode(self.statistic,gpio.OUTPUT)
#        gpio.pin_mode(self.ready,gpio.OUTPUT)
        gpio.digital_write(self.bsl_in, 0)
        gpio.digital_write(self.rst_in, 1)
        gpio.digital_write(self.bsl_out, 0)
        gpio.digital_write(self.rst_out, 1)
        gpio.digital_write(self.statistic, 0)
#        gpio.digital_write(self.ready,1)

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
#        gpio.digital_write(self.ready,0)
        if self.ser.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            gpio.digital_write(self.statistic,1)
            var buffer = self.ser.read()
            self.ser.flush()
            mqttprint("reception")
            if(buffer[0]==123)         # { -> json tele metry
                mystring = buffer.asstring()
                mylist = string.split(mystring,'\n')
                numitem = size(mylist)
                for i:0..numitem-2
                    myjson = json.load(mylist[i])
                    if myjson.contains('ID')
                        if myjson["ID"] == 0
                            topic=string.format("gw/%s/%s/%s/tele/DEBUG",self.client,self.ville,self.device)
                        else
                            topic=string.format("gw/%s/%s/%s/tele/DANFOSS",self.client,self.ville,self.device)
                        end
                        mqtt.publish(topic,mylist[i],true)
                    else
                        topic=string.format("gw/%s/%s/s_%s/tele/STATISTIC",self.client,self.ville,str(myjson["Name"]))
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
                    topic=string.format("gw/%s/%s/stat_%s/tele/STATISTIC",self.client,self.ville,str(myjson["ID"]))
                    mqtt.publish(topic,mylist[i],true)
                end
            end
            if (buffer[0] == 58)     # : -> debug text
                topic=string.format("gw/%s/%s/%s/tele/PRINT",self.client,self.ville,str(myjson["ID"]))
                mystring = buffer.asstring()
                mqtt.publish(topic,mystring,true)
            end
        end
        gpio.digital_write(self.statistic,0)
#        gpio.digital_write(self.ready,1)
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
