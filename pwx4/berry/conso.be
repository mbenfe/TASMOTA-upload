#---------------------------------#
# CONSO.BE 1.0 PWX4               #
#---------------------------------#
import json
import string
import mqtt
import global


class conso
    var consojson
    var day_list
    var month_list
    var num_day_month

    def get_hours()
        var ligne
        ligne = string.format('{"0":0,"1":0,"2":0,"3":0,"4":0,"5":0,"6":0,"7":0,"8":0,"9":0,"10":0,"11":0,"12":0,"13":0,"14":0,"15":0,"16":0,"17":0,"18":0,"19":0,"20":0,"21":0,"22":0,"23":0}')
        return ligne
    end

    def get_days()
        var ligne
        ligne = string.format('{"Lun":0,"Mar":0,"Mer":0,"Jeu":0,"Ven":0,"Sam":0,"Dim":0}')
        return ligne
    end

    def get_months()
        var ligne
        ligne = string.format('{"Jan":0,"Fev":0,"Mars":0,"Avr":0,"Mai":0,"Juin":0,"Juil":0,"Aout":0,"Sept":0,"Oct":0,"Nov":0,"Dec":0}')
        return ligne
    end


    def init_conso()
        var file
        var ligne
        print("creation du fichier de sauvegarde de la consommation....")
        var name = string.format("p_%s.json",global.ville)
        print("lecture du fichier ",name)
        import path
        if(path.exists(name))
            file = open(name,"rt")
            ligne = file.read()
            file.close()
            global.configjson=json.load(ligne)
            print(global.configjson[global.device])
            if global.configjson[global.device]["produit"]=="PWX4"
                ligne = string.format('{"hours":[]}')
                var mainjson = json.load(ligne)
                mainjson.insert("days",[])
                mainjson.insert("months",[])
                print("configuration PWX4")
                for i:0..0
                    if global.configjson[global.device]["mode"][i]=="tri"
                        ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWHOURS","DATA":%s}',global.device,global.configjson[global.device]["root"][i],self.get_hours())
                        mainjson["hours"].insert(i,json.load(ligne))
                        ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWDAYS","DATA":%s}',global.device,global.configjson[global.device]["root"][i],self.get_days())
                        mainjson["days"].insert(i,json.load(ligne))
                        ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWMONTHS","DATA":%s}',global.device,global.configjson[global.device]["root"][i],self.get_months())
                        mainjson["months"].insert(i,json.load(ligne))
                    else
                    end
                end
                ligne = json.dump(mainjson)
                return ligne
            end
        end
    end

    def init()
        import path
        var ligne
        var file
        if(path.exists("conso.json"))
            print("chargement de la sauvegarde de consommation")
            file = open("conso.json","rt")
            ligne = file.read()
            self.consojson= json.load(ligne)
            print(self.consojson)
            file.close()
            var name = string.format("p_%s.json",global.ville)
            file = open(name,'rt')
            ligne=file.read()
            global.configjson=json.load(ligne)
            file.close()
        else
            ligne = self.init_conso()
            file = open("conso.json","wt")
            file.write(ligne)
            file.close()
            print("fichier sauvegarde de consommation cree !")
        end
        self.day_list = ["Dim","Lun","Mar","Mer","Jeu","Ven","Sam"]
        self.month_list = ["","Jan","Fev","Mars","Avr","Mai","Juin","Juil","Aout","Sept","Oct","Nov","Dec"]
        self.num_day_month = [0,31,28,31,30,31,30,31,31,30,31,30,31]
    end

    def update(data)
        var split = string.split(data,":")
        var now = tasmota.rtc()
        var rtc=tasmota.time_dump(now["local"])
        var second = rtc["sec"]
        var minute = rtc["min"]
        var hour = rtc["hour"]
        var day = rtc["day"]
        var month = rtc["month"]
        var year = rtc["year"]
        var day_of_week = rtc["weekday"]  # 0=Sunday, 1=Monday, ..., 6=Saturday
        print('->',self.consojson)
        for i:0..0
            self.consojson["hours"][i]["DATA"][str(hour)]+=real(split[i+1])
            self.consojson["days"][i]["DATA"][self.day_list[day_of_week]]+=real(split[i+1])
            self.consojson["months"][i]["DATA"][self.month_list[month]]+=real(split[i+1])
        end
    end

    def sauvegarde()
        var ligne = json.dump(self.consojson)
        var file = open("conso.json","wt")
        file.write(ligne)
        file.close()
    end

    def mqtt_publish(scope)
        var now = tasmota.rtc()
        var rtc=tasmota.time_dump(now["local"])
        var second = rtc["sec"]
        var minute = rtc["min"]
        var hour = rtc["hour"]
        var day = rtc["day"]
        var month = rtc["month"]
        var year = rtc["year"]
        var day_of_week = rtc["weekday"]  # 0=Sunday, 1=Monday, ..., 6=Saturday
        var topic
        var payload
        var ligne

        var stringdevice
       for i:0..0
            stringdevice = string.format("%s",global.device)
            if(scope=="hours")
                topic = string.format("gw/%s/%s/%s/tele/PWHOURS",global.client,global.ville,stringdevice)
                payload=self.consojson["hours"][i]["DATA"]
                ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWHOURS","DATA":%s}',global.device,global.configjson[global.device]["root"][i],json.dump(payload))
                mqtt.publish(topic,ligne,true)
                self.consojson["hours"][i]["DATA"][str(hour+1)]=0
            else
                topic = string.format("gw/%s/%s/%s/tele/PWHOURS",global.client,global.ville,stringdevice)
                payload=self.consojson["hours"][i]["DATA"]
                ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWHOURS","DATA":%s}',global.device,global.configjson[global.device]["root"][i],json.dump(payload))
                mqtt.publish(topic,ligne,true)
                self.consojson["hours"][i]["DATA"][str(0)]=0

                topic = string.format("gw/%s/%s/%s/tele/PWDAYS",global.client,global.ville,stringdevice)
                payload=self.consojson["days"][i]["DATA"]
                ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWDAYS","DATA":%s}',global.device,global.configjson[global.device]["root"][i],json.dump(payload))
                mqtt.publish(topic,ligne,true)
                if day == 6
                    self.consojson["days"][i]["DATA"]["Dim"]=0
                else
                    self.consojson["days"][i]["DATA"][str(self.day_list[day_of_week+1])]=0
                end
                topic = string.format("gw/%s/%s/%s/tele/PWMONTHS",global.client,global.ville,stringdevice)
                payload=self.consojson["months"][i]["DATA"]
                ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWMONTHS","DATA":%s}',global.device,global.configjson[global.device]["root"][i],json.dump(payload))
                mqtt.publish(topic,ligne,true)
                # RAZ next month if end of the month
                if(day==self.num_day_month[month])  # si dernier jour
                    if(month == 12) # decembre
                        self.consojson["months"][i]["DATA"]["Jan"]=0
                    else
                        self.consojson["months"][i]["DATA"][str(self.month_list[month+1])]
                    end
                end
            end
        end
    end
end

return conso()