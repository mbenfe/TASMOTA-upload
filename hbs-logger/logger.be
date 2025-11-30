import global

class Logger

    var ser1,ser2
    var rx1,rx2
    var tx1,tx2

    def init()
        self.rx1 = 21
        self.tx1 = 9
        gpio.pin_mode(self.rx1,gpio.INPUT)
        gpio.pin_mode(self.tx1,gpio.OUTPUT)
       self.ser1 = serial(self.rx1,self.tx1,115200,serial.SERIAL_8N1)
       self.ser1.flush()

        self.rx2 = 6
        self.tx2 = 20
        gpio.pin_mode(self.rx2,gpio.INPUT)
        gpio.pin_mode(self.tx2,gpio.OUTPUT)
        self.ser2 = serial(self.rx2,self.tx2,115200,serial.SERIAL_8N1)
        self.ser2.flush()
    end                                                     

    def fast_loop1()
        self.read_uart1(1)
    end
    
    def fast_loop2()
        self.read_uart2(1)
    end


    def read_uart1(timeout)
        if self.ser1.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = self.ser1.read()
            self.ser1.flush()
            
            # Convert each byte to decimal
            var output = ""
            for i:0..buffer.size()-1
                if i > 0
                    output += " "  # Space separator
                end
                output += str(buffer[i])  # Decimal value
            end
            
            print("M:", output)
        end
    end

    def read_uart2(timeout)
        if self.ser2.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = self.ser2.read()
            self.ser2.flush()
            
            # Convert each byte to decimal
            var output = ""
            for i:0..buffer.size()-1
                if i > 0
                    output += " "  # Space separator
                end
                output += str(buffer[i])  # Decimal value
            end
            
            print("S:", output)
        end
    end


end

var logger = Logger()

tasmota.add_driver(logger)
tasmota.add_fast_loop(/-> logger.fast_loop1())
tasmota.add_fast_loop(/-> logger.fast_loop2())
