var version = "1.0.112024 ready to H7"

import mqtt
import string
import json
import global

def get_cron_second()
    var combined = string.format("%s|%s", global.ville, global.device)
    var sum = 0
    for i : 0 .. size(combined) - 1
        sum += string.byte(combined[i])
    end
    print("cron for " + combined + " is " + str(sum % 60))
    return sum % 60
end


class STM32
    var errors
    var mapID
    var mapFunc
    var ser
    var rst_in  
    var bsl_in  
    var rst_out  
    var bsl_out   
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
        gpio.digital_write(self.bsl_in, 0)
        gpio.digital_write(self.rst_in, 1)
        gpio.digital_write(self.bsl_out, 0)
        gpio.digital_write(self.rst_out, 1)

        gpio.pin_mode(global.statistic_pin,gpio.OUTPUT)
        gpio.pin_mode(global.ready_pin,gpio.OUTPUT)

        gpio.digital_write(global.statistic_pin, 0)
        gpio.digital_write(global.ready_pin,1)

        tasmota.add_fast_loop(/-> self.fast_loop())
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
        if dev_type ==""
           return
        end

        var reg = data["registre"]

        if reg != ""
           if !self.errors.contains(reg)
              self.errors.insert(reg,{"name":"tbd","ratio":1,"liste":[]})
           end
           if self.errors[reg]["liste"] == nil
              self.erros[reg]["liste"].push(dev_type)
           end
        end

        # if not self.errors.get(dev_type)
        #     self.errors[dev_type] = []
        # end

        # # Vérifier présence préalable
        # if self.errors[dev_type].find(reg) == nil
        #     self.errors[dev_type].push(reg)
        # end
    end

    def save()
        var file = open("error.json","wt")
        if file == nil
           return
        end
        var buffer = json.dump(self.errors)
        file.write(buffer)
        print("sauvegarde error : ",str(size(buffer))) 
        file.close()
    end


    def read_uart(timeout)
        var mystring
        var mylist
        var numitem
        var myjson
        var topic
        if self.ser.available()
            gpio.digital_write(global.ready_pin,0)
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
                     #           mqtt.publish(topic,mylist[i],true)
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
                        end
                    else
                        print('json error:',mylist[i])
                        self.mqttprint('json error:' + mylist[i])
                    end
                end
            elif (buffer[0] == 42)     # * -> json statistic
                mystring = buffer.asstring()
                mylist = string.split(mystring,'\n')
                numitem = size(mylist)
                for i:0..numitem-2
                    var line = mylist[i]
                    if size(line) > 0
                        if line[0] == '\r'
                            line = line[1..-1]
                        end
                        if line[0] == '*'
                            line = line[1..-1]
                        end
                        myjson = json.load(line)
                        if myjson != nil && myjson.contains("ID")
                            topic=string.format("gw/%s/%s/stat_%s/tele/STATISTIC",self.client,self.ville,str(myjson["Name"]))
                            mqtt.publish(topic,line,true)
                        else
                            self.mqttprint('json statistic error:' + line)
                        end
                    end
                end
            else
                topic=string.format("gw/%s/%s/snx/tele/PRINT",self.client,self.ville)
                mystring = buffer.asstring()
                mqtt.publish(topic,mystring,true)
            end
        end
        gpio.digital_write(global.ready_pin,1)
    end

    def get_statistic()
         gpio.digital_write(global.statistic_pin, 1)
         tasmota.delay(1)
         gpio.digital_write(global.statistic_pin, 0)
    end

    def heartbeat()
        var now = tasmota.rtc()
        var timestamp = tasmota.time_str(now["local"])
        var topic = string.format("gw/%s/%s/%s/tele/HEARTBEAT", self.client, self.ville, self.device)
        var payload = string.format('{"Device":"%s","Name":"%s","Time":"%s"}', self.device, self.device, timestamp)
        mqtt.publish(topic, payload, true)
    end
end

stm32 = STM32()
tasmota.add_driver(stm32)
tasmota.add_fast_loop(/-> stm32.fast_loop())
var cron_second = get_cron_second()
var cron_pattern = string.format("%d 59 23 * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> stm32.get_statistic(), "every_day")
print("cron statistic:" + cron_pattern)
cron_pattern = string.format("%d %d * * * *", cron_second, cron_second)
tasmota.add_cron(cron_pattern, /-> stm32.heartbeat(), "every_hour")
print("cron heartbeat:" + cron_pattern)
