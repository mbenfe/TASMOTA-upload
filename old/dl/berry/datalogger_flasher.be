#---------------------------------#
# VERSION 1.0                     #
#---------------------------------#

class datalogger_flasher 

    #################################################################################
    # Flashing from bin files
    #################################################################################
    var filename          # filename of hex file
    var f                 # file object
    var file_bin          # checkhex object
    var flasher           # low-level flasher object (stm32_flasher instance)
    var ser                # serial object
    var debug                   # verbose logs?
 
    var rx    # rx = GPI16
    var tx    # tx = GPI17
    var rst   # rst = GPIO2
    var bsl   # bsl = GPIO13
 
    def wait_ack(timeout)
        var due = tasmota.millis() + timeout
        while !tasmota.time_reached(due)
           if self.ser.available()
              var b = self.ser.read()
              while size(b) > 0 && b[0] == 0
                  b = b[1..]
              end
                return b.tohex()
            end
            tasmota.delay(1)        # check every 5ms
         end
         return '00'
     end

    def initialisation()
        import gpio  
 
        var ret
        self.rx = 16   # rx = GPI016
        self.tx = 17   # tx = GPIO17
        self.rst = 2  # rst = GPIO2
        self.bsl = 13  # bsl = GPIO13
 
        self.ser = serial(rx,tx,115200,serial.SERIAL_8E1)
        self.ser.flush()
         # reset STM32
         gpio.pin_mode(self.rst,gpio.OUTPUT)
         gpio.pin_mode(self.bsl,gpio.OUTPUT)
        #------------- INTIALISE BOOT -------------------------#
        print('FLASH:initialise boot sequence')
        gpio.digital_write(rst, 0)    # trigger BSL
        tasmota.delay(10)               # wait 10ms
        gpio.digital_write(bsl, 1)    # trigger BSL
        tasmota.delay(10)               # wait 10ms
        gpio.digital_write(rst, 1)    # trigger BSL
        tasmota.delay(100)               # wait 10ms

        self.ser.write(0x7F)
        ret = self.wait_ack(50)
        print("FLASH:ret=", ret)
    end
 
    def terminate()
        print('reset')
        gpio.digital_write(self.bsl, 0)    # reset bsl
        tasmota.delay(10)
        gpio.digital_write(self.rst, 0)    # trigger Reset
        tasmota.delay(10)
        gpio.digital_write(self.rst, 1)    # trigger Reset
    end

   #------------------------------------------------------------------------------------#
    #                                   CONVERSION FICHIER                               #
    #------------------------------------------------------------------------------------#
    def write_block(fichier,addresse,token)
        import string
        var ret
        var payload1,payload2,payload3
        var message
        var mycrc = 0
        var bAddresse
   
        bAddresse = bytes(string.format('%08X',addresse))
        mycrc = 0
        mycrc ^= bAddresse[0]
        mycrc ^= bAddresse[1]
        mycrc ^= bAddresse[2]
        mycrc ^= bAddresse[3]
        payload2 =bAddresse + bytes(string.format('%02X',mycrc))
        fichier.write(payload2)
  
        mycrc = 0
        for i: 1..size(token)
          mycrc ^= token[i-1]
        end
        mycrc ^= 0xFF
        mycrc ^= size(token)
        payload3 = bytes(string.format('%02s%sFF%02X',string.hex(size(token)),token.tohex(),mycrc))
        fichier.write(payload3)
    end

    def convert(filename)
        var file_convname 
        var file_conv
        var file
        var BLOCK = 252
        var numB, reste
        var token
        if type(filename) != 'string'   raise "erreur", "nom fichier non valide" end
        file_convname = filename+'c'
        file_conv = open(file_convname, "wb")    
        file = open(filename,"rb")
        numB = file.size()/BLOCK
        reste = file.size() - numB*BLOCK
        for i: 1 .. numB
            token = file.readbytes(BLOCK)
            self.write_block(file_conv,0x08000000+((i-1)*BLOCK),token)
        end
        token = file.readbytes(reste)
        self.write_block(file_conv,0x08000000+(numB*BLOCK),token)
        file.close()
        file_conv.close()
        print('conversion done')
    end

    #------------------------------------------------------------------------------------#
    #                                   ECRITURE FICHIER                                 #
    #------------------------------------------------------------------------------------#
    def flash(filename)
        var cfile = filename+'c'
        var file
        var index = 0
        var token
        var BLOCK = 252
        var ret
        self.initialisation()
        file = open(cfile,"rb")
        while index < file.size()
            self.ser.write(bytes('31CE'))
            ret = self.wait_ack(500)     # malek
            if ret != '79'
              print('resp:',ret)
              gpio.digital_write(self.bsl, 0)    # reset bsl
              raise 'erreur envoi 1','NACK'
           end
              
            token = file.readbytes(5)
            self.ser.write(token)
            ret = self.wait_ack(50)
            if ret != '79'
                print('resp:',ret)
                gpio.digital_write(self.bsl, 0)    # reset bsl
                raise 'erreur envoi 2','NACK'
            end   
            index += size(token)

            token = file.readbytes(BLOCK+3)
            self.ser.write(token)
            ret = self.wait_ack(50)
            if ret != '79'
                print('resp:',ret)
                gpio.digital_write(self.bsl, 0)    # reset bsl
                raise 'erreur envoi 3','NACK'
            end   
            index += size(token)
        end
        file.close()
        print('dernier token:',size(token))
        print('index:',index)
        self.terminate()
        print('flashing done')
    end

    #------------------------------------------------------------------------------------#
    #                                   EFFACEMENT                                       #
    #------------------------------------------------------------------------------------#
    def erase()
        self.initialisation()
        print('ERASE:initialisation hardware')
        var ret
        # start erase
         self.ser.write(bytes('44BB'))
         ret = self.wait_ack(50) 
         if ret != '79'
            print('resp:',ret)
            gpio.digital_write(self.bsl, 0)    # reset bsl
            raise 'erreur erase 1','NACK'
        end   
     print("ERASE:start:", ret)
         self.ser.write(bytes('FFFF00'))
         tasmota.delay(20000)
        ret = self.wait_ack(500) 
         if ret != '79'
            print('resp:',ret)
            gpio.digital_write(self.bsl, 0)    # reset bsl
            raise 'erreur erase 2','NACK'
        end   
     print("ERASE:end:", ret)
     self.terminate()
    end
    #------------------------------------------------------------------------------------#
    #                                   UNPROTECT                                        #
    #------------------------------------------------------------------------------------#
    def unprotect()
        self.initialisation()
        print('ERASE:initialisation hardware')
        var ret
        # unprotect
        self.ser.write(bytes('738C'))
        ret = self.wait_ack(50) 
        if ret != '79'
           print('resp:',ret)
           gpio.digital_write(self.bsl, 0)    # reset bsl
           raise 'erreur unprotect 1','NACK'
       end   
       print('ack:',ret)
       ret = self.wait_ack(500) 
       if ret != '79'
          print('resp:',ret)
          gpio.digital_write(self.bsl, 0)    # reset bsl
          raise 'erreur unprotect 2','NACK'
      end   
      print('flash unprotected')
    end
 
  end
 
  return datalogger_flasher()
