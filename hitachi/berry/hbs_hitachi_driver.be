import mqtt
import string
import json
import global


def mqttprint(texte)
    var payload =string.format("{\"texte\":\"%s\"}", texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, payload, true)
    return true
end

class HBSX
    var day_list
    var count

    # Initialization function
    def init()
        var file
        var myjson        

        print("HBSX driver initialization")
        var name = "setup.json"
        file = open(name, "rt")
        if file == nil
            mqttprint("Error: Failed to open file " + name)
        end
        myjson = file.read()
        file.close()
        global.setup = json.load(myjson)
        if global.setup == nil
            mqttprint("Error: Failed to parse JSON from file " + name)
        end
       

        self.day_list = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
        global.relay = list()
        global.relay.insert(0, 19)
        global.relay.insert(1, 18)
        gpio.pin_mode(global.relay[0], gpio.OUTPUT)
        gpio.pin_mode(global.relay[1], gpio.OUTPUT)
        gpio.digital_write(global.relay[0], 0)  # Set relay 1 to OFF
        gpio.digital_write(global.relay[1], 0)  # Set relay 2 to OFF
        print("relay OFF")
        print("HBSX driver initialized")

    end


    # Function to execute every minute
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
        print(string.format("Current time: %02d:%02d:%02d on %s %02d/%02d/%04d", hour, minute, second, jour, day, month, year))

    end

    # Function to execute every second
    def every_second()
    end   

end

var hbsx = HBSX()
global.hbsx = hbsx  # Add this line to make hbsx accessible globally
tasmota.add_driver(hbsx)
tasmota.add_cron("0 * * * * *", /-> hbsx.every_minute(), "every_min_@0_s")