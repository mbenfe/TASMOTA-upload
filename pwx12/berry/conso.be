import json
import string


class conso

    def get_hours()
        var ligne
        ligne = string.format("{'0':0,'1':0,'2':0,'3':0,'4':0,'5':0,'6':0,'7':0,'8':0,'9':0,'10':0,'11':0,'12':0,'13':0,'14':0,'15':0,'16':0,'17':0,'18':0,'19':0,'20':0,'21':0,'22':0,'23':0}")
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
            var configjson=json.load(ligne)
            var device = esp32json['device']
            print(configjson[device])
            if configjson[device]['produit']=='PWX12'
                print('configuration PWX12')
                for i:0..3
                    if configjson[device]['mode'][i]=='tri'
                        ligne = string.format("Device: '%s','Name':'%s','TYPE':'PWHOURS','DATA':%s}\n",device,configjson[device]['root'][i],self.gethours())
                        print(ligne)
                    else
                    end
                end
            else
                print('configuration PWX4')
            end
            file.close()
        end
    end

    def init()
        import path
        if(path.exists('conso.json'))
            print('chargement de la sauvegarde de consommation')
            var file
            file = open("conso.json","rt")
            file.close()
        else
            self.init_conso()
            print('fichier sauvegarde de consommation cree !')
        end
    end

end

return conso()