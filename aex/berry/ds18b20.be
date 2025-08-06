import mqtt
import string

class DS18B20
    var i2c_addr
    var humidity
    var temperature

    def init()
    end


    def poll(target)
        var temperature = -99
        var data = tasmota.read_sensors()
        if(data == nil)
            return -99
        end
        var myjson = json.load(data)
        print("DS18B20 data: " + str(myjson))
        if !myjson.contains("DS18B20-1") && target == "dsin"
            return -99
        end
        if !myjson.contains("DS18B20-2") && target == "ds"
            return -99
        end

        if target == "dsin"
            temperature = myjson["DS18B20-1"]["Temperature"]
        elif target == "ds"
            temperature = myjson["DS18B20-2"]["Temperature"]
        else
            return -99
        end
        return temperature
    end

end

ds18b20 = DS18B20()
tasmota.add_driver(ds18b20)