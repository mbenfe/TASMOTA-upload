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
            if global.wire == nil
                print("ERROR: I2C wire_scan failed - cannot initialize")
                return
            end
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

    def onoff(level, index)
        var bit
        if global.nombre == 2
            if index == 0  # led1
                bit = 0
            else           # led4
                bit = 5
            end
        else
            bit = 7   # led2
        end
        if level == 1
            global.io = global.io & ~(1 << bit)  # Set bit to 0
        else
            global.io = global.io | (1 << bit)   # Set bit to 1
        end
        self.write_pins(global.io)
    end

    def toggle_bit(bit)        
        global.io = global.io ^ (1 << bit)
        global.io = global.io | 0x0E  # P1, P2, P3 à 1
#        print("toggle bit: " + str(bit) + " state: " + string.hex(global.io))
        self.write_pins(global.io)
    end

    def every_250ms()
        var payload, topic,buffer
        if global.wire == nil return end

        self.input_state = self.read_pins()

#        print(self.input_state)

        # edge up detection left button
        if ((self.input_state & 0x02) == 0x02) && ((self.last_input_state & 0x02) == 0x00 && self.left_pressed == false)  # P1 button pressed
#            print("P1 pressed")
            self.left_pressed = true
            self.toggle_bit(0)    
            global.setups[0]['onoff'] = global.setups[0]['onoff'] == 1 ? 0 : 1
            buffer = json.dump(global.setups[0])
            topic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.devices[0])      # Toggle LED1 on P0
            payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}', 
                    global.esp_device, global.devices[0], buffer)
            mqtt.publish(topic, payload, true)
            global.aerotherme.every_minute()  # Update the state immediately
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
            self.toggle_bit(7)     
            global.setups[0]['onoff'] = global.setups[0]['onoff'] == 1 ? 0 : 1
            buffer = json.dump(global.setups[0])
            topic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.devices[0])      # Toggle LED1 on P0
            payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}', 
                    global.esp_device, global.devices[0], buffer)
            mqtt.publish(topic, payload, true)
            global.aerotherme.every_minute()  # Update the state immediately
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
            self.toggle_bit(5)       
            global.setups[1]['onoff'] = global.setups[1]['onoff'] == 1 ? 0 : 1
            buffer = json.dump(global.setups[1])
            topic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.devices[1])      # Toggle LED4 on P5
            payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}', 
                    global.esp_device, global.devices[1], buffer)
            mqtt.publish(topic, payload, true)
            global.aerotherme.every_minute()  # Update the state immediately
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
global.pcf = pcf  # Add this line to make pcf accessible globally
tasmota.add_driver(pcf)
