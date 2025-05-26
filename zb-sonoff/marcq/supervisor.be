class Supervisor
    def init()
    end

    def every_second()
        var sensors = read_sensors()
        print(sensors)
    end

 end

supervisor = Supervisor()
tasmota.add_driver(supervisor)