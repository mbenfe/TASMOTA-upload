# layout mezzanine pcf8574a:
# P0: Led1 = bit 0
# P1: left button = bit 1
# P2: middle button = bit 2
# P3: right button = bit 3
# P4: Led5 = bit 4
# P5: Led4 = bit 5
# P6: Led3 = bit 6
# P7: Led2 = bit 7
#
# P1 = system on off default state is off, when pressed toogle Led1 P0 bit 0 if on then all other led take their state, if off all other led off
# P2  = heat power, default state is 1, state can be 1 or 2 for 1 led 2 = on for 2 led 2=off and led 3 = on
# P3 = fan speed, default state = 1,state can be 1,2 or 3. when 1 led 4 = on and led 5 = off, when 2 led 4 = off and led 5 = on when 3 led 4 and 5 are on


#layout relay pcf8574a:
# P0: relay_onoff
# P1: relay_heatpower1
# P2: relay_heatpower2
# P3: relay_fanspeed1
# P4: relay_fanspeed2   
# P5: relay_fanspeed3
#the way it works:
# power on relay is 1, power off relay is 0
# heatpower 1 : relay_heatpower1 = 1 and relay_heatpower2 = 0
# heatpowwer 2 : relay_heatpower1 = 1  and relay_heatpower2 = 1  
# fanspeed 1 : relay_fanspeed1 = 1 and relay_fanspeed2 = 0 and relay_fanspeed3 = 0
# fanspeed 2 : relay_fanspeed1 = 0 and relay_fanspeed2 = 1 and relay_fanspeed3 = 0
# fanspeed 3 : relay_fanspeed1 = 0 and relay_fanspeed2 = 0 and relay_fanspeed3 = 1

import string
import global

