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
    var CMD_GET 
    var CMD_GO 
    var CMD_WRITE 
    var CMD_ERASE 

    var timeout

    def init()
        # initialized in cn7_driver.be
        self.ACK = 0x79
        self.NACK = 0x1F
        self.CMD_GET = 0x00
        self.CMD_GO = 0x21
        self.CMD_WRITE = 0x31
        self.CMD_ERASE = 0x43
        self.timeout = 1000  # 1 second timeout
    end

    # def mydelay(timeout)
    #     var due = tasmota.millis() + timeout
    #     while !tasmota.time_reached(due) end
    # end
    
    def enter_bootloader()
        # Set BOOT0=HIGH, pulse RESET
        gpio.digital_write(global.rst_pin, 0)   # RESET = LOW
        tasmota.delay(10)
        gpio.digital_write(global.bsl_pin, 1)  # BOOT0 = HIGH
        tasmota.delay(10)
        gpio.digital_write(global.rst_pin, 1)   # RESET = HIGH
        tasmota.delay(100)
        mqttprint("Entered bootloader mode")
    end
    
    def exit_bootloader()
        # Set BOOT0=LOW, pulse RESET
        gpio.digital_write(global.bsl_pin, 0)  # BOOT0 = LOW
        tasmota.delay(10)
        gpio.digital_write(global.rst_pin, 0)   # RESET = LOW
        tasmota.delay(10)
        gpio.digital_write(global.rst_pin, 1)   # RESET = HIGH
        tasmota.delay(100)
        mqttprint("Exited bootloader mode")
    end

    def wait_ack(timeout)
        var due = tasmota.millis() + timeout
        while !tasmota.time_reached(due)
            if global.ser.available()
                var b = global.ser.read()
                # Remove null bytes like in flasher.be
                while size(b) > 0 && b[0] == 0
                    b = b[1..]
                end
                global.ser.flush()
                return b.tohex()
            end
            tasmota.delay(1)        
        end
        return '00'  # timeout
    end
    
    def send_sync()
        # Send 0x7F sync byte
        global.ser.write(0x7F)
        var ret = self.wait_ack(50)
        
        if ret == '79'  # ACK received
            mqttprint("Sync successful")
            return true
        else
            mqttprint("Sync failed - response: " + ret)
            return false
        end
    end    

    def send_command(cmd)
        # Send command + complement
        var packet = bytes()
        packet.add(cmd)
        packet.add(cmd ^ 0xFF)  # Complement
        global.ser.write(packet)
        
        # Use wait_ack like send_sync
        var ret = self.wait_ack(100)
        
        if ret == '79'  # ACK received
            return true
        elif ret == '1F'  # NACK received
            mqttprint("Command NACK received")
            return false
        else
            mqttprint("Command timeout - response: " + ret)
            return false
        end
    end    

    def write_memory(addr, data)
        # STM32 write memory command implementation
        # Send Write Memory command (0x31)
#debug
return

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
            if response && size(response) > 0 && response[0] == self.ACK
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
        data_packet.add(size(data) - 1)  # N-1 format
        checksum = size(data) - 1

        for i:0..size(data)-1
            data_packet.add(data[i])
            checksum ^= data[i]
        end
        data_packet.add(checksum)
        
        global.ser.write(data_packet)
        
        # Wait for final ACK
        start_time = tasmota.millis()
        while (tasmota.millis() - start_time) < self.timeout
            var response = global.ser.read()
            if response && size(response) > 0
                return response[0] == self.ACK
            end
            tasmota.yield()
        end
        
        return false
    end
    
    def parse_hex_line(line)
        # Parse Intel HEX format line: :LLAAAATT[DD...]CC

        if size(line) < 11 || line[0] != ':'
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
            if size(line) < (9 + data_len * 2 + 2)
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

    def strip_line(s)
        var start = 0
        var last = size(s) - 1
        
        # return s

        # Remove leading whitespace
        while start < size(s) && (s[start] == ' ' || s[start] == '\t' || s[start] == '\r' || s[start] == '\n')
            start += 1
        end
        
        # Remove trailing whitespace  
        while last >= start && (s[last] == ' ' || s[last] == '\t' || s[last] == '\r' || s[last] == '\n')
            last -= 1
        end
        
        if start > last
            return ""
        end
        
        return s[start..last]
    end
    
    def flash_hex_file(filename)
        # Initialize UART
        global.ser = serial(global.uart_rx, global.uart_tx, 115200, serial.SERIAL_8E1)

        # Main flashing logic
        mqttprint("Starting flash of: " + filename)
        
        global.ser.flush()

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
        while size(line) > 0 && line != nil
           tasmota.yield()

            if size(line) == 0
                print("line size = 0")
                continue
            end
           line = self.strip_line(line)
            
            line_count += 1
            var parsed = self.parse_hex_line(line)
            
            if parsed == nil
                file.close()
                self.exit_bootloader()
                tasmota.resp_cmnd("Parse error at line " + str(line_count))
                return
            end
            
            if(parsed["type"]!=nil)
                if parsed["type"] == 0  # Data record
                    # var full_addr = base_address + parsed["addr"]
                    # if !self.write_memory(full_addr, parsed["data"])
                    #     file.close()
                    #     self.exit_bootloader()
                    #     tasmota.resp_cmnd("Flash failed at address: 0x" + string.format("%08X", full_addr))
                    #     return
                    # end
                    # bytes_written += size(parsed["data"])
                    
                    # Progress indicator every 1KB
                    # if bytes_written % 1024 == 0
                    #     mqttprint("Written: " + str(bytes_written) + " bytes")
                    # end
                    
                elif parsed["type"] == 1  # End of file
                    break
                elif parsed["type"] == 4  # Extended linear address
                    # Handle extended addressing if needed
                    continue
                end
            end
            tasmota.yield()
            line = file.readline()
        end

        print(str(line_count)+ ' lines processed')

        file.close()
        self.exit_bootloader()
        
        var result = "Flash completed: " + str(bytes_written) + " bytes written"
        mqttprint(result)
        tasmota.resp_cmnd(result)
        
        # get  UART back
        global.ser = serial(global.uart_rx, global.uart_tx, 115200, serial.SERIAL_8N1)
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

    
    # Start flashing in a timer to avoid blocking
    tasmota.set_timer(100, /-> global.flashex.flash_hex_file(payload))

    tasmota.resp_cmnd("Flash started for: " + payload)
end

var flashex = FLASHEX()
global.flashex = flashex
tasmota.add_driver(flashex)
tasmota.add_cmd('flashex', flashex_cmd)