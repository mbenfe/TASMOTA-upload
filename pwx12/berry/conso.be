import json
import string


class conso

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
            print(configjson)
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