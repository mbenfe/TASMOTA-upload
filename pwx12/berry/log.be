
class log

    var listlog
    var bloc
    var count

    def init()
        self.listLog = []
        self.count=0
        self.bloc=0

        print('heap:',tasmota.get_free_heap())
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