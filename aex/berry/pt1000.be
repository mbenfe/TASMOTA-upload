import mqtt
import string

class PT1000
    def init()
        tasmota.cmd("sensor12 s2")
        tasmota.resp_cmnd("sensor12 s2 done")
    end

    def poll(pt1000)
        var data = tasmota.read_sensors()
        if(data == nil)
            return -99
        end
        var myjson = json.load(data)
        print("--------------------")
        print('measure:'+str(myjson["ADS1115"]["A0"]))
        if(myjson["ADS1115"] != nil && pt1000 == 0)
            var Van1 = real(myjson["ADS1115"]["A0"])/real(32768)*real(2.048)
            print("Van1:",Van1)
#            var Rpt1000 = 10000*(Van1/(5-Van1))
            var Rpt1000 = 10000*(Van1/(5-Van1))/2
            print("Rpt1000:",Rpt1000)
            var temperature = (Rpt1000-1000)/3.85
            print("temperature:",temperature)
            return temperature
        else
            return -99
        end
    end
end

pt1000 = PT1000()
pt1000.init()
tasmota.add_driver(pt1000)