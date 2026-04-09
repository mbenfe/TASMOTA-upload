var version = "1.0.042026 debug reorganized"

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
    var rst_out  
    var bsl_out   
     var client 
    var ville
    var device
    var topic 
    var publish_mode

    def mqttprint(texte)
        import mqtt
        var topic = string.format("gw/%s/%s/%s/tele/DEBUG2", self.client, self.ville, self.device)
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
        self.rst_out=33   
        self.bsl_out=32   
        
        self.mapID = {}
        self.mapFunc = {}
        self.errors = {}
        self.publish_mode = "standard"

        self.loadconfig()

        print('DRIVER: serial init done')
    
        # setup boot pins for stm32: reset disable & boot normal

        gpio.pin_mode(self.rst_out,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_out,gpio.OUTPUT)
        gpio.digital_write(self.bsl_out, 0)

        gpio.pin_mode(global.statistic_pin,gpio.OUTPUT)
        gpio.pin_mode(global.ready_pin,gpio.OUTPUT)

        gpio.digital_write(global.statistic_pin, 0)
        gpio.digital_write(global.ready_pin,1)
    end

    def set_publish_mode(mode)
        if mode == nil
            return self.publish_mode
        end

        var m = string.tolower(str(mode))
        if m == "standard" || m == "debug" || m == "error" || m == "log" || m == "danfosslog" || m == "danfoss" || m == "consign"
            self.publish_mode = m
            return self.publish_mode
        end
        return nil
    end

    def get_publish_mode()
        return self.publish_mode
    end

    def _allow_publish(kind)
        var mode = self.publish_mode
        if mode == nil || mode == "standard"
            return true
        end

        if mode == "debug" || mode == "error"
            return kind == "debug" || kind == "print"
        end

        if mode == "log"
            return kind == "danfosslog"
        end

        if mode == "danfosslog"
            return kind == "danfosslog"
        end

        if mode == "danfoss"
            return kind == "danfoss"
        end

        if mode == "consign"
            return kind == "consign"
        end

        return true
    end

    def _publish_if_allowed(kind, topic, payload)
        if self._allow_publish(kind)
            mqtt.publish(topic, payload, true)
        end
    end

    def fast_loop()
        self.read_uart(2)
    end

    def save()
        var file = open("error.json","wt")
        if file == nil
           return
        end
        var buffer = json.dump(self.errors)
        file.write(buffer)
        file.close()
    end

    def read_uart(timeout)
        var mystring
        var mylist
        var numitem
        var myjson
        var topic
        if global.ser.available()
            gpio.digital_write(global.ready_pin,0)
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = global.ser.read()
            global.ser.flush()
            if buffer == nil || size(buffer) == 0
                print("ESP32: empty uart buffer")
            elif(buffer[0]==123)         # { -> json tele metry
                mystring = buffer.asstring()
                mylist = string.split(mystring,'\n')
                numitem = size(mylist)
                for i:0..numitem-2
                    myjson = json.load(mylist[i])
                    if myjson != nil
                        if myjson.contains('ID')
                            var msg_id = int(myjson["ID"])
                            if msg_id < 0
                                var kind = "debug"
                                if msg_id == -1
                                    topic=string.format("gw/%s/%s/%s/tele/DEBUG1",self.client,self.ville,self.device)
                                elif msg_id == -2
                                    topic=string.format("gw/%s/%s/%s/tele/DEBUG2",self.client,self.ville,self.device)
                                elif msg_id == -25
                                    kind = "config"
                                    topic=string.format("gw/%s/%s/%s/tele/CONFIG",self.client,self.ville,self.device)
                                elif msg_id == -20
                                    kind = "consign"
                                    topic=string.format("gw/%s/%s/%s/tele/ON_CONSIGNE",self.client,self.ville,self.device)
                                else
                                    topic=string.format("gw/%s/%s/%s/tele/DEBUG2",self.client,self.ville,self.device)
                                end
                                self._publish_if_allowed(kind, topic, mylist[i])
                            elif myjson.contains('CtrlState') || myjson.contains('TherAir') || myjson.contains('CutinTemp') || myjson.contains('CutoutTemp') 
                                topic=string.format("gw/%s/%s/%s-%s/tele/DANFOSS",self.client,self.ville,self.device,str(msg_id))
                                self._publish_if_allowed("danfoss", topic, mylist[i])
                            else
                                topic=string.format("gw/%s/%s/%s-%s/tele/DANFOSSLOG",self.client,self.ville,self.device,str(msg_id))
                                var log_allowed = true
                                if msg_id >= 10 && msg_id <= 20
                                    log_allowed = false
                                end
                                if self.publish_mode == "log" || self.publish_mode == "danfosslog"
                                    if msg_id < 10 || msg_id > 20
                                        log_allowed = false
                                    end
                                end
                                if log_allowed
                                    self._publish_if_allowed("danfosslog", topic, mylist[i])
                                end
                           end
                        end
                    else
                        topic=string.format("gw/%s/%s/%s/tele/DEBUG3",self.client,self.ville,self.device)
                        var payload = json.dump({"Error":"json_error","Raw":mylist[i]})
                        mqtt.publish(topic, payload, true)
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
                        if size(line) > 0 && line[0] == '*'
                            line = line[1..-1]
                        end
                        if size(line) > 0
                            myjson = json.load(line)
                            if myjson != nil && myjson.contains("ID")
                                topic=string.format("gw/%s/%s/%s-%s/tele/STATISTIC",self.client,self.ville,self.device,str(int(myjson["ID"])))
                                self._publish_if_allowed("statistic", topic, line)
                            else
                                print("ESP32: json statistic error:", line)
                            end
                        else
                            print("ESP32: empty statistic line")
                        end
                    end
                end
            else
                topic=string.format("gw/%s/%s/snx/tele/PRINT",self.client,self.ville)
                mystring = buffer.asstring()
                self._publish_if_allowed("print", topic, mystring)
            end
        end
        gpio.digital_write(global.ready_pin,1)
    end

    def get_statistic()
         gpio.digital_write(global.statistic_pin, 1)
         tasmota.delay(1)
         gpio.digital_write(global.statistic_pin, 0)
    end

    def stm32reset()
        # Reset only STM32 OUT line.
        gpio.digital_write(self.rst_out, 0)
        tasmota.delay(100)
        gpio.digital_write(self.rst_out, 1)
        tasmota.delay(100)
    end

    def heartbeat()
        var now = tasmota.rtc()
        var timestamp = tasmota.time_str(now["local"])
        var wifi = tasmota.wifi()
        var ap = "unknown"
        var ip = "unknown"
        if wifi != nil
            if wifi.contains("ssid") && wifi["ssid"] != nil
                ap = str(wifi["ssid"])
            end
            if wifi.contains("ip") && wifi["ip"] != nil
                ip = str(wifi["ip"])
            end
        end
        var topic = string.format("gw/%s/%s/%s/tele/HEARTBEAT", self.client, self.ville, self.device)
        var payload = string.format('{"Device":"%s","Name":"%s","Time":"%s","AccessPoint":"%s","IpAddress":"%s"}', self.device, self.device, timestamp, ap, ip)
        mqtt.publish(topic, payload, true)
    end
end

stm32 = STM32()
global.stm32 = stm32
tasmota.add_driver(stm32)
tasmota.add_fast_loop(/-> stm32.fast_loop())
var cron_second = get_cron_second()
var cron_pattern = string.format("%d 59 23 * * *", cron_second)
tasmota.add_cron(cron_pattern, /-> stm32.get_statistic(), "every_day")
print("cron statistic:" + cron_pattern)
cron_pattern = string.format("%d %d * * * *", cron_second, cron_second)
tasmota.add_cron(cron_pattern, /-> stm32.heartbeat(), "every_hour")
print("cron heartbeat:" + cron_pattern)
