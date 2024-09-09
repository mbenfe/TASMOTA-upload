#------------------------------------------------#
# DUALFLASHER.BE for VSNX 1.0                    #
#------------------------------------------------#

import strict
import math
import string

class dualflasher 

    #################################################################################
    # Flashing from bin files
    #################################################################################
    var filename          # filename of hex file
    var f                 # file object
    var file_bin          
    var flasher           # low-level flasher object (stm32_flasher instance)
    var ser                # serial object
    var debug                   # verbose logs?
 
    var rx_flash    
    var tx_flash 
    var rst_in   
    var bsl_in  
    var rst_out  
    var bsl_out
    var statistic
 
    def wait_ack(timeout)
        var due = tasmota.millis() + timeout
        while !tasmota.time_reached(due)
           if self.ser.available()
              var b = self.ser.read()
              while size(b) > 0 && b[0] == 0
                  b = b[1..]
              end
                self.ser.flush()
                return b.tohex()
            end
            tasmota.delay(1)        
         end
         return '00'
     end


    def initialisation(rank,stm32)
        import gpio  

        self.rx_flash=36    
        self.tx_flash=1    
        self.rst_in=19   
        self.bsl_in=21   
        self.rst_out=33   
        self.bsl_out=32   
        self.statistic=25
    
 
        var ret
        var rst
        var bsl
        var disable
        print('FLASHER:INITIALISATION',str(rank),':....wait 30 seconds')
        gpio.pin_mode(self.rx_flash,gpio.INPUT)
        gpio.pin_mode(self.tx_flash,gpio.OUTPUT)

        self.ser = serial(self.rx_flash,self.tx_flash,115200,serial.SERIAL_8E1)
        self.ser.flush()
         # reset STM32
         gpio.pin_mode(self.rst_in,gpio.OUTPUT)
         gpio.pin_mode(self.bsl_in,gpio.OUTPUT)
         gpio.pin_mode(self.rst_out,gpio.OUTPUT)
         gpio.pin_mode(self.bsl_out,gpio.OUTPUT)
         print('FLASHER:INITIALISATION:',str(rank),':stm32 ->',stm32)
         if stm32=='in'
            print('FLASHER:INITIALISATION:',str(rank),':flash RS485 in')
            rst=self.rst_in
            bsl=self.bsl_in
            disable=self.rst_out
         else
            print('FLASHER:INITIALISATION:',str(rank),':flash processor output')
            rst=self.rst_out
            bsl=self.bsl_out
            disable=self.rst_in
         end
        #------------- INTIALISE BOOT -------------------------#
        print('FLASHER:INITIALISATION:',str(rank),':initialise boot sequence')
        gpio.digital_write(disable, 0)    # put second chip open drain
        gpio.digital_write(rst, 0)    # trigger BSL
        tasmota.delay(10)               # wait 10ms
        gpio.digital_write(bsl, 1)    # trigger BSL
        tasmota.delay(10)               # wait 10ms
        gpio.digital_write(rst, 1)    # trigger BSL
        tasmota.delay(100)               # wait 10ms

        self.ser.write(0x7F)
        ret = self.wait_ack(50)
        print('FLASHER:INITIALISATION:',str(rank),':ret='+str(ret))
        if ret != '79'
            print('FLASHER:INITIALISATION:',str(rank),':resp:'+str(ret))
            gpio.digital_write(bsl, 0)    # reset bsl
            gpio.digital_write(disable, 1)    # enable second chip
            raise 'FLASHER:INITIALISATION:',str(rank),':erreur initialisation','NACK'
          end
    end
    #------------------------------------------------------------------------------------#
    #                                   GETINFO                                          #
    #------------------------------------------------------------------------------------#
    def getinfo(stm32) 
        var bsl
        var disable
        var ret
        if stm32=='in'
            bsl=self.bsl_in
            disable=self.rst_out
        else
            bsl=self.bsl_out
            disable=self.rst_in
        end    

        self.ser.write(bytes('01FE'))
        ret = self.wait_ack(100)     # malek
        if str(ret[0]) != '7' || str(ret[1]) != '9'
            gpio.digital_write(bsl, 0)    # reset bsl
            gpio.digital_write(disable, 1)    # enable second chip
            raise 'FLASHER:INFO:erreur envoi 1','NACK'
        else
            print('FLASHER:INFO:Protocol version -> '+str(ret[2])+'.'+str(ret[3]))
        end

        self.ser.write(bytes('02FD'))
        ret = self.wait_ack(100)     # malek
        if str(ret[0]) != '7' || str(ret[1]) != '9'
            gpio.digital_write(bsl, 0)    # reset bsl
            gpio.digital_write(disable, 1)    # enable second chip
            raise 'FLASHER:INFO:erreur envoi 1','NACK'
        else
            print('FLASHER:INFO:Chip ID -> '+ret[4]+ret[5]+ret[6]+ret[7])
        end
        self.ser.write(bytes('738C'))
        ret = self.wait_ack(100)     # malek
    end
 
    #------------------------------------------------------------------------------------#
    #                                   UNPROTTECT                                       #
    #------------------------------------------------------------------------------------#
    def unprotect(stm32) 
        var readbytes
        var disable
        var rst
        var ret
        if stm32=='in'
            rst=self.rst_in
            disable=self.rst_out
        else
            rst=self.rst_out
            disable=self.rst_in
        end    

        self.ser.write(bytes('738C'))
        ret = self.wait_ack(100)     # malek
        gpio.digital_write(rst, 0)  
        tasmota.delay(1) 
        gpio.digital_write(rst, 1)    # enable second chip
        tasmota.delay(1)  
    end
 
    def terminate(stm32)
        var rst
        var bsl
        var disable
        gpio.pin_mode(self.rst_in,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_in,gpio.OUTPUT)
        gpio.pin_mode(self.rst_out,gpio.OUTPUT)
        gpio.pin_mode(self.bsl_out,gpio.OUTPUT)
       if stm32=='in'
            rst=self.rst_in
            bsl=self.bsl_in
            disable=self.rst_out
         else
            rst=self.rst_out
            bsl=self.bsl_out
            disable=self.rst_in
         end
       
        print('FLASHER:TERMINATE:reset')
        gpio.digital_write(disable, 1)    # enable second chip
        tasmota.delay(10)
        gpio.digital_write(bsl, 0)    # reset bsl
        tasmota.delay(10)
        gpio.digital_write(rst, 0)    # trigger Reset
        tasmota.delay(10)
        gpio.digital_write(rst, 1)    # trigger Reset
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
        var tas = tasmota
        var yield = tasmota.yield
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
        try
            for i: 1 .. numB
                token = file.readbytes(BLOCK)
                self.write_block(file_conv,0x08000000+((i-1)*BLOCK),token)
                yield(tas)        # tasmota.yield() -- faster version
            end
            token = file.readbytes(reste)
            self.write_block(file_conv,0x08000000+(numB*BLOCK),token)
        except .. as e, m
            file.close()
            raise e, m      # re-raise
        end
        file.close()
        file_conv.close()
        print('FLASHER:CONVERT:conversion done')
    end

    #------------------------------------------------------------------------------------#
    #                                   ECRITURE FICHIER                                 #
    #------------------------------------------------------------------------------------#
    def flash(filename,stm32)
        var bsl
        var disable
        var tas = tasmota
        var yield = tasmota.yield
        var cfile = filename+'c'
        var file
        var index = 0
        var token
        var BLOCK = 252
        var ret
        if stm32=='in'
            bsl=self.bsl_in
            disable=self.rst_out
         else
            bsl=self.bsl_out
            disable=self.rst_in
         end
        
         self.initialisation(1,stm32)
         self.unprotect(stm32)
         self.initialisation(2,stm32)
         self.getinfo(stm32)
        file = open(cfile,"rb")
        while index < file.size()
            self.ser.write(bytes('31CE'))
            ret = self.wait_ack(100)     # malek
            if ret != '79'
              print('FLASHER:FLASH:resp:'+str(ret))
              gpio.digital_write(bsl, 0)    # reset bsl
              gpio.digital_write(disable, 1)    # enable second chip
              raise 'FLASHER:FLASH:erreur envoi 1','NACK'
            end
              
            token = file.readbytes(5)
            self.ser.write(token)
            ret = self.wait_ack(50)
            if ret != '79'
                print('FLASHER:FLASH:resp:'+str(ret))
                gpio.digital_write(bsl, 0)    # reset bsl
                gpio.digital_write(disable, 1)    # enable second chip
                raise 'FLASHER:FLASH:erreur envoi 2','NACK'
            end   
            index += size(token)

            token = file.readbytes(BLOCK+3)
            self.ser.write(token)
            ret = self.wait_ack(50)
            if ret != '79'
                print('FLASHER:FLASH:resp:'+str(ret))
                gpio.digital_write(bsl, 0)    # reset bsl
                gpio.digital_write(disable, 1)    # enable second chip
                raise 'FLASHER:FLASH:erreur envoi 3','NACK'
            end   
            index += size(token)
            yield(tas)        # tasmota.yield() -- faster version
        end
        file.close()
        print('FLASHER:FLASH:dernier token:',size(token))
        print('FLASHER:FLASH:index:',index)
        self.terminate(stm32)
        print('FLASHER:FLASH:flashing done')
    end

    #------------------------------------------------------------------------------------#
    #                                   EFFACEMENT                                       #
    #------------------------------------------------------------------------------------#
    def erase(stm32)
        var rst
        var bsl
        var ret
        var disable
        if stm32=='in'
            rst=self.rst_in
            bsl=self.bsl_in
            disable=self.rst_out
         else
            rst=self.rst_out
            bsl=self.bsl_out
            disable=self.rst_in
         end

        self.initialisation(stm32)
        print('FLASHER:ERASE:initialisation hardware')
        # start erase
         self.ser.write(bytes('44BB'))
         ret = self.wait_ack(50) 
         if ret != '79'
            print('FLASHER:ERASE:resp:'+str(ret))
            gpio.digital_write(bsl, 0)    # reset bsl
            gpio.digital_write(disable, 1)    # enable second chip
            raise 'FLASHER:ERASE:erreur erase 1','NACK'
        end   
         print("FLASHER:ERASE:start:"+str(ret))
         self.ser.write(bytes('FFFF00'))
         tasmota.delay(20000)
        ret = self.wait_ack(500) 
         if ret != '79'
            print('FLASHER:ERASE:resp:'+str(ret))
            gpio.digital_write(bsl, 0)    # reset bsl
            gpio.digital_write(disable, 1)    # enable second chip
            raise 'FLASHER:ERASE:erreur erase 2','NACK'
        end   
        print("FLASHER:ERASE:end:"+str(ret))
        self.terminate(stm32)
    end

end
return dualflasher()