#---------------------------------#
# VERSION PWX12                   #
#---------------------------------#

import mqtt
import string
import json

class PWX12
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

    var listLog

    var tick_midnight
    var tick_hour
    var tick_second

    var conso

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
        import conso
        self.conso = conso
        self.rx=3
        self.tx=1
        self.rst=2
        self.bsl=13

        self.tick_midnight=15
        self.tick_hour=33
        self.tick_second=32

        self.loadconfig()

        print('DRIVER: serial init done')
        print('heap:',tasmota.get_free_heap())
        self.ser = serial(self.rx,self.tx,115200,serial.SERIAL_8N1) 
    
        # setup boot pins for stm32: reset disable & boot normal
        gpio.pin_mode(self.rst,gpio.OUTPUT)
        gpio.pin_mode(self.bsl,gpio.OUTPUT)
        gpio.pin_mode(self.tick_midnight,gpio.OUTPUT)
        gpio.pin_mode(self.tick_hour,gpio.OUTPUT)
        gpio.pin_mode(self.tick_second,gpio.OUTPUT)
        gpio.digital_write(self.bsl, 0)
        gpio.digital_write(self.rst, 1)
        gpio.digital_write(self.tick_midnight, 0)
        gpio.digital_write(self.tick_hour, 0)
        gpio.digital_write(self.tick_second, 0)

        self.listLog = []

        for i:0..3600
            self.listLog.insert(i,0.0)
        end
        print('heap:',tasmota.get_free_heap())
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
                            self.topic = string.format("gw/%s/%s/%s/tele/%s",self.client,self.ville,self.device,myjson['TYPE'])
                        else
                            self.topic = string.format("gw/%s/%s/%s/tele/POWER",self.client,self.ville,self.device)
                        end
                        mqtt.publish(self.topic,mylist[i],true)
                    else
                        var token = string.format('PWX12-> %s',mylist[i])
                        print(token)
                    end
                end
            end
    
        end
    end

    def midnight()
         gpio.digital_write(self.tick_midnight, 1)
         tasmota.delay(1)
         print('midnight')
         gpio.digital_write(self.tick_midnight, 0)
    end

    def hour()
        gpio.digital_write(self.tick_hour, 1)
        tasmota.delay(1)
        print('hour')
        gpio.digital_write(self.tick_hour, 0)
    end

    def every_second()
        # gpio.digital_write(self.tick_midnight, 1)
        # gpio.digital_write(self.tick_hour, 1)
        gpio.digital_write(self.tick_second, 1)
        tasmota.delay(1)
        print('1s')
        # gpio.digital_write(self.tick_midnight, 0)
        # gpio.digital_write(self.tick_hour, 0)
        gpio.digital_write(self.tick_second, 0)
    end

end

pwx12 = PWX12()
tasmota.add_driver(pwx12)
tasmota.add_fast_loop(/-> pwx12.fast_loop())
tasmota.add_cron("59 59 23 * * *",  /-> pwx12.midnight(), "every_day")
tasmota.add_cron("59 59 * * * *",   /-> pwx12.hour(), "every_hour")
