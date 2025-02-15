import mqtt
import string

class PT1000

    def init()
    end


    def poll()
         return 0
    end

end

pt1000 = PT1000()
pt1000.init()
tasmota.add_driver(pt1000)