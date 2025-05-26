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
        print("waiting for Zigbee handler to start")
        print(zigbee.info())

        print("Zigbee handler started")
        for device: zigbee
            self.sensors.insert(device.name,{})
        end
        for k: self.sensors.keys()
            print(k)
        end
        self.subscribes()
    end


    def frame_received(event_type, frame, attr_list, idx)
        # print("------------- frame received -----------------------")
        # print(f"shortaddr=0x{idx:04X} {event_type=} {frame=}")
    end

    def attributes_raw(event_type, frame, attr_list, idx)
        # print("------------- attribute raw -----------------------")
        # print(f"shortaddr=0x{idx:04X} {event_type=} {attr_list=}")
    end
    
    def attributes_refined(event_type, frame, attr_list, idx)
        # print("--------------------------------------------------")
        # print(f"shortaddr=0x{idx:04X} {event_type=} {attr_list=}")
    end

    def attributes_final(event_type, frame, attr_list, idx)
        print("------------ attributes final ---------------")
        print(f"shortaddr=0x{idx:04X} {event_type=} {attr_list=}")
    end

    def acknowledge(topic, idx, payload_s, payload_b)
        var myjson = json.load(string.tolower(payload_s))
        if myjson == nil
            mqttprint("Error: Failed to parse JSON payload")
            return
        end

        print("-----------------------------------------------------------------")
        print(myjson)

        var newtopic

        newtopic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        mqtt.publish(newtopic, payload_s, true)
    end

     def subscribes()
        var topic 
        
        for device: zigbee
            topic = string.format("app/%s/%s/%04X/set/SETUP", global.client, global.ville, device.shortaddr)
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.acknowlege(topic, idx, payload_s, payload_b))
            print("subscribe to topic: ", topic)
        end
    end

end

var my_handler = my_zb_handler()
zigbee.add_handler(my_handler)
