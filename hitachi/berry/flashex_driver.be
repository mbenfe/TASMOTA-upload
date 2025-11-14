# File: flashex_driver.be
import mqtt
import string
import json
import global
import gpio

# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, texte, true)
    return true
end

class FLASHEX
    var ACK
    var NACK
    var timeout

    def init()
        # initialized in cn7_driver.be
        self.ACK = 0x79
        self.NACK = 0x1F
        self.timeout = 1000  # 1 second timeout
    end

    def mydelay(ms)
        var start = tasmota.millis()
        while (tasmota.millis() - start) < ms
            tasmota.yield()
        end
    end
    
    def enter_bootloader()
        # Set BOOT0=HIGH, pulse RESET
        gpio.digital_write(global.bsl_pin, 1)  # BOOT0 = HIGH
        gpio.digital_write(global.rst_pin, 0)   # RESET = LOW
        self.mydelay(10)
        gpio.digital_write(global.rst_pin, 1)   # RESET = HIGH
        self.mydelay(100)
        mqttprint("Entered bootloader mode")
    end
    
    def exit_bootloader()
        # Set BOOT0=LOW, pulse RESET
        gpio.digital_write(global.bsl_pin, 0)  # BOOT0 = LOW
        gpio.digital_write(global.rst_pin, 0)   # RESET = LOW
        self.mydelay(10)
        gpio.digital_write(global.rst_pin, 1)   # RESET = HIGH
        self.mydelay(100)
        mqttprint("Exited bootloader mode")
    end
    
    def send_sync()
        # Send 0x7F sync byte
        var sync_byte = bytes()
        sync_byte.add(0x7F)
        global.ser.write(sync_byte)
        
        var start_time = tasmota.millis()
        while (tasmota.millis() - start_time) < self.timeout
            var response = global.ser.read()
            if response && response.size() > 0
                if response[0] == self.ACK
                    mqttprint("Sync successful")
                    return true
                end
            end
            tasmota.yield()
        end
        mqttprint("Sync failed - no response")
        return false
    end
    
    def send_command(cmd)
        # Send command + complement + wait ACK
        var packet = bytes()
        packet.add(cmd)
        packet.add(cmd ^ 0xFF)  # Complement
        global.ser.write(packet)
        
        var start_time = tasmota.millis()
        while (tasmota.millis() - start_time) < self.timeout
            var response = global.ser.read()
            if response && response.size() > 0
                if response[0] == self.ACK
                    return true
                elif response[0] == self.NACK
                    mqttprint("Command NACK received")
                    return false
                end
            end
            tasmota.yield()
        end
        mqttprint("Command timeout")
        return false
    end
    
    def write_memory(addr, data)
        # STM32 write memory command implementation
        # Send Write Memory command (0x31)
        if !self.send_command(0x31)
            return false
        end
        
        # Send address (4 bytes + checksum)
        var addr_packet = bytes()
        addr_packet.add((addr >> 24) & 0xFF)
        addr_packet.add((addr >> 16) & 0xFF)
        addr_packet.add((addr >> 8) & 0xFF)
        addr_packet.add(addr & 0xFF)
        
        var checksum = 0
        for i:0..3
            checksum ^= addr_packet[i]
        end
        addr_packet.add(checksum)
        
        global.ser.write(addr_packet)
        
        # Wait for ACK
        var start_time = tasmota.millis()
        var ack_received = false
        while (tasmota.millis() - start_time) < self.timeout
            var response = global.ser.read()
            if response && response.size() > 0 && response[0] == self.ACK
                ack_received = true
                break
            end
            tasmota.yield()
        end
        
        if !ack_received
            mqttprint("Address ACK timeout")
            return false
        end
        
        # Send data length + data + checksum
        var data_packet = bytes()
        data_packet.add(data.size() - 1)  # N-1 format
        checksum = data.size() - 1
        
        for i:0..data.size()-1
            data_packet.add(data[i])
            checksum ^= data[i]
        end
        data_packet.add(checksum)
        
        global.ser.write(data_packet)
        
        # Wait for final ACK
        start_time = tasmota.millis()
        while (tasmota.millis() - start_time) < self.timeout
            var response = global.ser.read()
            if response && response.size() > 0
                return response[0] == self.ACK
            end
            tasmota.yield()
        end
        
        return false
    end
    
    def parse_hex_line(line)
        # Parse Intel HEX format line: :LLAAAATT[DD...]CC
        if line.size() < 11 || line[0] != ':'
            return nil
        end
        
        # Extract fields
        var data_len_str = line[1..2]
        var addr_str = line[3..6]
        var record_type_str = line[7..8]
        
        var data_len = 0
        var address = 0
        var record_type = 0
        
        # Convert hex strings to integers
        try
            data_len = int("0x" + data_len_str)
            address = int("0x" + addr_str)
            record_type = int("0x" + record_type_str)
        except .. as e
            mqttprint("HEX parse error: " + str(e))
            return nil
        end
        
        if record_type == 0  # Data record
            if line.size() < (9 + data_len * 2 + 2)
                return nil
            end
            
            var data = bytes()
            for i:0..data_len-1
                var byte_pos = 9 + i * 2
                var byte_str = line[byte_pos..byte_pos+1]
                try
                    data.add(int("0x" + byte_str))
                except .. as e
                    mqttprint("Data parse error: " + str(e))
                    return nil
                end
            end
            
            return {"addr": address, "data": data, "type": record_type}
        elif record_type == 1  # End of file record
            return {"type": record_type}
        elif record_type == 4  # Extended linear address
            return {"type": record_type}
        end
        
        return nil
    end
    
    def flash_hex_file(filename)
        # Main flashing logic
        mqttprint("Starting flash of: " + filename)
        
        # Enter bootloader
        self.enter_bootloader()
        
        # Send sync
        if !self.send_sync()
            self.exit_bootloader()
            tasmota.resp_cmnd("Sync failed")
            return
        end
        
        # Open HEX file
        var file = open(filename, "rt")
        if !file
            self.exit_bootloader()
            tasmota.resp_cmnd("File not found: " + filename)
            return
        end
        
        var line_count = 0
        var bytes_written = 0
        var base_address = 0x08000000  # STM32 flash start address
        
        # Process each line
        var line = file.readline()
        while line 
            line = string.strip(line)
            if line.size() == 0
                continue
            end
            
            line_count += 1
            var parsed = self.parse_hex_line(line)
            
            if parsed == nil
                file.close()
                self.exit_bootloader()
                tasmota.resp_cmnd("Parse error at line " + str(line_count))
                return
            end
            
            if parsed["type"] == 0  # Data record
                var full_addr = base_address + parsed["addr"]
                if !self.write_memory(full_addr, parsed["data"])
                    file.close()
                    self.exit_bootloader()
                    tasmota.resp_cmnd("Flash failed at address: 0x" + string.format("%08X", full_addr))
                    return
                end
                bytes_written += parsed["data"].size()
                
                # Progress indicator every 1KB
                if bytes_written % 1024 == 0
                    mqttprint("Written: " + str(bytes_written) + " bytes")
                end
                
            elif parsed["type"] == 1  # End of file
                break
            elif parsed["type"] == 4  # Extended linear address
                # Handle extended addressing if needed
                continue
            end
            line = file.readline()
        end
        
        file.close()
        self.exit_bootloader()
        
        var result = "Flash completed: " + str(bytes_written) + " bytes written"
        mqttprint(result)
        tasmota.resp_cmnd(result)
    end
end

# Command handler
def flashex_cmd(cmd, idx, payload, payload_json)
    if payload == ''
        mqttprint("Error: No file specified")
        tasmota.resp_cmnd("Error: No file specified")
        return
    end

    if !path.exists(payload)
        mqttprint("Error: File not found")
        tasmota.resp_cmnd("Error: File not found")
        return
    end

    # Initialize UART
    global.ser = serial(global.uart_rx, global.uart_tx, 115200, serial.SERIAL_8N1)
    
    # Start flashing in a timer to avoid blocking
    tasmota.set_timer(100, /-> global.flashex.flash_hex_file(payload))

    tasmota.resp_cmnd("Flash started for: " + payload)
end

var flashex = FLASHEX()
global.flashex = flashex
tasmota.add_driver(flashex)
tasmota.add_cmd('flashex', flashex_cmd)