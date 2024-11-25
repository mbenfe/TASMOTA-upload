import mqtt
import string
import i2c

class AHT20
    var i2c_addr
    var i2c_bus

    def init()
        self.i2c_addr = 0x38  # AHT20 I2C address
        self.i2c_bus = i2c(1, 8, 9)  # Initialize I2C bus 1 with SDA on GPIO8 and SCL on GPIO9
        self.initialize_sensor()
    end

    def initialize_sensor()
        self.i2c_bus.write(self.i2c_addr, bytes([0xBE, 0x08, 0x00]))
        tasmota.delay(20)  # Wait for the sensor to initialize
    end

    def read_data()
        self.i2c_bus.write(self.i2c_addr, bytes([0xAC, 0x33, 0x00]))
        tasmota.delay(80)  # Wait for the measurement to complete
        var data = self.i2c_bus.read(self.i2c_addr, 7)
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
        var parsed_data = self.parse_data(data)
        return parsed_data
    end
end

aht20 = AHT20()
tasmota.add_driver(aht20)