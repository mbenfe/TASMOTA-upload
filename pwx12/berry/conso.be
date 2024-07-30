
class conso

    def init()
        import path
        if(path.exists('conso.sav'))
            print('chargement de la sauvegarde de consommation')
            var file
            file = open("conso.sav","rt")
            file.close()
        else
            print('creer fichier sauvegarde de consommation')
        end
    end

end

return conso