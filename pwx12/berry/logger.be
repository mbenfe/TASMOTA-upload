
class logger

    var listlog
    var bloc
    var count

    var filelog

    def real_to_bytes(myreal) 
    # Convert the float to its integer representation
        var int_representation = tasmota.real_to_int(myreal)
    
        # Extract bytes using bitwise operations
        var byte_array = [0, 0, 0, 0]
        byte_array[0] = (int_representation >> 24) & 0xFF
        byte_array[1] = (int_representation >> 16) & 0xFF
        byte_array[2] = (int_representation >> 8) & 0xFF
        byte_array[3] = int_representation & 0xFF
    
        return byte_array
    end


    def store()
        self.filelog = open('logged.log','w')
        var tas = tasmota
        var yield = tasmota.yield
        var mybytes
 
        for i:0..5760
            yield(tas)        # tasmota.yield() -- faster version
            mybytes=self.real_to_bytes(self.listlog[i])
            self.filelog.write_bytes(mybytes)
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
        if(self.count<5760)
          self.count=self.count+1
        end
        self.listlog.insert(self.count,real(split[1]))
    end

end

return logger()