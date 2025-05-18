var version = "1.0.012025 "

import mqtt
import string
import json

class PWX4
    var ser
    var rx
    var tx
    var bsl
    var rst

    var logger
    var root
    var topic 
    var conso

    var agregate
    var map_powers
    var main_total
    var map_conso_hours
    var map_conso_days
    var map_conso_months
    var total_hours 
    var total_days
    var total_months

    def loadconfig()
        import json
        var jsonstring
        var file 
        file = open("esp32.cfg","rt")
        if file.size() == 0
            print('create esp32 config file')
            file = open("esp32.cfg","wt")
            jsonstring=string.format("{\"ville\":\"unknown\",\"client\":\"inter\",\"device\":\"unknown\"}")
            file.write(jsonstring)
            file.close()
            file=open("esp32.cfg","rt")
        end
        var buffer = file.read()
        var jsonmap = json.load(buffer)
        global.client=jsonmap["client"]
        print('client:',global.client)
        global.ville=jsonmap["ville"]
        print('ville:',global.ville)
        global.device=jsonmap["device"]
        print('device:',global.device)
    end

    def aggregation_power(topic, idx, payload_s, payload_b)
        var main_topic = string.format("gw/%s/%s/virtuel/tele/POWER", global.client,global.ville)
        var text
        var myjson = json.load(payload_s)
        self.main_total = 0
        self.map_powers[myjson["Name"]] = myjson["ActivePower"]
        for key:self.map_powers.keys()
            self.main_total += self.map_powers[key]
        end
        text = string.format('{"Device": "virtuel","Name":"main_total","ActivePower":%.1f}', self.main_total)
        mqtt.publish(main_topic, text, true)
    end

    def aggregation_conso(topic, idx, payload_s, payload_b)
        var myjson = json.load(payload_s)
        var conso_topic
        var text
        var mois = ["Jan","Fev","Mars","Avr","Mai","Juin","Juil","Aout","Sept","Oct","Nov","Dec"]
        var jours = ["Lun","Mar","Mer","Jeu","Ven","Sam","Dim"]
        if myjson["TYPE"] == "PWHOURS"
            conso_topic = string.format("gw/%s/%s/virtuel/tele/PWHOURS", global.client,global.ville)
            self.total_hours = {"0":0,"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0,"13":0,"14":0,"15":0,"16":0,"17":0,"18":0,"19":0,"20":0,"21":0,"22":0,"23":0}
            self.map_conso_hours[myjson["Name"]] = myjson["DATA"]
            for key:self.map_conso_hours.keys()
                for i:0..23
                    self.total_hours[str(i)] += self.map_conso_hours[key][str(i)]
                end
            end
            text = string.format('{"Device": "virtuel","Name":"main_total_H","TYPE":"PWHOURS","DATA":%s}', json.dump(self.total_hours))
            mqtt.publish(conso_topic, text, true)
        elif myjson["TYPE"] == "PWDAYS"
            conso_topic = string.format("gw/%s/%s/virtuel/tele/PWDAYS",global.client,global.ville)
            self.total_days = {"Lun":0,"Mar":0,"Mer":0,"Jeu":0,"Ven":0,"Sam":0,"Dim":0}
            self.map_conso_days[myjson["Name"]] = myjson["DATA"]
            for key:self.map_conso_days.keys()
                for i:0..6
                    self.total_days[jours[i]] += self.map_conso_days[key][jours[i]]
                end
            end
            text = string.format('{"Device": "virtuel","Name":"main_total_D","TYPE":"PWDAYS","DATA":%s}', json.dump(self.total_days))
            mqtt.publish(conso_topic, text, true)
        elif myjson["TYPE"] == "PWMONTHS"
            conso_topic = string.format("gw/%s/%s/virtuel/tele/PWMONTHS",global.client,global.ville)
            self.total_months = {"Jan":0,"Fev":0,"Mars":0,"Avr":0,"Mai":0,"Juin":0,"Juil":0,"Aout":0,"Sept":0,"Oct":0,"Nov":0,"Dec":0}
            self.map_conso_months[myjson["Name"]] = myjson["DATA"]
            for key:self.map_conso_months.keys()
                for i:0..11
                    self.total_months[mois[i]] += self.map_conso_months[key][mois[i]]
                end
            end
            text = string.format('{"Device": "virtuel","Name":"main_total_M","TYPE":"PWMONTHS","DATA":%s}', json.dump(self.total_months))
            mqtt.publish(conso_topic, text, true)
        end
    end

    def subscribes()
        var topic
        var value
        var mois = ["Jan","Fev","Mars","Avr","Mai","Juin","Juil","Aout","Sept","Oct","Nov","Dec"]
        var jours = ["Lun","Mar","Mer","Jeu","Ven","Sam","Dim"]
        for key:self.agregate.keys()
            value = self.agregate[key]
            # power
            self.map_powers.insert(value, 0)
            topic = string.format("gw/%s/%s/%s/tele/POWER",global.client,global.ville, key)
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.aggregation_power(topic, idx, payload_s, payload_b))
            # conso
            self.map_conso_hours.insert(value, {})
            for i:0..23
                self.map_conso_hours[value].insert(str(i), 0)
            end
            self.map_conso_days.insert(value, {})
            for i:0..6
                self.map_conso_days[value].insert(jours[i], 0)
            end
            self.map_conso_months.insert(value, {})
            for i:0..11
                self.map_conso_months[value].insert(mois[i], 0)
            end
            topic = string.format("gw/%s/%s/%s/tele/PWHOURS", global.client,global.ville,key)
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.aggregation_conso(topic, idx, payload_s, payload_b))
            topic = string.format("gw/%s/%s/%s/tele/PWDAYS", global.client,global.ville,key)
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.aggregation_conso(topic, idx, payload_s, payload_b))
            topic = string.format("gw/%s/%s/%s/tele/PWMONTHS", global.client,global.ville,key)
            mqtt.subscribe(topic, / topic, idx, payload_s, payload_b -> self.aggregation_conso(topic, idx, payload_s, payload_b))
        end
    end

    def init()
        self.loadconfig()
        import conso
        self.conso = conso
        import logger
        self.logger = logger
        self.rx = 3
        self.tx = 1
        self.rst = 2
        self.bsl = 13

        print('DRIVER: serial init done')
        print('heap:', tasmota.get_free_heap())
        self.ser = serial(self.rx, self.tx, 115200, serial.SERIAL_8N1) 
        # setup boot pins for stm32: reset disable & boot normal
        gpio.pin_mode(self.rst, gpio.OUTPUT)
        gpio.pin_mode(self.bsl, gpio.OUTPUT)
        gpio.digital_write(self.bsl, 0)
        gpio.digital_write(self.rst, 1)

        self.agregate = {"dl4-sdm":"gene_froid","dl12-td_ss-3":"gene_td_ss","dl12-tgbt3-3":"gene_tgbt"}
        self.map_powers = {}
        self.main_total = 0
        self.map_conso_hours = {}
        self.map_conso_days = {}
        self.map_conso_months = {}
        self.subscribes()
    end

    def fast_loop()
        self.read_uart(2)
    end

    def read_uart(timeout)
        if self.ser.available()
            var due = tasmota.millis() + timeout
            while !tasmota.time_reached(due) end
            var buffer = self.ser.read()
            self.ser.flush()
            var mystring = buffer.asstring()
            var mylist = string.split(mystring, '\n')
            var numitem = size(mylist)
            var topic
            var split
            var ligne
            for i: 0..numitem-2
                if mylist[i][0] == 'C'
                    self.conso.update(mylist[i])
                    topic = string.format("gw/%s/%s/%s/tele/PRINT", global.client, global.ville, global.device)
                    mqtt.publish(topic, mylist[i], true)
                elif mylist[i][0] == 'W'
 #                       self.logger.log_data(mylist[i])
                    split = string.split(mylist[i], ':')
                    for j:0..2
                        topic = string.format("gw/%s/%s/%s-%d/tele/POWER", global.client, global.ville, global.device, j+1)
                        ligne = string.format('{"Device": "%s","Name":"%s","ActivePower":%.1f}', global.device, global.configjson[global.device]["root"][j], real(split[j+1]))
                        mqtt.publish(topic, ligne, true)
                    end
                else
                    print('PWX4->', mylist[i])
                end
            end
        end
    end

    def midnight()
        self.conso.mqtt_publish('all')
    end

    def hour()
        var now = tasmota.rtc()
        var rtc = tasmota.time_dump(now["local"])
        var hour = rtc["hour"]
        # publish if not midnight
        if hour != 23
            self.conso.mqtt_publish('hours')
        end
    end

    def every_4hours()
        self.conso.sauvegarde()
    end

    def testlog()
        self.logger.store()
    end

end

pwx4 = PWX4()
tasmota.add_driver(pwx4)
tasmota.add_fast_loop(/-> pwx4.fast_loop())
tasmota.add_cron("59 59 23 * * *",  /-> pwx4.midnight(), "every_day")
tasmota.add_cron("59 59 * * * *",   /-> pwx4.hour(), "every_hour")
tasmota.add_cron("01 01 */4 * * *",   /-> pwx4.every_4hours(), "every_4_hours")

return pwx4