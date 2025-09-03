var version = "1.0.112024 ready to H7"

import mqtt
import string
import json


class STM32
    var errors
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

    def mqttprint(texte)
        import mqtt
        var topic = string.format("gw/inter/%s/%s/tele/DEBUG2", self.ville, self.device)
        mqtt.publish(topic, texte, true)
    end


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
        self.errors = {}

        self.loadconfig()

        print('DRIVER: serial init done')
        # lecture STM32 IN pour debug
        # self.ser = serial(36,1,921600,serial.SERIAL_8N1)
        # pinout flasher
        # serial speed limite (choisy)
        self.ser = serial(17,16,921600,serial.SERIAL_8N1)
    
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

    #    tasmota.add_fast_loop(/-> self.fast_loop())
    end

    def fast_loop()
        self.read_uart(2)
    end

    def map_error(json_string)
        var data = json.load(json_string)

        if data["ERREUR"] != "Type introuvable"
            return
        end

        var dev_type = data["type"]
        var reg = data["registre"]

        # TODO

        # if not self.errors.get(dev_type)
        #     self.errors[dev_type] = []
        # end

        # # Vérifier présence préalable
        # if self.errors[dev_type].find(reg) == nil
        #     self.errors[dev_type].push(reg)
        # end
    end


    def read_uart(timeout)
        var mystring
        var mylist
        var numitem
        var myjson
        var topic
        if self.ser.available()
            gpio.digital_write(self.ready,0)
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
                    if myjson != nil
                        if myjson.contains('ID')
                            if myjson["ID"] == 0 || myjson["ID"] == -1
                                topic=string.format("gw/%s/%s/%s/tele/DEBUG",self.client,self.ville,self.device)
                                if myjson.contains('ERREUR')
                                    self.mqttprint('error: ' + mylist[i])
                                    self.map_error(mylist[i])
                                end
#                                mqtt.publish(topic,mylist[i],true)
                            elif myjson["ID"] == -2
                                topic=string.format("gw/%s/%s/%s/tele/CONFIG",self.client,self.ville,self.device)
                                mqtt.publish(topic,mylist[i],true)
                            elif myjson["ID"] == -3
                                topic=string.format("gw/%s/%s/%s/tele/ON_CONSIGNE",self.client,self.ville,self.device)
                                mqtt.publish(topic,mylist[i],true)
                            elif myjson.contains('CtrlState') || myjson.contains('TherAir') || myjson.contains('CutinTemp') || myjson.contains('CutoutTemp') 
                                topic=string.format("gw/%s/%s/%s-%s/tele/DANFOSS",self.client,self.ville,self.device,str(int(myjson["ID"])))
                                mqtt.publish(topic,mylist[i],true)
                            else
                                topic=string.format("gw/%s/%s/%s-%s/tele/DANFOSSLOG",self.client,self.ville,self.device,str(int(myjson["ID"])))
                                mqtt.publish(topic,mylist[i],true)
                           end
                        else
                            topic=string.format("gw/%s/%s/s_%s/tele/STATISTIC",self.client,self.ville,str(myjson["Name"]))
                            mqtt.publish(topic,mylist[i],true)
                        end
                    else
                        print('json error:',mylist[i])
                        self.mqttprint('json error:' + mylist[i])
                    end
                end
            elif (buffer[0] == 42)     # * -> json statistic
                mystring = buffer[1..-1].asstring()
                mylist = string.split(mystring,'\n')
                numitem = size(mylist)
                for i:0..numitem-2
                    myjson = json.load(mylist[i])
                    topic=string.format("gw/%s/%s/stat_%s/tele/STATISTIC",self.client,self.ville,str(myjson["ID"]))
                    mqtt.publish(topic,mylist[i],true)
                end
            elif (buffer[0] == 58)     # : -> debug text
                self.mqttprint('debug: ' + buffer.asstring())
                mystring = buffer.asstring()
                myjson = json.load(mystring)
                topic=string.format("gw/%s/%s/%s/tele/PRINT",self.client,self.ville,str(myjson["ID"]))
                mqtt.publish(topic,mystring,true)
            else
                topic=string.format("gw/%s/%s/snx/tele/PRINT",self.client,self.ville)
                mystring = buffer.asstring()
                mqtt.publish(topic,mystring,true)
            end
        end
        gpio.digital_write(self.ready,1)
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
