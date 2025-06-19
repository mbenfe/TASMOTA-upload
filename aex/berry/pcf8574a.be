
import string

class PCF8574A
    var i2c_addr
    var wire
    var state

    def init()
#        print("wire scan ",wire1.scan())
        for i:0..255
            self.i2c_addr = 0x00 + i  # PCF8574 with A0, A1, A2 grounded
            self.wire = tasmota.wire_scan(self.i2c_addr)
            if self.wire == nil
        #        print("PCF8574 not found on I2C bus : ",self.i2c_addr)
            else 
                print("trouve !!!!!!!!!!!!!",self.i2c_addr)
            end
#            return
        end
        self.i2c_addr = 0x39  # PCF8574 with A0, A1, A2 grounded
        self.wire = tasmota.wire_scan(self.i2c_addr)
        if self.wire == nil
            print("PCF8574 not found on I2C bus 0x39")
            return
        end
        print("PCF8574 found!")
        self.state = 0xFF  # All pins high (inputs by default)
        self.wire.write_byte(self.i2c_addr, self.state)
    end

    def read_buttons()
        if self.wire != nil
            var value = self.wire.read_byte(self.i2c_addr)
            # Buttons are on P0, P3, P6 (active low)
            var p0 = (value & 0x01) == 0
            var p3 = (value & 0x08) == 0
            var p6 = (value & 0x40) == 0
            print("P0:", p0, "P3:", p3, "P6:", p6)
            return [p0, p3, p6]
        else
            return [false, false, false]
        end
    end

    def set_outputs(p1, p2, p4, p5, p7)
        # Outputs: P1, P2, P4, P5, P7
        # Buttons (inputs): P0, P3, P6 (must be set to 1 to be input)
        self.state = 0xFF
        # Set output pins to 0 or 1 as requested
        if !p1
            self.state = self.state & ~(1 << 1)
        end
        if !p2
            self.state = self.state & ~(1 << 2)
        end
        if !p4
            self.state = self.state & ~(1 << 4)
        end
        if !p5
            self.state = self.state & ~(1 << 5)
        end
        if !p7
            self.state = self.state & ~(1 << 7)
        end
        if(self.wire != nil)
            print("Setting outputs to:", string.format("0x%02X", self.state))
            # Write the new state to the PCF8574
            self.wire.write_byte(self.i2c_addr, self.state)
        end
    end

    def every_second()
        self.read_buttons()
        # Example: set all outputs high
        # self.set_outputs(true, true, true, true, true)
    end
end

pcf = PCF8574A()
tasmota.add_driver(pcf)