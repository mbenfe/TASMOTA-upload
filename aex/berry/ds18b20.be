import mqtt
import string

class DS18B20
    var i2c_addr
    var wire
    var humidity
    var temperature

    def init()
    end


    def poll()
        var data = tasmota.read_sensors()
        if(data == nil)
            return -99
        end
        var myjson = json.load(data)
        var temperature = myjson["DS18B20"]["Temperature"]
         return temperature
    end

end

ds18b20 = DS18B20()
ds18b20.init()
tasmota.add_driver(ds18b20)