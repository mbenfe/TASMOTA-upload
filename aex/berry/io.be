import string

var PRESSED = false
var LED_ON = false
var LED_OFF = true

class PCF8574A
    var i2c_addr
    var wire
    var state

    def init()
        self.i2c_addr = 0x3F  # PCF8574 with A0, A1, A2 at high
        self.wire = tasmota.wire_scan(self.i2c_addr)
        if self.wire == nil
            print("PCF8574 not found on I2C bus 0x3F")
            return
        end
        print("PCF8574 found!")
        self.state = 0xFF  # All pins high (inputs by default)
#        self.wire.write(self.i2c_addr, 0x7E, self.state,1)
        # for i:0..10
        #     tasmota.delay(300)
        #     self.wire.write(self.i2c_addr, 0x7E, 0x49,1)
        #     #self.set_outputs(false, false, false, false, false)  # Set all LEDs off
        #     tasmota.delay(300)
        #     self.wire.write(self.i2c_addr, 0x7E, self.state,1)
        #     #self.set_outputs(true, true, true, true, true)  # Set all LEDs on
        # end
        # tasmota.delay(300)
        # self.set_outputs(false, false, false, false, false)  # Set all LEDs off
        # self.wire.write(self.i2c_addr, 0x7E, 0xFF,1)
        # tasmota.delay(1000)
        # self.wire.write(self.i2c_addr, 0x7E, 0xFE,1)
        # tasmota.delay(1000)
        # self.wire.write(self.i2c_addr, 0x7E, 0xFF,1)
        # tasmota.delay(1000)
        # self.wire.write(self.i2c_addr, 0x7E, 0x7F,1)
        # tasmota.delay(1000)
        # self.wire.write(self.i2c_addr, 0x7E, 0xFF,1)
        # tasmota.delay(1000)
        # self.wire.write(self.i2c_addr, 0x7E, 0xBF,1)
        # tasmota.delay(1000)
        # self.wire.write(self.i2c_addr, 0x7E, 0xFF,1)
        # tasmota.delay(1000)
        # self.wire.write(self.i2c_addr, 0x7E, 0xDF,1)
        # tasmota.delay(1000)
        # self.wire.write(self.i2c_addr, 0x7E, 0xFF,1)
        # tasmota.delay(1000)
        # self.wire.write(self.i2c_addr, 0x7E, 0xEF,1)
        # tasmota.delay(1000)
        # self.wire.write(self.i2c_addr, 0x7E, 0xFF,1)
    end

    def read_buttons()
        if self.wire != nil
            print(self.wire.read(self.i2c_addr, 0x7F, 1))
            var value = self.wire.read(self.i2c_addr,0x7F,1)
            print(value)
            # Buttons are on P1, P2, P3 (active low)
            var p1 = (value & 0x02) == 0
            var p2 = (value & 0x04) == 0
            var p3 = (value & 0x08) == 0
            print("P1:", p1, "P2:", p2, "P3:", p3)
            return [p1, p2, p3]
        else
            return [false, false, false]
        end
    end

    def set_outputs(p0, p4, p5, p6, p7)
        # LEDs: P0, P4, P5, P6, P7
        # Buttons (inputs): P1, P2, P3 (must be set to 1 to be input)
        self.state = 0xFF
        # Set output pins to 0 or 1 as requested
        if !p0
            self.state = self.state & ~(1 << 0)
        end
        if !p4
            self.state = self.state & ~(1 << 4)
        end
        if !p5
            self.state = self.state & ~(1 << 5)
        end
        if !p6
            self.state = self.state & ~(1 << 6)
        end
        if !p7
            self.state = self.state & ~(1 << 7)
        end
        if(self.wire != nil)
            print("Setting outputs to:", string.format("0x%02X", self.state))
            self.wire.write(self.i2c_addr, 0x7E, self.state, 1)
        end
    end

    def every_250ms()
        # Example: read buttons and set outputs based on their state
        var buttons = self.read_buttons()
        print("Buttons state:", buttons)
        if buttons[0] == PRESSED # P1 pressed
            self.set_outputs(LED_ON, LED_OFF, LED_OFF, LED_OFF, LED_OFF)
        elif buttons[1] == PRESSED # P2 pressed
            self.set_outputs(LED_OFF, LED_ON, LED_OFF, LED_OFF, LED_OFF)
        elif buttons[2] == PRESSED # P3 pressed
            self.set_outputs(LED_OFF, LED_OFF, LED_ON, LED_OFF, LED_OFF)
        else
            self.set_outputs(LED_OFF, LED_OFF, LED_OFF, LED_ON, LED_ON)  # Default state
        end
    end

    # def every_second()
    #     self.read_buttons()
    #     # Example: set all LEDs on
    #     # self.set_outputs(true, true, true, true, true)
    # end
end

var pcf = PCF8574A()
tasmota.add_driver(pcf)