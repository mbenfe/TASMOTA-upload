import zigbee
import json
import string

class my_zb_handler

    ###############################################################################
    #
    ###############################################################################
    def removeAll(liste)
        while liste.size()!=0
            liste.remove(0)
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
        if myjson.contains('Data')
            print('type:',type(myjson['Data']),' ',myjson['Data'])
            var mylist = string.split(myjson['Data'],"/")
            for i: 0..size(mylist)-1
                print(i,':',mylist[i],' ',real(mylist[i]))
            end
        else
        #    self.removeAll(attr_list)
        end
            # print(f"shortaddr=0x{idx:04X} {event_type=} {attr_list.item(i)}")
     end

    def attributes_final(event_type, frame, attr_list, idx)
    #    print(f"shortaddr=0x{idx:04X} {event_type=} {attr_list=}")
    end
end

var my_handler = my_zb_handler()
zigbee.add_handler(my_handler)
