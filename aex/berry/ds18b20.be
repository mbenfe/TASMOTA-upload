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
        if !myjson.contains("DS18B20")
            return -99
        end
         print("--------------------")
         print('measure:'+str(myjson["DS18B20"]["Temperature"]))
         print('measure:'+str(myjson["DS18B20"]["Humidity"]))
         print('measure:'+str(myjson["DS18B20"]["Status"]))
         print('measure:'+str(myjson["DS18B20"]["Reglage"]))
        var temperature = myjson["DS18B20"]["Temperature"]
         return temperature
    end

end

ds18b20 = DS18B20()
ds18b20.init()
tasmota.add_driver(ds18b20)