class PCF8574A
    var I2C_button_led_addr, I2C_relay_addr
    var state,last_input_state,input_state
    var left_pressed, middle_pressed, right_pressed

    def init()
        var list_devices
        print("init io driver...")
        self.I2C_button_led_addr = 0x3F
        if global.wire == nil
            global.wire = tasmota.wire_scan(self.I2C_button_led_addr)
            list_devices = global.wire.scan()
            print("Wire devices found: " + str(list_devices))
            if (list_devices.find(0x3F)== nil)
                print("PCF8574A buttons/leds not found")
            else
                print("PCF8574A buttons/leds found!")
            end
            if (list_devices.find(0x38)== nil)
                print("PCF8574A relays not found")
            else
                print("PCF8574A relays found!")
            end
        end
        
        # No need to initialize these here since they come from setup.json via frico_driver
        # global.setup['onoff'], global.setup['fanspeed'], global.setup['heatpower'] are loaded in frico_driver
        
        global.io = 0xFF  # All high = inputs, all LEDs off
        self.last_input_state = 0xFF
        self.input_state = 0xFF
        self.write_pins(global.io)
        self.left_pressed = false
        self.middle_pressed = false 
        self.right_pressed = false
        print("io driver initialized")
    end

    def write_pins(value)
        if global.wire != nil
            global.wire._begin_transmission(self.I2C_button_led_addr)
            global.wire._write(value)
            global.wire._end_transmission()
        end
    end

    def read_pins()
        var data
        if global.wire != nil
            data = global.wire.read(self.I2C_button_led_addr, global.io, 1)
            return (data != nil ) ? data : 0xF1
        end
        return 0xFF
    end

    def update_onoff_led()
        var bit

        bit = 0   # led1

        if global.setup['onoff'] == 1
            global.io = global.io & ~(1 << bit)  # Set bit to 0
        else
            global.io = global.io | (1 << bit)   # Set bit to 1
        end
        self.write_pins(global.io)
    end

    def update_heat_power_leds()
        # Safety check for setup
        if global.setup == nil || global.setup.find('onoff') == nil || global.setup.find('heatpower') == nil
            return
        end
        
        # Only update if system is on
        if global.setup['onoff'] == 1
            if global.setup['heatpower'] == 1
                # LED2 on, LED3 off
                global.io = global.io & ~(1 << 7)  # LED2 on (bit 7 = 0)
                global.io = global.io | (1 << 6)   # LED3 off (bit 6 = 1)
            else  # heatpower == 2
                # LED2 off, LED3 on
                global.io = global.io | (1 << 7)   # LED2 off (bit 7 = 1)
                global.io = global.io & ~(1 << 6)  # LED3 on (bit 6 = 0)
            end
        else
            # System OFF - turn off both heat LEDs
            global.io = global.io | (1 << 7)   # LED2 off (bit 7 = 1)
            global.io = global.io | (1 << 6)   # LED3 off (bit 6 = 1)
        end
        self.write_pins(global.io)
    end

    def update_fan_speed_leds()
      
        # Only update if system is on
        if global.setup['onoff'] == 1
            if global.setup['fanspeed'] == 1
                # LED4 on, LED5 off
                global.io = global.io & ~(1 << 5)  # LED4 on (bit 5 = 0)
                global.io = global.io | (1 << 4)   # LED5 off (bit 4 = 1)
            elif global.setup['fanspeed'] == 2
                # LED4 off, LED5 on
                global.io = global.io | (1 << 5)   # LED4 off (bit 5 = 1)
                global.io = global.io & ~(1 << 4)  # LED5 on (bit 4 = 0)
            else  # fanspeed == 3
                # LED4 on, LED5 on
                global.io = global.io & ~(1 << 5)  # LED4 on (bit 5 = 0)
                global.io = global.io & ~(1 << 4)  # LED5 on (bit 4 = 0)
            end
        else
            # System OFF - turn off both fan LEDs
            global.io = global.io | (1 << 5)   # LED4 off (bit 5 = 1)
            global.io = global.io | (1 << 4)   # LED5 off (bit 4 = 1)
        end
        self.write_pins(global.io)
    end

    def every_250ms()
        var detect_pressed = false
        var payload, topic, buffer
        if global.wire == nil return end

        self.input_state = self.read_pins()

        # P1 button - System ON/OFF
        if ((self.input_state & 0x02) == 0x02) && ((self.last_input_state & 0x02) == 0x00 && self.left_pressed == false)
            self.left_pressed = true
            # Toggle system on/off state
            global.setup['onoff'] = global.setup['onoff'] == 1 ? 0 : 1
            
            if global.setup['onoff'] == 1
                # System ON - LED1 on, other LEDs take their state
                global.io = global.io & ~(1 << 0)  # LED1 on (bit 0 = 0)
                # Set other LEDs based on current states
                self.update_heat_power_leds()
                self.update_fan_speed_leds()
            else
                # System OFF - all LEDs off
                global.io = global.io | 0xF0  # Turn off all LEDs (bits 4,5,6,7 = 1)
                global.io = global.io | (1 << 0)   # LED1 off (bit 0 = 1)
            end
            global.io = global.io | 0x0E  # Keep buttons high (P1, P2, P3)
            self.write_pins(global.io)
        end
        
        # P1 button release
        if ((self.input_state & 0x02) == 0x00) && ((self.last_input_state & 0x02) == 0x02 && self.left_pressed == true)
            self.left_pressed = false
            detect_pressed = true
        end

        # P2 button - Heat power (only if system is on)
        if ((self.input_state & 0x04) == 0x04) && ((self.last_input_state & 0x04) == 0x00 && self.middle_pressed == false)
            self.middle_pressed = true
            if global.setup['onoff'] == 1  # Only if system is on
                global.setup['heatpower'] = global.setup['heatpower'] == 1 ? 2 : 1
                self.update_heat_power_leds()
                global.io = global.io | 0x0E  # Keep buttons high
                self.write_pins(global.io)
            end
        end
        
        # P2 button release
        if ((self.input_state & 0x04) == 0x00) && ((self.last_input_state & 0x04) == 0x04 && self.middle_pressed == true)
            self.middle_pressed = false

            if global.setup['onoff'] == 1  # Only if system is on
                detect_pressed = true
            end
        end

        # P3 button - Fan speed (only if system is on)
        if ((self.input_state & 0x08) == 0x08) && ((self.last_input_state & 0x08) == 0x00 && self.right_pressed == false)
            self.right_pressed = true
            if global.setup['onoff'] == 1  # Only if system is on
                global.setup['fanspeed'] = global.setup['fanspeed'] + 1
                if global.setup['fanspeed'] > 3
                    global.setup['fanspeed'] = 1
                end
                self.update_fan_speed_leds()
                global.io = global.io | 0x0E  # Keep buttons high
                self.write_pins(global.io)
            end
        end
        
        # P3 button release
        if ((self.input_state & 0x08) == 0x00) && ((self.last_input_state & 0x08) == 0x08 && self.right_pressed == true)
            self.right_pressed = false
            if global.setup['onoff'] == 1  # Only if system is on
                detect_pressed = true
            end
        end

        self.last_input_state = self.input_state
        if detect_pressed == true
            payload = string.format('{"Device":"%s","Name":"setup_%s","TYPE":"SETUP","DATA":%s}', 
                global.device, global.device, json.dump(global.setup))
            topic = string.format("gw/%s/%s/%s/set/SETUP", global.client, global.ville, global.device)
            mqtt.publish(topic, payload, true)
        end
    end
    
end

var pcf = PCF8574A()
global.pcf = pcf  # Add this line to make pcf accessible globally
tasmota.add_driver(pcf)