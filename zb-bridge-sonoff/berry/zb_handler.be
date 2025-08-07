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
        # print(f"shortaddr=0x{idx:04X} {event_type=} {frame=}")
    end

    def attributes_raw(event_type, frame, attr_list, idx)
        # print(f"shortaddr=0x{idx:04X} {event_type=} {attr_list=}")
    end
    
    def attributes_refined(event_type, frame, attr_list, idx)
        var myjson = json.load(str(attr_list))
        var topic
        var mydevice = zigbee[idx]
        var hexa = string.format("0x%04X",idx)

        if !self.sensors.contains(mydevice.name)
            self.sensors.insert(mydevice.name,{})
            self.sensors[mydevice.name].insert("Device",hexa)
            self.sensors[mydevice.name].insert("Name",mydevice.name)
        end

        if(!self.sensors[mydevice.name].contains("Device"))
            self.sensors[mydevice.name].insert("Device",hexa)
        end
        
        if(!self.sensors[mydevice.name].contains("Name"))
            self.sensors[mydevice.name].insert("Name",mydevice.name)
        end

        # Add timestamp - will be updated each time
        var now = tasmota.rtc()
        var timestamp = tasmota.time_str(now["local"])
        if self.sensors[mydevice.name].contains("Time")
            self.sensors[mydevice.name]["Time"] = timestamp
        else
            self.sensors[mydevice.name].insert("Time", timestamp)
        end

        for i:0..size(attr_list)-1
            if self.sensors[mydevice.name].contains(attr_list.item(i).key)
                self.sensors[mydevice.name][attr_list.item(i).key] = attr_list.item(i).val
            else
                if attr_list.item(i).key == 'Temperature' || attr_list.item(i).key == 'Humidity' 
                    || attr_list.item(i).key == 'BatteryVoltage' || attr_list.item(i).key == 'BatteryPercentage'
                    || attr_list.item(i).key == 'LinkQuality' 
                    || attr_list.item(i).key == 'Contact' 
                    self.sensors[mydevice.name].insert(attr_list.item(i).key,attr_list.item(i).val)
                end
            end    
        end
        
        if myjson.contains("Temperature")
            if(myjson["Temperature"] > -25 &&  myjson["Temperature"] < 100 )
                topic = string.format("gw/%s/%s/zb-%s/tele/SENSOR", global.client,global.ville, mydevice.name)
                mqtt.publish(topic, json.dump(self.sensors[mydevice.name]), true)
            else
                topic = string.format("gw/adomelec/alarm/%s", mydevice.name)
                mqtt.publish(topic, json.dump(self.sensors[mydevice.name]), true)
            end
        elif myjson.contains("Contact")  
            topic = string.format("gw/%s/%s/zb-%s/tele/SENSOR", global.client,global.ville, mydevice.name)
            mqtt.publish(topic, json.dump(self.sensors[mydevice.name]), true)
        end
        
        self.removeAll(attr_list)
    end

    def attributes_final(event_type, frame, attr_list, idx)
        # print(f"shortaddr=0x{idx:04X} {event_type=} {attr_list=}")
    end

end

var my_handler = my_zb_handler()
zigbee.add_handler(my_handler)