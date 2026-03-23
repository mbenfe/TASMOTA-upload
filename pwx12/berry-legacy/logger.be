var version = '05.01.2025'
class logger

    var listlog
    var bloc
    var count

    var filelog

    def store()
        self.filelog = open('logged.log','w')
        var tas = tasmota
        var yield = tasmota.yield

        var token
 
        for i:0..5760
            token = string.format("%f\n",self.listlog[i])
            yield(tas)        # tasmota.yield() -- faster version
            self.filelog.write(token)
        end
        self.filelog.close()
    end

    def init()
        self.listlog = []
        self.count=0
        self.bloc=0

        print('heap:',tasmota.get_free_heap())
        for i:0..5760
            self.listlog.insert(i,0.0)
        end
        print('heap:',tasmota.get_free_heap())
   end

    def log_data(data)
        var split
        split = string.split(data,':')
        # if(self.count<5760)
        #   self.count=self.count+1
        # end
        # self.listlog.insert(self.count,real(split[1]))
    end

end

return logger()