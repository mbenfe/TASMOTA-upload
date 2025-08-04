# layout:
# P1: left button
# P2: middle button
# P3: right button
#
# P0: Led1
# P4: Led2
# P5: Led3
# P6: Led4
# P7: Led5
#
# P1 pressed toogle Led1
# P2 pressed toogle Led2
# P3 pressed toogle Led4

import string

class PCF8574A
    var i2c_addr, wire, state

    def init()
        self.i2c_addr = 0x3F
        self.wire = tasmota.wire_scan(self.i2c_addr)
        if self.wire == nil
            print("PCF8574 not found")
            return
        end
        print("PCF8574 found!")
        self.state = 0xFF  # All high = inputs
        self.write_pins(self.state)
    end

    def write_pins(value)
        if self.wire != nil
            self.wire._begin_transmission(self.i2c_addr)
            self.wire._write(value)
            self.wire._end_transmission()
        end
    end

    def read_pins()
        var data
        if self.wire != nil
 #           print(self.state)
 #           data = self.wire.read(self.i2c_addr, self.state, 1)
            data = self.wire.read(self.i2c_addr, 0xFF, 1)
            return (data != nil ) ? data : 0xF1
        end
        return 0xFF
    end

    def toggle_bit(bit)
        self.state = self.state ^ (1 << bit)
        self.state = self.state | 0x0E  # P1, P2, P3 à 1
        self.write_pins(self.state)
    end

    def every_250ms()
        if self.wire == nil return end

        var input_state = self.read_pins()
        print(input_state)

        if ((input_state & 0x02) == 0x02)  # P1 button pressed
            print("P1 pressed")
            self.toggle_bit(0)          # Toggle LED1 on P0
        end

        if ((input_state & 0x04) == 0x04)  # P2 button pressed
            print("P2 pressed")
            self.toggle_bit(4)          # Toggle LED2 on P4
        end

        if ((input_state & 0x08) == 0x08)  # P3 button pressed
            print("P3 pressed")
            self.toggle_bit(6)          # Toggle LED4 on P6
        end
    end
end

var pcf = PCF8574A()
tasmota.add_driver(pcf)
