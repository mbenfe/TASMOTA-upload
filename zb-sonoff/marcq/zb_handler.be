import zigbee
import json
import string
import global

class my_zb_handler
    var sensors
    var state_detecteur_escalier
    var state_detecteur_entree

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
            self.sensors.insert(device.name,device)
        end
        for k: self.sensors.keys()
            print(k)
        end
        print(self.sensors)
        self.subscribes()
        self.state_detecteur_escalier = 0
        self.state_detecteur_entree = 0
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

    def timeout(event_type, frame, attr_list, idx)
        tasmota.cmd('zbsend { "Device":"switch_entree", "send" : {"power":0} }')
    end

    def attributes_final(event_type, frame, attr_list, idx)
        # print("------------ attributes final ---------------")
        # print(f"shortaddr=0x{idx:04X} {event_type=} {attr_list=}")
        var myjson
        var command

        var contact = zigbee.item("contact_entree")
 
        if contact.shortaddr == idx
            tasmota.cmd('zbsend { "Device":"switch_entree", "send" : {"power":1} }')
        #    tasmota.set_timer(60000, /-> self.timeout())
        end

        var escalier = zigbee.item("detecteur_escalier")
        if escalier.shortaddr == idx
            for i: 0..attr_list.size()-1
                myjson = attr_list[i].tomap()
                if myjson['key']=='Occupancy'
                    self.state_detecteur_escalier = myjson['val']
                    command = string.format('zbsend { "Device":"switch_entree", "send" : {"power":%d} }', int(myjson['val']) | int(self.state_detecteur_entree))
                    tasmota.cmd(command)
                    if int(myjson['val']) | int(self.state_detecteur_entree)
                        print("Detecteur escalier ON")
                    end
                end
            end
        end
        var entree = zigbee.item("detecteur_entree")
        if entree.shortaddr == idx
            for i: 0..attr_list.size()-1
                myjson = attr_list[i].tomap()
                if myjson['key']=='Occupancy'
                    self.state_detecteur_entree = myjson['val']
                    command = string.format('zbsend { "Device":"switch_entree", "send" : {"power":%d} }', myjson['val'] | self.state_detecteur_escalier)
                    if(myjson['val'] | self.state_detecteur_entree)
                        print("Detecteur entree ON")
                    end
                    tasmota.cmd(command)
                end
            end
        end
    end

    def acknowledge(topic, idx, payload_s, payload_b)
        print("------------- acknowledge -----------------------")
        print(f"topic={topic} payload_s={payload_s}")
        var myjson = json.load(string.tolower(payload_s))
        if myjson.contains("power")
            var command = string.format('zbsend { "Device":"%s", "send" : {"power":%d} }', myjson["name"], myjson["power"])
            tasmota.cmd(command)
            tasmota.resp_cmnd("done")   
        end

        var newtopic

        newtopic = string.format("gw/%s/%s/%s/tele/SENSOR", global.client, global.ville, global.device)
        mqtt.publish(newtopic, payload_s, true)
    end

     def subscribes()
        var topic 
        
        for device: zigbee
            topic = string.format("app/%s/%s/%s/tele/SENSOR", global.client, global.ville, device.name)
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.acknowledge(topic, idx, payload_s, payload_b))
            print("subscribe to topic: ", topic)
        end
    end

    def every_5_minutes()
        if (self.state_detecteur_escalier == 0 &&  self.state_detecteur_entree == 0)
            tasmota.cmd('zbsend { "Device":"switch_entree", "send" : {"power":0} }')
        end
    end

end

var my_handler = my_zb_handler()
zigbee.add_handler(my_handler)

tasmota.add_cron("0 */15 * * * *", /-> my_handler.every_5_minutes(), "every_5_minutes")

