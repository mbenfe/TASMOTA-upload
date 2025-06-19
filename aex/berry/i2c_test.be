import mqtt
import string
import global

class I2C
    var i2c_addr
    var wire

    def init()
        print("init I2C test driver")
        for i:10..127
            self.i2c_addr =  i  # Scan all possible I2C addresses
            self.wire = tasmota.wire_scan(self.i2c_addr)
            if self.wire != nil
                print("I2C found at address:", self.i2c_addr)
            end
        end
    end

    def every_second()
        print("i2c:",wire1.scan())
    end
end

i2c = I2C()
tasmota.add_driver(i2c)