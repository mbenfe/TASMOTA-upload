import zigbee
import json
import string
import global

class my_zb_handler
    var sensors

    ###############################################################################
    #
    ###############################################################################
    def removeAll(liste)
        while liste.size()!=0
            liste.remove(0)
        end
    end

    def init()
        self.sensors = map()
        for device: zigbee
            self.sensors.insert(device.name,{})
        end
        for k: self.sensors.keys()
            print(k)

        end
    end


    def frame_received(event_type, frame, attr_list, idx)
#        print(f"shortaddr=0x{idx:04X} {event_type=} {frame=}")
    end

    def attributes_raw(event_type, frame, attr_list, idx)
#         print(f"shortaddr=0x{idx:04X} {event_type=} {attr_list=}")
    end
    
    def attributes_refined(event_type, frame, attr_list, idx)

        var myjson = json.load(str(attr_list))
        var topic
        var mydevice = zigbee[idx]
        if myjson.contains('Temperature')
            self.sensors[mydevice.name].insert('Temperature',myjson['Temperature'])
            self.sensors[mydevice.name].insert('Name',mydevice.name)
            self.sensors[mydevice.name].insert('Device',mydevice.shortaddrhex)
            topic = string.format("gw/%s/%s/zb-%s/tele/SENSOR", global.client,global.ville, mydevice.name)
            mqtt.publish(topic, json.dump(self.sensors[mydevice.name]), true)            
            self.removeAll(attr_list)
        elif myjson.contains('Humidity')
            self.sensors[mydevice.name].insert('Humidity',myjson['Humidity'])
            self.removeAll(attr_list)
        elif myjson.contains('BatteryVoltage')
            self.sensors[mydevice.name].insert('BatteryVoltage',myjson['BatteryVoltage'])
            self.removeAll(attr_list)
        elif myjson.contains('BatteryPercentage')
            self.sensors[mydevice.name].insert('BatteryPercentage',myjson['BatteryPercentage'])
            self.removeAll(attr_list)
        elif myjson.contains('LinkQuality')         
            self.sensors[mydevice.name].insert('LinkQuality',myjson['LinkQuality'])
            self.removeAll(attr_list)
        end
     end

    def attributes_final(event_type, frame, attr_list, idx)
    #    print(f"shortaddr=0x{idx:04X} {event_type=} {attr_list=}")
    end
end

var my_handler = my_zb_handler()
zigbee.add_handler(my_handler)
