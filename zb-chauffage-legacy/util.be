import zigbee
import string
import mqtt
import strict
import global


class util
  ###############################################################################
  #
  ###############################################################################
  def init()
  end

  def zbreads(cmd, idx, payload, payload_json)
    var command
    if size(payload) == 0
        print('erreur argument...')
        tasmota.resp_cmnd_done()
        return
    end
    print(payload)
    # semaine
    command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x0006","Read":"0x1030"}',payload) # ok
    tasmota.cmd(command)
    print(command)
    command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x0006","Read":"0x1031"}',payload) # ok
    tasmota.cmd(command)
    print(command)
    command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x0006","Read":"0x1032"}',payload) # ok
    tasmota.cmd(command)
    print(command)
    command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x0006","Read":"0x1033"}',payload) # ok
    tasmota.cmd(command)
    print(command)
   tasmota.resp_cmnd_done()
end

  def zbreadw(cmd, idx, payload, payload_json)
    var command
    if size(payload) == 0
        print('erreur argument...')
        tasmota.resp_cmnd_done()
        return
    end
    # week end
    command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x0006","Read":"0x1034"}',payload) # ok
    tasmota.cmd(command)
    command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x0006","Read":"0x1035"}',payload) # ok
    tasmota.cmd(command)
    command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x0006","Read":"0x1036"}',payload)
    tasmota.cmd(command)
    command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x0006","Read":"0x1037"}',payload)
    tasmota.cmd(command)
   tasmota.resp_cmnd_done()
end

  def zbreada(cmd, idx, payload, payload_json)
    var command
    if size(payload) == 0
        print('erreur argument...')
        tasmota.resp_cmnd_done()
        return
    end
    # away
    command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x0006","Read":"0x1038"}',payload) # ok
    tasmota.cmd(command)
    command = string.format('ZbSend {"Device":"%s","endpoint":1,"cluster":"0x0006","Read":"0x1039"}',payload) # ok
    tasmota.cmd(command)
   tasmota.resp_cmnd_done()
end
######################################################################
#  ZIGBEE commands:
#  ZbResetParameters  : reset all atributs to default
#  ZbResetFactory: reset to factory
#  ZbLocation: set device location
#  ZbTempOffset: set the potential offset of measurment of temp due to AHT20 heater proximity and/or electronic device temperature
#  ZbTempLog: set the timing to log temperature (in seconds) - expect minutes (>60 seconds)
#  ZbPowerLog: set the timing of log power (in seconds) - expect 1s when mobile application and 5s default or more
#  ZbLed: set whether or not the led is blinkig when running and connected (usefull for troubleshooting)
def ZbResetParameter(cmd, idx, payload, payload_json)
  var command
  # command ZCL erase to default parameters value
  command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0000!00/\"}",payload)
  print(command)
  tasmota.cmd(command)
end

