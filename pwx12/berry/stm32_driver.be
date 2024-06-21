#---------------------------------#
# VERSION SNX                     #
#---------------------------------#

import mqtt
import string
import json

class STM32
    var ser
    var rx
    var tx
    var bsl
    var rst

    var client 
    var log
    var ville
    var device
    var root
    var topic 

    def loadconfig()
        import json
        var jsonstring
        var file 
        file = open("esp32.cfg","rt")
        if file.size() == 0
            print('creat esp32 config file')
            file = open("esp32.cfg","wt")
            jsonstring=string.format("{\"ville\":\"unknown\",\"client\":\"inter\",\"device\":\"unknown\",\"root\":\"unknown\"}")
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
        self.root=jsonmap["root"]
        print('root:',self.root)
    end

    def init()
        self.rx=3
        self.tx=1
        self.rst=2
        self.bsl=13
        self.log=15

        self.loadconfig()

        print('DRIVER: serial init done')
        self.ser = serial(self.rx,self.tx,921600,serial.SERIAL_8N1) 
    
        # setup boot pins for stm32: reset disable & boot normal
        gpio.pin_mode(self.rst,gpio.OUTPUT)
        gpio.pin_mode(self.bsl,gpio.OUTPUT)
        gpio.pin_mode(self.log,gpio.OUTPUT)
        gpio.digital_write(self.bsl, 0)
        gpio.digital_write(self.rst, 1)
        gpio.digital_write(self.log, 1)
    end

    def fast_loop()
        self.read_uart(2)
    end

    def read_uart(timeout)
        if self.ser.available()
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
                            self.topic = string.format("gw/%s/%s/%s/tele/POWER",self.client,self.ville,myjson['Name'])
                        end
                        mqtt.publish(self.topic,mylist[i],true)
                    else
                        var token = string.format('STM32-> %s',mylist[i])
                        print(token)
                    end
                end
            end
    
        end
    end

    def get_24hlog()
         gpio.digital_write(self.statistic, 1)
         tasmota.delay(1)
         gpio.digital_write(self.statistic, 0)
    end
end

stm32 = STM32()
tasmota.add_driver(stm32)
tasmota.add_fast_loop(/-> stm32.fast_loop())
# tasmota.add_cron("59 59 23 * * *",  /-> stm32.get_statistic(), "every_day")
