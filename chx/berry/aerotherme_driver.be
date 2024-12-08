import string
import mqtt

# prealablement configurer les gpios avec configuration model
# gpio0 = I2C_SCL 1
# gpio1 = I2C_SDA 1

class AHT20 
    var wire 
    var humidity
    var temperature
    var name1
    var name2
    var client
    var ville

    def init()
        self.name1 = 'aerotherm7'
        self.name2 = ''
        self.client = 'inter'
        self.ville = 'aulnay'
        var status
        self.humidity=0
        self.temperature=0
        self.wire = tasmota.wire_scan(0x38)
        if self.wire
            print("I2C adress:",wire1.scan())
            # read status
            print('read status...')
            status = self.wire.read_bytes(0x38,0x71,1)
            print('status:',status)
            # reset
            # print("AHT20 reset....")
            # self.wire.write(0x38,0xBA,0,1)
            # tasmota.delay(20)
            # self.wire.write(0x38, 0xBE,0,1)
            # print('AHT20 initialized....')
        else
            print('erreur initialisation AHT20')
        end
    end

   def publish()
     var topic
     var payload
     topic = 'gw/'+self.client+'/'+self.ville+'/'+self.name1+'/tele/SENSOR'     
     payload = string.format('{"Device":"%s","Name":"%s","Temperature":%.2f,"Humidity":%.2f}',self.name1,self.name1,self.temperature,self.humidity)
     mqtt.publish(topic,payload,true)
   end

    def poll()
        var measure
        self.wire._begin_transmission(0x38)
        self.wire._write(0xAC)
        self.wire._write(0x33)
        self.wire._write(0x00)
        self.wire._end_transmission()
        tasmota.delay(80)
        measure = self.wire.read_bytes(0x38,0x71,7)
        self.humidity=number('0x'+measure[1..3].tohex())
        self.humidity = self.humidity>>4
        self.humidity = real(self.humidity) / real(1048576)
        self.humidity*=100
        self.temperature=number('0x'+measure[3..5].tohex())
        self.temperature &= 0x0FFFFF
        self.temperature = real(self.temperature) / real(1048576)
        self.temperature*=200
        self.temperature-=50

        self.publish()
    end
end

aht20 = AHT20()
tasmota.add_driver(aht20)

tasmota.add_cron("15 * * * * *", /-> aht20.poll(), "every_minute")