def ZbResetFactory(cmd, idx, payload, payload_json)
    var command
    # command set attribut flagreset (factory reset) to 1
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/15101001\"}",payload)
    print(command)
    tasmota.cmd(command)
    # command ZCL erase to default parameters value
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0000!00/\"}",payload)
    print(command)
    tasmota.cmd(command)
  end

  def ZbLocation(cmd, idx, payload, payload_json)
    var argument = string.split(payload,' ')
    if argument.size() < 2   # manque un argument
        print('erreur arguments')
        return
    end
    var block = string.split(payload, size(argument[0])+1)
    var converted = bytes().fromstring(block[1])
    var length = size(converted)
    var command
    # command set location
    # ajout caractere de fin 0x00
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/161042%02X%s00\"}",argument[0],length+1,converted.tohex())
    print(command)
    tasmota.cmd(command)
    tasmota.resp_cmnd_done()
  end

  def ZbTempOffset(cmd, idx, payload, payload_json)
    var argument = string.split(payload,' ')
    if argument.size() < 2   # manque un argument
        print('erreur arguments')
        return
    end
    # convert signed int to little endian and format
    var multiple = real(argument[1])
    multiple *= 100
    if(multiple==0)
        return
    end
    var command
    var block
    # offset negatif format
    if(multiple < 0)  
      var hexValue = string.hex(int(multiple))
      var bytesValue = bytes(hexValue)
      var littleEndian = bytesValue.geti(2,2)
      var stringValue = string.format("%08X",littleEndian)
      block = string.split(stringValue,4)
    else
        var hexValue = string.hex(int(multiple))
        if(size(hexValue)==1)
            hexValue=string.format("000%s",hexValue)
        end
        if(size(hexValue)==2)
            hexValue=string.format("00%s",hexValue)
        end
        if(size(hexValue)==3)
            hexValue=string.format("0%s",hexValue)
        end
        var bytesValue = bytes(hexValue)
        var littleEndian = bytesValue.geti(0,2)
        var stringValue = string.format("%08X",littleEndian)
        block = string.split(stringValue,4)
      end
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/171029%s\"}",argument[0],block[1])
    print(command)
    tasmota.cmd(command)
    tasmota.resp_cmnd_done()
  end

  def ZbTempLog(cmd, idx, payload, payload_json)
    var argument = string.split(payload,' ')
    if argument.size() < 2   # manque un argument
        print('erreur arguments')
        return
    end
    # convert unsigned to little endian and format
    var hexValue = string.format("%04X",number(argument[1]))
    var bytesValue = bytes(hexValue)
    var littleEndian = bytesValue.get(0,2)
    var stringValue = string.format("%04X",littleEndian)
    var command
    # command set temp log type uint16 (0x21)
    # ajout caractere de fin 0x00
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/181021%s\"}",argument[0],stringValue)
    print(command)
    tasmota.cmd(command)
    tasmota.resp_cmnd_done()
   end

  def ZbPowerLog(cmd, idx, payload, payload_json)
    var argument = string.split(payload,' ')
    if argument.size() < 2   # manque un argument
        print('erreur arguments')
        return
    end
    # convert unsigned to little endian and format
    var hexValue = string.format("%04X",number(argument[1]))
    var bytesValue = bytes(hexValue)
    var littleEndian = bytesValue.get(0,2)
    var stringValue = string.format("%04X",littleEndian)
    var command
    # command set power log type uint16 (0x21)
    # ajout caractere de fin 0x00
    command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/191021%s\"}",argument[0],stringValue)
    print(command)
    tasmota.cmd(command)
    tasmota.resp_cmnd_done()
  end
 
  def ZbLed(cmd, idx, payload, payload_json)
    var argument = string.split(payload,' ')
    var state
    # test arguments
    if argument.size() < 2 ||  (string.toupper(argument[1])!='ON' && argument[1]!='1' && string.toupper(argument[1])!='OFF' && argument[1]!='0')
        print('erreur arguments')
        return
    end
    if string.toupper(argument[1])=='ON' || argument[1]=='1'
        state = 1
    else 
        state = 0
    end
    var command
    # command led on off
   command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/1A1010%02X\"}",argument[0],state)
    print(command)
    tasmota.cmd(command)
    tasmota.resp_cmnd_done()
  end
 
  def ZbStorage(cmd, idx, payload, payload_json)
    # test arguments
    if size(payload) < 1
        print('erreur arguments')
        return
    end
    var command
    # command flag storage = 1 (remis a zero dans le module une fois le storage effectu�)
   command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/1B101001\"}",payload)
    print(command)
    tasmota.cmd(command)
    tasmota.resp_cmnd_done()
  end

  def ZbReboot(cmd, idx, payload, payload_json)
    # test arguments
    if size(payload) < 1
        print('erreur arguments')
        return
    end
    var command
    # command flag reboot = 1 (reset du systeme)
   command = string.format("Zbsend {\"Device\":\"%s\",\"send\":\"0006_02/1C101001\"}",payload)
    print(command)
    tasmota.cmd(command)
    tasmota.resp_cmnd_done()
  end

  def PrintLog()
    var jsonmap
    var buffer
    var file = open('sauvegarde.json','rt')
    buffer = file.read(file.size())
    jsonmap = json.load(buffer)
    for  key:jsonmap.keys()
       print(jsonmap[key])
    end
    file.close()
    return true
  end

  ###############################################################################
  #
  ###############################################################################
  def load_config() 
    var tab = {  'Mode':'14',
                 'SemaineMatin':'30',
                 'SemaineJournee':'31',
                 'SemaineSoir':'32',
                 'SemaineNuit':'33',
                 'WeMatin':'34',
                 'WeJournee':'35',
                 'WeSoir':'36',
                 'WeNuit':'37',
                 'AwayTemp':'38',
                 'AwayHum':"39"}

    var device 
    var command
    var count = 0
    for k:global.mapThermostat.keys()
       print('k:',k)
       self.zbreads(k)
       tasmota.delay(1000)
       self.zbreadw(k)
       tasmota.delay(1000)
       self.zbreada(k)
       tasmota.delay(1000)
    end
    global.ready = true
  end
end


var util = util()
zigbee.add_handler(util)

print('Zigbee: create commande ZbResetParameter')
tasmota.add_cmd('ZbResetParameter',/->util.ZbResetParameter)

print('Zigbee: create commande ZbResetFactory')
tasmota.add_cmd('ZbResetFactory',/->util.ZbResetFactory)

print('Zigbee: create commande Zblocation')
tasmota.add_cmd('ZbLocation',/->util.ZbLocation)

print('Zigbee: create commande util.ZbTempOffset')
tasmota.add_cmd('ZbTempOffset',/->util.ZbTempOffset)

print('Zigbee: create commande ZbTempLog')
tasmota.add_cmd('ZbTempLog',/->util.ZbTempLog)

print('Zigbee: create commande ZbPowerLog')
tasmota.add_cmd('ZbPowerLog',/->util.ZbPowerLog)

print('Zigbee: create commande ZbLed')
tasmota.add_cmd('ZbLed',/->util.ZbLed)

print('Zigbee: create commande ZbStorage')
tasmota.add_cmd('ZbStorage',/->util.ZbStorage)

print('Zigbee: create commande ZbReboot')
tasmota.add_cmd('ZbReboot',/->util.ZbReboot)

print('Zigbee: create commande printlog')
tasmota.add_cmd('PrintLog',/->util.PrintLog)

tasmota.add_cmd('ZbLed',/cmd, idx, payload, payload_json -> util.ZbLed(cmd, idx, payload, payload_json))

 tasmota.add_cmd('ZbReads',/ cmd, idx, payload, payload_json -> util.zbreads(cmd, idx, payload, payload_json))
 tasmota.add_cmd('ZbReadw',/ cmd, idx, payload, payload_json -> util.zbreadw(cmd, idx, payload, payload_json))
 tasmota.add_cmd('ZbReada',/ cmd, idx, payload, payload_json -> util.zbreada(cmd, idx, payload, payload_json))

tasmota.add_cmd('Zbloadconfig',/ -> util.load_config())
