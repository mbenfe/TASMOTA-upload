
class log

    var listlog

    def init()
        self.listLog = []

        for i:0..3600
            self.listLog.insert(i,0.0)
        end
        print('heap:',tasmota.get_free_heap())
   end

    def log(data)
        var split
        split = string.split(data)
        print(split[1])
    end

end

return log()