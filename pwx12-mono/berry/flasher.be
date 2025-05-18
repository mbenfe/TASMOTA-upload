#------------------------------------------------#
# VERSION NEW 2.0                                #
# added tasmote yield for long process           #
# adapter rx et tx selon la carte ligne 49 et 50 #
#------------------------------------------------#

import strict
import math
import string

class flasher

    #################################################################################
    # Flashing from bin files
    #################################################################################
    var filename          # filename of hex file
    var f                 # file object
    var file_bin          
    var flasher           # low-level flasher object (stm32_flasher instance)
    var ser               # serial object
    var debug             # verbose logs?
 
    var rx    
    var tx 
    var rst   
    var bsl  

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

    var ville
    var device

    def mqttprint(texte)
        import mqtt
        var topic = string.format("gw/inter/%s/%s/tele/PRINT", self.ville, self.device)
        mqtt.publish(topic, texte, true)
    end

    def initialisation()
        import gpio  
        import json

        self.rx = 16    
        self.tx = 17    
        self.rst = 2   
        self.bsl = 13    
        self.statistic = 25

        var ret

        var file = open("esp32.cfg", "rt")
        var buffer = file.read()
        file.close()
        var myjson = json.load(buffer)
        self.ville = myjson["ville"]
        self.device = myjson["device"]

        gpio.pin_mode(self.rx, gpio.INPUT)
        gpio.pin_mode(self.tx, gpio.OUTPUT)

        self.ser = serial(rx, tx, 115200, serial.SERIAL_8E1)
        self.ser.flush()
        # reset STM32
        gpio.pin_mode(self.rst, gpio.OUTPUT)
        gpio.pin_mode(self.bsl, gpio.OUTPUT)

        #------------- INTIALISE BOOT -------------------------#
        mqttprint('FLASH:initialise boot sequence')
        gpio.digital_write(self.rst, 0)    # trigger BSL
        tasmota.delay(10)                  # wait 10ms
        gpio.digital_write(self.bsl, 1)    # trigger BSL
        tasmota.delay(10)                  # wait 10ms
        gpio.digital_write(self.rst, 1)    # trigger BSL
        tasmota.delay(100)                 # wait 10ms

        self.ser.write(0x7F)
        ret = self.wait_ack(50)
        print("FLASH:ret=" + str(ret))
        if ret != '79'
            print('resp:' + str(ret))
            gpio.digital_write(bsl, 0)    # reset bsl
            raise 'erreur initialisation', 'NACK'
        end
    end

    def terminate()
        mqttprint('reset')
        gpio.digital_write(self.bsl, 0)    # reset bsl
        tasmota.delay(10)
        gpio.digital_write(self.rst, 0)    # trigger Reset
        tasmota.delay(10)
        gpio.digital_write(self.rst, 1)    # trigger Reset
    end

    #------------------------------------------------------------------------------------#
    #                                   CONVERSION FICHIER                               #
    #------------------------------------------------------------------------------------#
    def write_block(fichier, addresse, token)
        import string
        var ret
        var payload1, payload2, payload3
        var message
        var mycrc = 0
        var bAddresse

        bAddresse = bytes(string.format('%08X', addresse))
        mycrc = 0
        mycrc ^= bAddresse[0]
        mycrc ^= bAddresse[1]
        mycrc ^= bAddresse[2]
        mycrc ^= bAddresse[3]
        payload2 = bAddresse + bytes(string.format('%02X', mycrc))
        fichier.write(payload2)

        mycrc = 0
        for i: 1..size(token)
            mycrc ^= token[i-1]
        end
        mycrc ^= 0xFF
        mycrc ^= size(token)
        payload3 = bytes(string.format('%02s%sFF%02X', string.hex(size(token)), token.tohex(), mycrc))
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
        if type(filename) != 'string' raise "erreur", "nom fichier non valide" end
        file_convname = filename + 'c'
        file_conv = open(file_convname, "wb")    
        file = open(filename, "rb")
        numB = file.size() / BLOCK
        reste = file.size() - numB * BLOCK
        try
            for i: 1 .. numB
                token = file.readbytes(BLOCK)
                self.write_block(file_conv, 0x08000000 + ((i-1) * BLOCK), token)
                yield(tas)        # tasmota.yield() -- faster version
            end
            token = file.readbytes(reste)
            self.write_block(file_conv, 0x08000000 + (numB * BLOCK), token)
        except .. as e, m
            file.close()
            raise e, m      # re-raise
        end
        file.close()
        file_conv.close()
        mqttprint('conversion done')
    end

    #------------------------------------------------------------------------------------#
    #                                   ECRITURE FICHIER                                 #
    #------------------------------------------------------------------------------------#
    def flash(filename)
        var bsl
        var tas = tasmota
        var yield = tasmota.yield
        var cfile = filename + 'c'
        var file
        var index = 0
        var token
        var BLOCK = 252
        var ret

        self.initialisation()
        file = open(cfile, "rb")
        while index < file.size()
            self.ser.write(bytes('31CE'))
            ret = self.wait_ack(100)     # malek
            if ret != '79'
                mqttprint('resp:' + str(ret))
                gpio.digital_write(self.bsl, 0)    # reset bsl
                raise 'erreur envoi 1', 'NACK'
            end

            token = file.readbytes(5)
            self.ser.write(token)
            ret = self.wait_ack(50)
            if ret != '79'
                mqttprint('resp:' + str(ret))
                gpio.digital_write(self.bsl, 0)    # reset bsl
                raise 'erreur envoi 2', 'NACK'
            end
            index += size(token)

            token = file.readbytes(BLOCK + 3)
            self.ser.write(token)
            ret = self.wait_ack(50)
            if ret != '79'
                mqttprint('resp:' + str(ret))
                gpio.digital_write(self.bsl, 0)    # reset bsl
                raise 'erreur envoi 3', 'NACK'
            end
            index += size(token)
            yield(tas)        # tasmota.yield() -- faster version
        end
        file.close()
        mqttprint('dernier token:' + str(size(token)))
        mqttprint('index:' + str(index))
        self.terminate()
        mqttprint('flashing done')
    end

    #------------------------------------------------------------------------------------#
    #                                   EFFACEMENT                                       #
    #------------------------------------------------------------------------------------#
    def erase()
        self.initialisation()
        mqttprint('ERASE:initialisation hardware')
        var ret
        # start erase
        self.ser.write(bytes('44BB'))
        ret = self.wait_ack(50) 
        if ret != '79'
            mqttprint('resp:' + str(ret))
            gpio.digital_write(self.bsl, 0)    # reset bsl
            raise 'erreur erase 1', 'NACK'
        end
        mqttprint("ERASE:start:" + str(ret))
        self.ser.write(bytes('FFFF00'))
        tasmota.delay(20000)
        ret = self.wait_ack(500) 
        if ret != '79'
            mqttprint('resp:' + str(ret))
            gpio.digital_write(self.bsl, 0)    # reset bsl
            raise 'erreur erase 2', 'NACK'
        end
        mqttprint("ERASE:end:" + str(ret))
        self.terminate()
    end
end

return flasher()