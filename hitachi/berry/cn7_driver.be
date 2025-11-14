import mqtt
import string
import json
import global
import gpio

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, texte, true)
    return true
end

class CN7
    var rst
    var bsl
    var day_list

    var rx
    var tx
    var ser
    var setup

    def acknowlege_app(topic, idx, payload_s, payload_b)
        var myjson
        var newtopic
        var newpayload
        var file
        var buffer

        myjson = json.load(payload_s)
        print("acknowledge_app:", topic," ",payload_s)
        newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        newpayload = string.format('{"Device":"%s","Name":"%s","DATA":%s}',
                    global.device, global.device, payload_s)
        mqtt.publish(newtopic, newpayload, true)
        file = open("setup.json", "wt")
        file.write(payload_s)
        file.close()

        self.temperature = myjson["temperature"]
        self.status = myjson["status"]
        self.scheduler = myjson["scheduler"]
        self.reglage = myjson["reglage"]
        print("setup.json read done")
        self.set_stm32()
     end

    def mypush()
        var file
        var myjson        
            
        file = open("setup.json", "rt")
        if file == nil
            mqttprint("Error: Failed to open file setup.json")
            return
        end
        myjson = file.read()
        file.close()
        var  newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        var payload = string.format('{"Device":"%s","Name":"%s","DATA":%s}',
                    global.device, global.device, myjson)
        print('setup:', newtopic, ' ', payload)
        mqtt.publish(newtopic, payload, true) 
        self.set_stm32()
    end

    def set_stm32()
        var texte = string.format("%d:%d:%d:%d", self.setup['onoff'], self.setup['mode'], self.setup['fanspeed'], self.setup['fanswing'])
        self.ser.write(bytes().fromstring(texte))
    end


    def init()
        import path
        var file
        var buffer
        var myjson
        var topic
        mqttprint('init')
        global.rst_pin = 20
        gpio.pin_mode(global.rst_pin, gpio.OUTPUT)
        gpio.digital_write(global.rst_pin, 1)    
        file = open("setup.json", "rt")
        if(file == nil)
            mqttprint("file not found: setup.json")
            return
        end
        buffer = file.read()
        myjson = json.load(buffer)

        file.close()
        self.setup = myjson
        self.day_list = ["dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"]

        self.rx = 21
        self.tx = 9
        gpio.pin_mode(self.rx,gpio.INPUT)
        gpio.pin_mode(self.tx,gpio.OUTPUT)
        self.ser = serial(self.rx,self.tx,921600,serial.SERIAL_8N1)
        print("serial", self.ser)
        self.subscribes()
        tasmota.set_timer(30000,/-> self.mypush())
    end

    def subscribes()
        var topic 
        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.acknowlege_app(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to SETUP")
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
        if self.ser.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = self.ser.read()
            self.ser.flush()
            mystring = buffer.asstring()
            mylist = string.split(mystring,'\n')
            numitem = size(mylist)
            for i:0..numitem-2
                myjson = json.load(mylist[i])
               print(myjson)
            end
        end
    end

    def every_minute()
    end  

    def every_second()
    end
end

var cn7 = CN7()

tasmota.add_driver(cn7)
tasmota.add_cron("0 * * * * *", /-> cn7.every_minute(), "every_min_@0_s")
tasmota.add_fast_loop(/-> cn7.fast_loop())