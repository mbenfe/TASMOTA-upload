#---------------------------------#
# WFX_DRIVER.BE 1.0 WF            #
#---------------------------------#
import mqtt
import string
import json
import global


class WFX
    var mapID
    var mapFunc 
       
    var rst_1  
    var bsl_1  
    var rst_2  
    var bsl_2   
    var client 
    var ville
    var device1
    var device2
    var topic 

    var logger
    var conso

    def loadconfig()
        import json
        var jsonstring
        var file 
        file = open("esp32.cfg","rt")
        if file.size() == 0
            print('DRIVER:create esp32 config file')
            file = open("esp32.cfg","wt")
            jsonstring=string.format("{\"ville\":\"unknown\",\"client\":\"inter\",\"device\":\"unknown\"}")
            file.write(jsonstring)
            file.close()
            file=open("esp32.cfg","rt")
        end
        var buffer = file.read()
        var jsonmap = json.load(buffer)
        self.client=jsonmap["client"]
        print('DRIVER:client:',self.client)
        self.ville=jsonmap["ville"]
        print('DRIVER:ville:',self.ville)
        self.device1=jsonmap["device1"]
        print('DRIVER:device1:',self.device1)
        self.device2=jsonmap["device2"]
        print('DRIVER:device2:',self.device2)
    end

    def init()
        import conso
        self.conso = conso
        import logger
        self.logger = logger

        self.rst_1=22   
        self.bsl_1=0   
        self.rst_2=2   
        self.bsl_2=14   
    
        # setup boot pins for stm32: reset disable & boot normal

        gpio.pin_mode(self.rst_1,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_1,gpio.OUTPUT)
        gpio.pin_mode(self.rst_2,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_2,gpio.OUTPUT)
        gpio.digital_write(self.bsl_1, 0)
        gpio.digital_write(self.rst_1, 1)
        gpio.digital_write(self.bsl_2, 0)
        gpio.digital_write(self.rst_2, 1)

    end

    def fast_loop()
        self.read_uart(2)
    end

    def read_uart(timeout)
        var mystring
        var mylist
        var numitem
        var myjson
        var due
        var topic
        var buffer
        if global.serial1.available()
            due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            buffer = global.serial1.read()
            global.serial1.flush()
            mystring = buffer.asstring()
            mylist = string.split(mystring,'\n')
            numitem= size(mylist)
            for i: 0..numitem-2
                if mylist[i][0] == 'C'
                    self.conso.update(mylist[i],1)
                    print(mylist[i])
                elif mylist[i][0] == 'W'
                    self.logger.log_data(mylist[i])
                else
                    print('WFX 1 ->',mylist[i])
                end
            end
        end
        if global.serial2.available()
            due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            buffer = global.serial2.read()
            global.serial2.flush()
            mystring = buffer.asstring()
            mylist = string.split(mystring,'\n')
            numitem= size(mylist)
            for i: 0..numitem-2
                if mylist[i][0] == 'C'
                    self.conso.update(mylist[i],2)
                    print(mylist[i])
                elif mylist[i][0] == 'W'
                    self.logger.log_data(mylist[i])
                else
                    print('WFX 2 ->',mylist[i])
                end
            end
        end
    end

    def midnight()
        self.conso.mqtt_publish('all')
   end

   def hour()
       var now = tasmota.rtc()
       var rtc=tasmota.time_dump(now['local'])
       var hour = rtc['hour']
       # publish if not midnight
       if hour != 23
           self.conso.mqtt_publish('hours')
       end
   end


    def every_4hours()
        self.conso.sauvegarde()
    end

    def testlog()
        self.logger.store()
    end

end

wfx = WFX()
tasmota.add_driver(wfx)
tasmota.add_fast_loop(/-> wfx.fast_loop())
tasmota.add_cron("59 59 23 * * *",  /-> wfx.midnight(), "every_day")
tasmota.add_cron("59 59 * * * *",   /-> wfx.hour(), "every_hour")
tasmota.add_cron("01 01 */4 * * *",   /-> wfx.every_4hours(), "every_4_hours")
return wfx
