
class conso

    def init()
        var file
        file = open('conso.sav','rt')
        if file.size()==0
            print('fichier non existant')
        end
    end

end

return conso