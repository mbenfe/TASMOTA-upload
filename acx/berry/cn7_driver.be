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

class RDX
    var io_rst
    var io_bsl
    var temperature
    var status
    var scheduler
    var reglage
    var day_list

    var rx
    var tx
    var ser

    def set_stm32()
        var status = string.format("%d:%d:%d:%d",self.status['onoff'],self.status['mode'],self.status['fanspeed'],self.status['heatpower'])
        self.ser.write(bytes().fromstring(status))
        print('status send to stm32:',status)
    end
    

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
    end


    def init()
        import path
       var file
        var buffer
        var myjson
        var topic
        mqttprint('init')
        mqttprint('io init')
        self.io_rst = 18
        self.io_bsl = 19
        gpio.pin_mode(self.io_rst, gpio.OUTPUT)
        gpio.pin_mode(self.io_bsl, gpio.OUTPUT)
        mqttprint('io mode set')
        gpio.digital_write(self.io_rst, 1)    
        gpio.digital_write(self.io_bsl, 0)    
        mqttprint('io init done')
       file = open("setup.json", "rt")
        if(file == nil)
            mqttprint("file not found: setup.json")
            return
        end
        buffer = file.read()
        myjson = json.load(buffer)

        file.close()
        self.scheduler = myjson["scheduler"]
        self.status = myjson["status"]
        self.reglage = myjson["reglage"]
        self.temperature = myjson["temperature"]
        self.day_list = ["dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"]

        self.rx = 8
        self.tx = 7
        gpio.pin_mode(self.rx,gpio.INPUT)
        gpio.pin_mode(self.tx,gpio.OUTPUT)
        self.ser = serial(self.rx,self.tx,115200,serial.SERIAL_8N1)
        self.set_stm32()
         self.subscribes()   
        tasmota.set_timer(30000,/-> self.mypush())

    end

    def subscribes()
        var topic 
        # rideaux
        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.acknowlege_app(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to SETUP")
    end

    def every_minute()
        if(self.reglage ==0)
        else
        end
    end  

    def every_second()
    end
end

rdx = RDX()

tasmota.add_driver(rdx)
tasmota.add_cron("0 * * * * *", /-> rdx.every_minute(), "every_min_@0_s")