import mqtt
import string
import json
import global

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, texte, true)
    return true
end

class HTCHX
    var ser

    def init()
        print('DRIVER: initializing HTCHX driver') 
        gpio.pin_mode(6, gpio.INPUT)
        gpio.pin_mode(20, gpio.OUTPUT)
        self.ser = serial(6,20,921600,serial.SERIAL_8N1)
        tasmota.add_fast_loop(/-> self.fast_loop())
        print('DRIVER: HTCHX driver initialized')
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
            print(mystring)
        end
    end

 
    # Function to subscribe to MQTT topics
    def subscribes()
    end

    def every_minute()
    end

    def every_second()
    end
end

htchx = HTCHX()
tasmota.add_driver(htchx)
tasmota.add_cron("0 * * * * *", /-> htchx.every_minute(), "every_min_@0_s")