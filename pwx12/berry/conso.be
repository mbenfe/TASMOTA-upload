import json
import string


class conso

    def init_conso()
        var file = open('esp32.cfg','rt')
        var ligne = file.read()
        var esp32json = json.load(ligne)
        file.close()
        var name = string.format('p_%s',esp32json['ville'])
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
            print('creer fichier sauvegarde de consommation')
        end
    end

end

return conso()