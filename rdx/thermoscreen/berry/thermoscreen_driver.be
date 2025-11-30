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

    def poll()
        var temperature = 99
        
        # Priority 1: Use remote sensor if available and valid
        if (global.config["remote"] != "nok" && global.remote_temp != nil)
            temperature = global.remote_temp
            return temperature
        end
        
        # Priority 2: Fallback to local DS18B20
        global.dsin = 99
        var data = tasmota.read_sensors()
        if(data == nil)
            return 99
        end
        var myjson = json.load(data)
        if(myjson.contains("DS18B20"))
            global.dsin = myjson["DS18B20"]["Temperature"]
            temperature = global.dsin + global.dsin_offset
            return temperature
        end
        
        return 99  # No temperature source available
    end

    def check_gpio()
        # Check if GPIOs are configured correctly
        var gpio_result = tasmota.cmd("Gpio")
        
        if gpio_result != nil
            
            # Check GPIO8 (DS18x20-1 - 1312)
            if gpio_result['GPIO8'] != nil
                if !gpio_result['GPIO8'].contains('1312')
                    mqttprint("WARNING: GPIO8 not DS18x20-1! Reconfiguring...")
                    tasmota.cmd("Gpio8 1312")
                end
            end            
        else
            mqttprint("ERROR: Cannot read GPIO configuration")
            return false
        end
        
        return true
    end

    def set_stm32()
        var status = string.format("%d:%d:%d:%d",global.setup['onoff'],global.setup['mode'],global.setup['fanspeed'],global.setup['heatpower'])
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
        newpayload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}',
                    global.device, global.device, json.dump(myjson["DATA"]))
        mqtt.publish(newtopic, newpayload, true)
        global.setup    = myjson["DATA"] 
        file = open("setup.json", "wt")
        file.write(json.dump(global.setup))
        file.close()
        self.set_stm32()
        self.every_minute()
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
        var payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}',
                    global.device, global.device, myjson)
        print('setup:', newtopic, ' ', payload)
        mqtt.publish(newtopic, payload, true) 
        self.every_minute()
    end

    def init()
        import path
        var file
        var buffer
        var myjson
        var topic
        # mqttprint('init')
        # mqttprint('io init')
        self.io_rst = 18
        # self.io_bsl = 19
        gpio.pin_mode(self.io_rst, gpio.OUTPUT)
        # gpio.pin_mode(self.io_bsl, gpio.OUTPUT)
        # mqttprint('io mode set')
        gpio.digital_write(self.io_rst, 1)    
        # gpio.digital_write(self.io_bsl, 0)    
        # mqttprint('io init done')

        self.day_list = ["dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"]

        self.rx = 6
        self.tx = 7
        gpio.pin_mode(self.rx,gpio.INPUT)
        gpio.pin_mode(self.tx,gpio.OUTPUT)
        self.ser = serial(self.rx,self.tx,115200,serial.SERIAL_8N1)

        self.set_stm32()
        self.subscribes()   
        tasmota.set_timer(30000,/-> self.mypush())
      
        if (global.config["remote"] != "nok")           
            self.subscribes_sensors(global.config["remote"])
        end
    end

    def subscribes()
        var topic 
        # rideaux
        topic = string.format("app/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.acknowlege_app(topic, idx, payload_s, payload_b))
        mqttprint("subscribed to SETUP")
    end

    def every_minute()
        var now = tasmota.rtc()
        var rtc = tasmota.time_dump(now["local"])
        var second = rtc["sec"]
        var minute = rtc["min"]
        var hour = rtc["hour"]
        var day = rtc["day"]
        var month = rtc["month"]
        var year = rtc["year"]
        var day_of_week = rtc["weekday"]  # 0=Sunday, 1=Monday, ..., 6=Saturday
        var jour = self.day_list[day_of_week]

        var target,status,power,temperature

        self.check_gpio()

        if (hour >= global.setup[jour]['debut'] && hour < global.setup[jour]['fin'])
            target = global.setup['ouvert']
            status = "ouvert"
        else
            target = global.setup['ferme']
            status = "ferme"
        end

        temperature = self.poll()
        if(temperature < target)
            self.set_stm32()
            power = 1
        else
#            var standby = string.format("%d:%d:1:1",global.setup['onoff'],global.setup['mode'])
            var standby = string.format("0:%d:%d:%d",global.setup['mode'],global.setup['fanspeed'],global.setup['heatpower'])
            self.ser.write(bytes().fromstring(standby))
            power = 0
        end

        var topic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)

         var payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"ouvert":%.1f,"ferme":%.1f,"onoff":%d,"target":%d,"etat":"%s","power":%d}',
                global.device, global.device, temperature, global.setup['ouvert'], global.setup['ferme'], global.setup['onoff'],target,status,power)
        mqtt.publish(topic, payload, true)
    end

    def fast_loop()
        self.read_uart(2)
    end

    def read_uart(timeout)
        if self.ser.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = self.ser.read()
            self.ser.flush()
            var mystring = buffer.asstring()
            var mylist = string.split(mystring, '\n')
            var numitem = size(mylist)
            for i: 0..numitem-2
                var split = string.split(mylist[i], ":")
                global.setup['onoff'] = int(split[0])
                global.setup['mode'] = int(split[1])
                global.setup['fanspeed'] = int(split[2])
                global.setup['heatpower'] = int(split[3])
                var file = open("setup.json", "wt")
                file.write(json.dump(global.setup))
                file.close()
                var  newtopic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
                var payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}',
                    global.device, global.device, json.dump(global.setup))
                mqtt.publish(newtopic, payload, true) 
            end
        end
    end

    def remote_sensor(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        print("remote sensor data received: " + payload_s)
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end
        var sensor = myjson["Name"]
        if global.config["remote"] == sensor
            if myjson.contains("Temperature")
                global.remote_temp = real(myjson["Temperature"])

            else
                mqttprint("Error: Temperature data not found in payload for device " + sensor)
            end
        end
    end
    # Function to subscribe to MQTT topics
    def subscribes_sensors(sensor)
        var topic
        topic = string.format("gw/%s/%s/zb-%s/tele/SENSOR", global.client, global.ville, sensor)
        mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.remote_sensor(topic, idx, payload_s, payload_b))
        print("subscribed to remote sensor:" + topic)
    end
end

rdx = RDX()

tasmota.add_fast_loop(/-> rdx.fast_loop())
tasmota.add_driver(rdx)
tasmota.add_cron("0 * * * * *", /-> rdx.every_minute(), "every_min_@0_s")