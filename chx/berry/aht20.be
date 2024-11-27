import mqtt
import string

class AHT20
    var i2c_addr
    var wire

    def init()
        self.i2c_addr = 0x38  # AHT20 I2C address
        self.wire = tasmota.wire_scan(self.i2c_addr, 58)  # Scan for the device on the I2C bus
        if self.wire == nil
            mqttprint("AHT20 not found on I2C bus")
            return
        end
        mqttprint("AHT20 found!")
        self.initialize_sensor()
    end

    def initialize_sensor()
        if(self.wire==nil)
            return
        end
        self.wire.write_bytes(self.i2c_addr, 0x00, bytes([0xBE, 0x08, 0x00]))
        tasmota.delay(20)  # Wait for the sensor to initialize
    end

    def read_data()
        if(self.wire==nil)
            return
        end
        self.wire.write_bytes(self.i2c_addr, 0x00, bytes([0xAC, 0x33, 0x00]))
        tasmota.delay(80)  # Wait for the measurement to complete
        var data = self.wire.read_bytes(self.i2c_addr, 0x00, 7)
        return data
    end

    def parse_data(data)
        var humidity_raw = ((data[1] << 12) | (data[2] << 4) | (data[3] >> 4))
        var temperature_raw = (((data[3] & 0x0F) << 16) | (data[4] << 8) | data[5])
        var humidity = (humidity_raw * 100.0) / 1048576.0
        var temperature = ((temperature_raw * 200.0) / 1048576.0) - 50.0
        return [temperature, humidity]
    end

    def read_temperature_humidity()
        var data = self.read_data()
        if data == nil
            return
        end
        var parsed_data = self.parse_data(data)
        return parsed_data
    end
end

aht20 = AHT20()
aht20.init()
tasmota.add_driver(aht20)
