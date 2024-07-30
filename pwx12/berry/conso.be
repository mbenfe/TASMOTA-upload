import json
import string


class conso
    var consojson

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
        print('creation du fichier de sauvegarde de la consommation....')
        var file = open('esp32.cfg','rt')
        var ligne = file.read()
        var esp32json = json.load(ligne)
        file.close()
        var name = string.format('p_%s.json',esp32json['ville'])
        print('lecture du fichier ',name)
        import path
        if(path.exists(name))
            file = open(name,'rt')
            ligne = file.read()
            file.close()
            var configjson=json.load(ligne)
            var device = esp32json['device']
            print(configjson[device])
            if configjson[device]['produit']=='PWX12'
                ligne = string.format('{"hours":[]}')
                var mainjson = json.load(ligne)
                mainjson.insert('days',[])
                mainjson.insert('months')
                print('configuration PWX12')
                for i:0..2
                    if configjson[device]['mode'][i]=='tri'
                        ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWHOURS","DATA":%s}',device,configjson[device]['root'][i],self.get_hours())
                        mainjson['hours'].insert(i,json.load(ligne))
                        ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWDAYS","DATA":%s}',device,configjson[device]['root'][i],self.get_days())
                        mainjson['days'].insert(i,json.load(ligne))
                        ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWMONTHS","DATA":%s}',device,configjson[device]['root'][i],self.get_months())
                        mainjson['days'].insert(i,json.load(ligne))
                    else
                    end
                end
                ligne = json.dump(mainjson)
                return ligne
            else
                print('configuration PWX4')
                return ''
            end
        end
    end

    def init()
        import path
        var ligne
        var file
        if(path.exists('conso.json'))
            print('chargement de la sauvegarde de consommation')
            file = open("conso.json","rt")
            ligne = file.read()
            self.consojson= json.load(ligne)
            print(self.consojson)
            file.close()
        else
            ligne = self.init_conso()
            file = open('conso.json','wt')
            file.write(ligne)
            file.close()
            print('fichier sauvegarde de consommation cree !')
        end
    end

    def update(data)
        var day_list = ["Dim","Lun","Mar","Mer","Jeu","Ven","Sam"]
        var month_list = ["","Jan","Fev","Mars","Avr","Mai","Juin","Juil","Aout","Sept","Oct","Nov","Dec"]
        var rtc = tasmota.rtc()

        # Extract the hour, day of the month, and day of the week
        var second = rtc['second']
        var minute = rtc['minute']
        var hour = rtc['hour']
        var day = rtc['day']
        var month = rtc['month']
        var year = rtc['year']
        var day_of_week = rtc['wday']  # 0=Sunday, 1=Monday, ..., 6=Saturday
        print(year+'/'+month+'/'+day+' '+day_list[day_of_week]+' '+hour+':'+minute+':'+second)
    end

end

return conso()