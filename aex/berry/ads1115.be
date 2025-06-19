import mqtt
import string
import global

class ADS1115
    var i2c_addr
    var wire
    var temperature1
    var temperature2
    var sample


    def init()
        self.i2c_addr = 0x48  # ADS1115 I2C address
        self.wire = tasmota.wire_scan(self.i2c_addr)
        if self.wire == nil
            print("ADS1115 not found on I2C bus")
            return
        end
        print("ADS1115 found!")
        self.temperature1 = []
        self.temperature2 = []
        for i:0..59
            self.temperature1.insert(i,0)
            self.temperature2.insert(i,0)
        end
        if (path.exists("calibration.json"))
            var file = open("calibration.json", "rt")
            var myjson = file.read()
            file.close()
            var calibration = json.load(myjson)
            global.factor1 = real(calibration["pt1"])
            global.factor2 = real(calibration["pt2"])
        else
            print("calibration.json not found, using default factors")
            global.factor1 = 150
            global.factor2 = 150
            var file = open("calibration.json", "wt")
            var calibration = json.dump({"pt1": global.factor1, "pt2": global.factor2})
            file.write(calibration)
            file.close()
        end
        self.sample = 0
    end

    def every_second()
        # PT1 on A0, PGA = ±6.144V (highest FSR), DR = 8SPS
        self.wire._begin_transmission(self.i2c_addr)
        self.wire._write(0x01)
        # Config register for A0, 8SPS, PGA=±6.144V:
        # MSB: 0xC0 = 1100 0000
        #   [15] OS        = 1 (start single conversion)
        #   [14:12] MUX[2:0]= 100 (AIN0 vs GND)
        #   [11:9] PGA[2:0]= 000 (FSR = ±6.144V)
        #   [8] MODE       = 0 (continuous conversion)
        # LSB: 0x83 = 1000 0011
        #   [7:5] DR[2:0]  = 000 (8 SPS)
        #   [4] COMP_MODE  = 0 (traditional comparator)
        #   [3] COMP_POL   = 0 (active low)
        #   [2] COMP_LAT   = 0 (non-latching)
        #   [1:0] COMP_QUE = 11 (disable comparator)
        self.wire._write(0xC0)   # MSB
        self.wire._write(0x83)   # LSB
        self.wire._end_transmission()
#        tasmota.delay(8)
        var measure = self.wire.read_bytes(self.i2c_addr, 0x00, 2)
        var value = (measure[0] << 8) | measure[1]
        if value >= 0x8000
            value = value - 0x10000
        end
        self.temperature1.setitem(self.sample, (real(value) / real(global.factor1)))

        # PT2 on A1, PGA = ±6.144V (highest FSR), DR = 8SPS
        self.wire._begin_transmission(self.i2c_addr)
        self.wire._write(0x01)
        # Config register for A1, 8SPS, PGA=±6.144V:
        # MSB: 0xD0 = 1101 0000
        #   [15] OS        = 1 (start single conversion)
        #   [14:12] MUX[2:0]= 101 (AIN1 vs GND)
        #   [11:9] PGA[2:0]= 000 (FSR = ±6.144V)
        #   [8] MODE       = 0 (continuous conversion)
        # LSB: 0x83 = 1000 0011 (same as above)
        self.wire._write(0xD0)   # MSB
        self.wire._write(0x83)   # LSB
        self.wire._end_transmission()
#        tasmota.delay(8)
        measure = self.wire.read_bytes(self.i2c_addr, 0x00, 2)
        value = (measure[0] << 8) | measure[1]
        if value >= 0x8000
            value = value - 0x10000
        end
        self.temperature2.setitem(self.sample, (real(value) / real(global.factor2)))
        if self.sample == 59
            self.sample = 0
            global.average_temperature1 = 0
            global.average_temperature2 = 0
            for i:0..59
                global.average_temperature1 += self.temperature1.item(i)
                global.average_temperature2 += self.temperature2.item(i)
            end
            global.average_temperature1 /=  60
            global.average_temperature2 /=  60 
        else
            self.sample += 1
        end
    end
end

ads1115 = ADS1115()
tasmota.add_driver(ads1115)