import mqtt
import string
import math

class AHT20
    var i2c_addr
    var wire
    var humidity
    var temperature
    var thermostat
    var day_list

    def init()
        var now = tasmota.rtc()
        var delay
        var mycron
        math.srand(now["local"])

        var file = open("thermostat_intermarche.json", "rt")
        var myjson = file.read()
        file.close()
        self.thermostat = json.load(myjson)  

        self.day_list = ["dimanche","lundi","mardi","mercredi","jeudi","vendredi","samedi"]

        self.i2c_addr = 0x38  # AHT20 I2C address
        self.wire = tasmota.wire_scan(self.i2c_addr)  # Scan for the device on the I2C bus
        if self.wire == nil
            mqttprint("AHT20 not found on I2C bus")
            return
        end
        mqttprint("AHT20 found!")
    end

    def poll()
        var measure
        var now = tasmota.rtc()
        var rtc=tasmota.time_dump(now["local"])
        var second = rtc["sec"]
        var minute = rtc["min"]
        var hour = rtc["hour"]
        var day = rtc["day"]
        var month = rtc["month"]
        var year = rtc["year"]
        var day_of_week = rtc["weekday"]  # 0=Sunday, 1=Monday, ..., 6=Saturday

        var jour = self.day_list[day_of_week]
        if(self.wire==nil)
            self.i2c_addr = 0x38  # AHT20 I2C address
            self.wire = tasmota.wire_scan(self.i2c_addr)  # Scan for the device on the I2C bus
            if self.wire == nil
                print("AHT20 not found again")
                var humidity = 40 + math.rand() % 20
                var temperature
                print("simulation")
                if (hour >= self.thermostat[jour]['debut'] && hour < self.thermostat[jour]['fin'])
                    temperature = real(self.thermostat['ouvert']) - real(math.rand() % 10)/real(10) + real(self.thermostat['offset'])
                else
                    temperature = real(self.thermostat['ferme']) + 1 + real(math.rand() % 10)/real(10) + real(self.thermostat['offset'])
                end
                return[temperature,humidity]
            else
                print("AHT20 found again!")
                self.initialize_sensor()
            end
        end    
        self.wire._begin_transmission(0x38)
        self.wire._write(0xAC)
        self.wire._write(0x33)
        self.wire._write(0x00)
        self.wire._end_transmission()
        tasmota.delay(80)
        measure = self.wire.read_bytes(0x38,0x71,7)
        self.humidity=number('0x'+measure[1..3].tohex())
        self.humidity = self.humidity>>4
        self.humidity = real(self.humidity) / real(1048576)
        self.humidity*=100
        self.temperature=number('0x'+measure[3..5].tohex())
        self.temperature &= 0x0FFFFF
        self.temperature = real(self.temperature) / real(1048576)
        self.temperature*=200
        self.temperature-=50
        return[self.temperature, self.humidity]
    end

end

aht20 = AHT20()
aht20.init()
tasmota.add_driver(aht20)