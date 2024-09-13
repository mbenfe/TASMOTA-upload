#---------------------------------#
# CONSO.BE 1.0 WFX                #
#---------------------------------#

import json
import string
import mqtt
import global


class conso
    var consojson1
    var consojson2

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


    def init_conso(device)
        var file
        var ligne
        print('CONSO:init_conso:creation du fichier de sauvegarde de la consommation....')
        var name = string.format('p_%s.json',global.ville)
        print('CONSO:init_conso:lecture du fichier ',name)
        import path
        var targetdevice
        if(path.exists(name))
            file = open(name,'rt')
            ligne = file.read()
            file.close()
            global.configjson=json.load(ligne)
            if(device == 1)
                targetdevice = global.device1
            else
                targetdevice = global.device2
            end
            if targetdevice != "unknown"
                if global.configjson[targetdevice]["produit"]=='PWX12'
                    ligne = string.format('{"hours":[]}')
                    var mainjson = json.load(ligne)
                    mainjson.insert('days',[])
                    mainjson.insert('months',[])
                    print('CONSO:init_conso:configuration PWX12')
                    for i:0..2
                        if global.configjson[targetdevice]["mode"][i]=='tri'
                            ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWHOURS","DATA":%s}',targetdevice,global.configjson[targetdevice]["root"][i],self.get_hours())
                            mainjson["hours"].insert(i,json.load(ligne))
                            ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWDAYS","DATA":%s}',targetdevice,global.configjson[targetdevice]["root"][i],self.get_days())
                            mainjson["days"].insert(i,json.load(ligne))
                            ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWMONTHS","DATA":%s}',targetdevice,global.configjson[targetdevice]["root"][i],self.get_months())
                            mainjson["months"].insert(i,json.load(ligne))
                        else
                        end
                    end
                    ligne = json.dump(mainjson)
                    return ligne
                else
                    print('CONSO:init_conso:configuration PWX4')
                    ligne = string.format('{"hours":[]}')
                    var mainjson = json.load(ligne)
                    mainjson.insert('days',[])
                    mainjson.insert('months',[])
                    if global.configjson[targetdevice]["mode"]=='tri'
                        ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWHOURS","DATA":%s}',targetdevice,global.configjson[targetdevice]["root"][0],self.get_hours())
                        mainjson["hours"].insert(0,json.load(ligne))
                        ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWDAYS","DATA":%s}',targetdevice,global.configjson[targetdevice]["root"][0],self.get_days())
                        mainjson["days"].insert(0,json.load(ligne))
                        ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWMONTHS","DATA":%s}',targetdevice,global.configjson[targetdevice]["root"][0],self.get_months())
                        mainjson["months"].insert(0,json.load(ligne))
                    else
                    end
                    ligne = json.dump(mainjson)
                    return ligne
                end
            end
        end
    end

    def init()
        import path
        var ligne
        var file
        # premier BL logger
        if(path.exists('conso1.json'))
            print('CONSO:chargement de la sauvegarde de consommation')
            file = open("conso1.json","rt")
            ligne = file.read()
            self.consojson1= json.load(ligne)
            print('CONSO:',self.consojson1)
            file.close()
        else
            ligne = self.init_conso(1)
            file = open('conso1.json','wt')
            file.write(ligne)
            file.close()
            print('CONSO:fichier sauvegarde de consommation cree !')
        end
        var name = string.format("p_%s.json",global.ville)
        file = open(name,'rt')
        ligne=file.read()
        global.configjson=json.load(ligne)
        file.close()
        self.day_list = ["Dim","Lun","Mar","Mer","Jeu","Ven","Sam"]
        self.month_list = ["","Jan","Fev","Mars","Avr","Mai","Juin","Juil","Aout","Sept","Oct","Nov","Dec"]
        self.num_day_month = [0,31,28,31,30,31,30,31,31,30,31,30,31]
        # deuxieme BL logger
        if(path.exists('conso2.json'))
            print('CONSO:chargement de la sauvegarde de consommation')
            file = open("conso2.json","rt")
            ligne = file.read()
            self.consojson2= json.load(ligne)
            print('CONSO:',self.consojson2)
            file.close()
        else
            ligne = self.init_conso(2)
            file = open('conso2.json','wt')
            file.write(ligne)
            file.close()
            print('CONSO:fichier sauvegarde de consommation cree !')
        end
        self.day_list = ["Dim","Lun","Mar","Mer","Jeu","Ven","Sam"]
        self.month_list = ["","Jan","Fev","Mars","Avr","Mai","Juin","Juil","Aout","Sept","Oct","Nov","Dec"]
        self.num_day_month = [0,31,28,31,30,31,30,31,31,30,31,30,31]
    end

    def update(data,device)
        var split = string.split(data,':')
        var now = tasmota.rtc()
        var rtc=tasmota.time_dump(now["local"])
        var second = rtc["sec"]
        var minute = rtc["min"]
        var hour = rtc["hour"]
        var day = rtc["day"]
        var month = rtc["month"]
        var year = rtc["year"]
        var day_of_week = rtc["weekday"] # 0=Sunday, 1=Monday, ..., 6=Saturday
        var channel  
        if device == 1 
            if global.configjson[global.device1]["produit"] == "PWX4"
                channel=0
            else
                channel=2
            end
        else
            if global.configjson[global.device2]["produit"] == "PWX4"
                channel=0
            else
                channel=2
            end
        end
        for i:0..channel
            if(device ==1)
                self.consojson1["hours"][i]["DATA"][str(hour)]+=real(split[i+1])
                self.consojson1["days"][i]["DATA"][self.day_list[day_of_week]]+=real(split[i+1])
                self.consojson1["months"][i]["DATA"][self.month_list[month]]+=real(split[i+1])
            else
                self.consojson2["hours"][i]["DATA"][str(hour)]+=real(split[i+1])
                self.consojson2["days"][i]["DATA"][self.day_list[day_of_week]]+=real(split[i+1])
                self.consojson2["months"][i]["DATA"][self.month_list[month]]+=real(split[i+1])
            end
        end
    end

    def sauvegarde()
        var ligne
        var file 
        ligne = json.dump(self.consojson1)
        file = open('conso1.json',"wt")
        file.write(ligne)
        file.close()
        ligne = json.dump(self.consojson2)
        file = open('conso2.json',"wt")
        file.write(ligne)
        file.close()
    end

    def mqtt_publish(scope,device)
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

        var stringdevice
        var channel  
        var consojson
        var ligne
        if device == 1 
            consojson = self.consojson1
            stringdevice = string.format("%s",global.device1)
          if global.configjson[global.device1]["produit"] == "PWX4"
                channel=0
            else
                channel=2
            end
        else
            stringdevice = string.format("%s",global.device2)
            consojson = self.consojson2
            if global.configjson[global.device2]["produit"] == "PWX4"
                channel=0
            else
                channel=2
            end
        end
        for i:0..channel
            if(scope=="hours")
                topic = string.format("gw/%s/%s/%s/tele/PWHOURS",global.client,global.ville,stringdevice+'-'+str(i))
                payload=consojson["hours"][i]["DATA"]
				ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWHOURS","DATA":%s}',stringdevice,global.configjson[stringdevice]["root"][i],json.dump(payload))
                mqtt.publish(topic,ligne,true)
                consojson["hours"][i]["DATA"][str(hour+1)]=0
            else
                topic = string.format("gw/%s/%s/%s/tele/PWHOURS",global.client,global.ville,stringdevice+'-'+str(i))
                payload=consojson["hours"][i]["DATA"]
                ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWHOURS","DATA":%s}',stringdevice,global.configjson[stringdevice]["root"][i],json.dump(payload))
                mqtt.publish(topic,ligne,true)
                consojson["hours"][i]["DATA"][str(0)]=0

                topic = string.format("gw/%s/%s/%s/tele/PWDAYS",global.client,global.ville,stringdevice+'-'+str(i))
                payload=consojson["days"][i]["DATA"]
                ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWDAYS","DATA":%s}',stringdevice,global.configjson[stringdevice]["root"][i],json.dump(payload))
                mqtt.publish(topic,ligne,true)
                if day == 6
                    consojson["days"][i]["DATA"]["Dim"]=0
                else
                    consojson["days"][i]["DATA"][str(self.day_list[day_of_week+1])]=0
                end
                topic = string.format("gw/%s/%s/%s/tele/PWMONTHS",global.client,global.ville,stringdevice+'-'+str(i))
                payload=consojson["months"][i]["DATA"]
                ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWMONTHS","DATA":%s}',stringdevice,global.configjson[stringdevice]["root"][i],json.dump(payload))																																								  
                mqtt.publish(topic,ligne,true)
                # RAZ next month if end of the month
                if(day==self.num_day_month[month])  # si dernier jour
                    if(month == 12) # decembre
                        consojson["months"][i]["DATA"]["Jan"]=0
                    else
                        consojson["months"][i]["DATA"][str(self.month_list[month+1])]
                    end
                end
            end
        end
        if device == 1 
            self.consojson1=consojson
        else
            self.consojson2=consojson
        end

	end
end

return conso()