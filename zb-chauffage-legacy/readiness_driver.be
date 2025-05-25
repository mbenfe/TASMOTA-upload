import global
import zigbee

class readiness
    def init()
    end

    def check()
     #   print(zigbee.size(),'/',numSensors)
        if zigbee.size()>= numSensors
            if global.subscribed == false
                print('zigbee ready ......:',zigbee.size())
                print('subscribing ......:',zigbee.size())
                subscribes()
                global.subscribed = true
                print('load util .....')
                tasmota.load('util.be')
                print('load superviseur .....')
                tasmota.load('superviseur.be')
                print('load thermostat .....')
                tasmota.load('thermostat.be')   
                tasmota.delay(1000)         
            end
        end
    end

    def every_second()
        self.check()
    end

    def every_250ms()
        if global.listSetup.size()>0
            tasmota.cmd(global.listSetup[0])
            print('remove:',global.listSetup[0])
            global.listSetup.remove(0)
        end
    end
end

readiness = readiness()
tasmota.add_driver(readiness)