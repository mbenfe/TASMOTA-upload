# layout:
# P0: Led1 = bit 0
# P1: left button = bit 1
# P2: middle button = bit 2
# P3: right button = bit 3
# P4: Led5 = bit 4
# P5: Led4 = bit 5
# P6: Led3 = bit 6
# P7: Led2 = bit 7
#
# P1 pressed toogle Led1 P0 bit 0
# P2 pressed toogle Led3 P5 bit 5
# P3 pressed toogle Led4 P6 bit 6

import string
import global

class PCF8574A
    var pcf8574a_addr, state,last_input_state,input_state
    var left_pressed, middle_pressed, right_pressed

    def init()
        var list_devices
        self.pcf8574a_addr = 0x3F
        if global.wire == nil
            global.wire = tasmota.wire_scan(self.pcf8574a_addr)
            list_devices = global.wire.scan()
            if (list_devices.find(0x3F)== nil)
                print("PCF8574A not found")
            else
                print("PCF8574A found!")
            end
            if (list_devices.find(0x48)== nil)
                print("ADS1115 not found")
            else
                print("ADS1115 found!")
            end
        end
        global.io = 0xFF  # All high = inputs
        self.last_input_state = 0xFF
        self.input_state = 0xFF
        self.write_pins(global.io)
        self.left_pressed = false
        self.middle_pressed = false 
        self.right_pressed = false
    end

    def write_pins(value)
        if global.wire != nil
            global.wire._begin_transmission(self.pcf8574a_addr)
            global.wire._write(value)
            global.wire._end_transmission()
        end
    end

    def read_pins()
        var data
        if global.wire != nil
 #           print(global.io)
            data = global.wire.read(self.pcf8574a_addr, global.io, 1)
            return (data != nil ) ? data : 0xF1
        end
        return 0xFF
    end

    def toggle_bit(bit)
        global.io = global.io ^ (1 << bit)
        global.io = global.io | 0x0E  # P1, P2, P3 à 1
#        print("toggle bit: " + str(bit) + " state: " + string.hex(global.io))
        self.write_pins(global.io)
    end

    def every_250ms()
        if global.wire == nil return end

        self.input_state = self.read_pins()

#        print(self.input_state)

        # edge up detection left button
        if ((self.input_state & 0x02) == 0x02) && ((self.last_input_state & 0x02) == 0x00 && self.left_pressed == false)  # P1 button pressed
#            print("P1 pressed")
            self.left_pressed = true
            self.toggle_bit(0)          # Toggle LED1 on P0
        end
        # edge down detection left button
        if ((self.input_state & 0x02) == 0x00) && ((self.last_input_state & 0x02) == 0x02 && self.left_pressed == true)  # P1 button pressed
#            print("P1 released")
            self.left_pressed = false
        end

        # edge up detection middle button
        if ((self.input_state & 0x04) == 0x04) && ((self.last_input_state & 0x04) == 0x00 && self.middle_pressed == false)  # P2 button pressed
#            print("P2 pressed")
            self.middle_pressed = true
            self.toggle_bit(7)          # Toggle LED2 on P7
        end
        # edge down detection middle button
        if ((self.input_state & 0x04) == 0x00) && ((self.last_input_state & 0x04) == 0x04 && self.middle_pressed == true)  # P2 button released
#            print("P2 released")
            self.middle_pressed = false
        end
        # edge up detection right button
        if ((self.input_state & 0x08) == 0x08) && ((self.last_input_state & 0x08) == 0x00 && self.right_pressed == false)  # P3 button pressed
#            print("P3 pressed")
            self.right_pressed = true
            self.toggle_bit(5)          # Toggle LED4 on P5
        end
        # edge down detection right button
        if ((self.input_state & 0x08) == 0x00) && ((self.last_input_state & 0x08) == 0x08 && self.right_pressed == true)  # P3 button released
#            print("P3 released")
            self.right_pressed = false
        end

        self.last_input_state = self.input_state
    end
    
end

var pcf = PCF8574A()
tasmota.add_driver(pcf)
