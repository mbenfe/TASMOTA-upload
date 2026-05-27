var version = "1.1.0 avec couts par semaine"
import json
import string
import mqtt
import global

class conso
    var consojson
    var week_couts_json
    var coutjson
    var day_list
    var month_list
    var num_day_month
    var cout

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

    def init_cout()
        var name = string.format("c_%s.json", global.ville)
        var file = open(name, "rt")
        var ligne = file.read()
        file.close()
        global.coutjson = json.load(ligne)
        self.cout = map()
        name = string.format("c_%s", global.configjson[global.device]["root"][0])
        self.cout.insert(name, 0)
    end

    def calcul_cout(month, day_of_week, myjson, chanel)
        var target
        var name
        var kwh
        var euros
        var heures_creuses
        var heures_pleines
        var hc_cout
        var hp_cout
        var saison

        var taxable

        var hp_cout_conso
        var hp_cout_acheminement
        var hp_cout_taxes

        var hc_cout_conso
        var hc_cout_acheminement
        var hc_cout_taxes

        heures_creuses = 0
        heures_pleines = 0
        for j:0..23
            if j >= global.coutjson["electricite"]["hc_debut"] || j < global.coutjson["electricite"]["hc_fin"]
                if myjson.contains(str(j))
                    heures_creuses += myjson[str(j)]
                end
            else
                if myjson.contains(str(j))
                    heures_pleines += myjson[str(j)]
                end
            end
        end
        heures_creuses /= 1000
        heures_pleines /= 1000
        if month >= global.coutjson["electricite"]["sh_debut"] || month <= global.coutjson["electricite"]["sh_fin"]
            saison = global.coutjson["electricite"]["sh"]
        else
            saison = global.coutjson["electricite"]["sb"]
        end

        taxable = (saison["hp_acheminement_cc"] + saison["hp_acheminement_cs"] + saison["hp_acheminement_cg"]) * heures_pleines
        taxable += (saison["hc_acheminement_cc"] + saison["hc_acheminement_cs"] + saison["hc_acheminement_cg"]) * heures_creuses

        # heures pleines
        hp_cout_conso = (saison["hp_tarif"] + saison["cee"] + saison["hp_obligation"]) * heures_pleines
        hp_cout_acheminement = (saison["hp_acheminement_cc"] + saison["hp_acheminement_cs"] + saison["hp_acheminement_cg"] + saison["hp_acheminement_conso"]) * heures_pleines

        if heures_pleines != 0
            hp_cout_taxes = taxable * saison["taxe_acheminement"] * (1 - real(heures_creuses) / real(heures_pleines)) + saison["hp_sp"] * heures_pleines
        else
            hp_cout_taxes = taxable * saison["taxe_acheminement"] + saison["hp_sp"] * heures_pleines
        end
        hp_cout = hp_cout_conso + hp_cout_acheminement + hp_cout_taxes
        # heures creuses
        hc_cout_conso = (saison["hc_tarif"] + saison["cee"] + saison["hc_obligation"]) * heures_creuses
        hc_cout_acheminement = (saison["hc_acheminement_cc"] + saison["hc_acheminement_cs"] + saison["hc_acheminement_cg"] + saison["hc_acheminement_conso"]) * heures_creuses

        if heures_pleines != 0
            hc_cout_taxes = taxable * saison["taxe_acheminement"] * real(heures_creuses) / real(heures_pleines) + saison["hc_sp"] * heures_creuses
        else
            hc_cout_taxes = taxable * saison["taxe_acheminement"] + saison["hc_sp"] * heures_creuses
        end
        hc_cout = hc_cout_conso + hc_cout_acheminement + hc_cout_taxes
        target = string.format("c_%s", chanel)
        self.cout[target] = hp_cout + hc_cout
        self.week_couts_json[self.day_list[day_of_week]] = hp_cout + hc_cout
    end

    def init_conso()
        var file
        var ligne
        var name = string.format("p_%s.json", global.ville)
        import path
        if path.exists(name)
            file = open(name, "rt")
            ligne = file.read()
            file.close()
            global.configjson = json.load(ligne)
            print(global.configjson[global.device])
            if global.configjson[global.device]["produit"] == "PWX4"
                ligne = string.format('{}')
                var mainjson = json.load(ligne)
                if global.configjson[global.device]["mode"] == "tri"
                    ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWHOURS","DATA":%s}', global.device, global.configjson[global.device]["root"][0], self.get_hours())
                    mainjson.insert("hours", json.load(ligne))
                    ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWDAYS","DATA":%s}', global.device, global.configjson[global.device]["root"][0], self.get_days())
                    mainjson.insert("days", json.load(ligne))
                    ligne = string.format('{"Device": "%s","Name":"%s","TYPE":"PWMONTHS","DATA":%s}', global.device, global.configjson[global.device]["root"][0], self.get_months())
                    mainjson.insert("months", json.load(ligne))
                end
                ligne = json.dump(mainjson)
                return ligne
            end
        else
            raise 'fichier configuration non existant:', str(name)
        end
    end

    def normalize_conso_schema()
        var changed = false

        if self.consojson.contains("hours") && type(self.consojson["hours"]) == "list"
            if size(self.consojson["hours"]) > 0
                self.consojson["hours"] = self.consojson["hours"][0]
                changed = true
            end
        end

        if self.consojson.contains("days") && type(self.consojson["days"]) == "list"
            if size(self.consojson["days"]) > 0
                self.consojson["days"] = self.consojson["days"][0]
                changed = true
            end
        end

        if self.consojson.contains("months") && type(self.consojson["months"]) == "list"
            if size(self.consojson["months"]) > 0
                self.consojson["months"] = self.consojson["months"][0]
                changed = true
            end
        end

        return changed
    end

    def init()
        import path

        var ligne
        var file
        var legacy_indexed_json = false
        var name = string.format("p_%s.json", global.ville)
        file = open(name, "rt")
        ligne = file.read()
        global.configjson = json.load(ligne)
        file.close()

        if path.exists("conso.json")
            file = open("conso.json", "rt")
            if file.size() != 0
                ligne = file.read()
                legacy_indexed_json = string.find(ligne, '"hours":[{') != -1 || string.find(ligne, '"days":[{') != -1 || string.find(ligne, '"months":[{') != -1
                self.consojson = json.load(ligne)
                print(self.consojson)
                file.close()
            else
                ligne = self.init_conso()
                file = open("conso.json", "wt")
                file.write(ligne)
                file.close()
                print("fichier sauvegarde de consommation cree !")
                print(ligne)
                self.consojson = json.load(ligne)
            end
        else
            ligne = self.init_conso()
            file = open("conso.json", "wt")
            file.write(ligne)
            file.close()
            print("fichier sauvegarde de consommation cree !")
            print(ligne)
            self.consojson = json.load(ligne)
        end

        var normalized_in_init = self.normalize_conso_schema()
        if !normalized_in_init && legacy_indexed_json
            print("CONSO init: forcing indexed migration from raw file signature")
            if self.consojson.contains("hours") && size(self.consojson["hours"]) > 0
                self.consojson["hours"] = self.consojson["hours"][0]
                normalized_in_init = true
            end
            if self.consojson.contains("days") && size(self.consojson["days"]) > 0
                self.consojson["days"] = self.consojson["days"][0]
                normalized_in_init = true
            end
            if self.consojson.contains("months") && size(self.consojson["months"]) > 0
                self.consojson["months"] = self.consojson["months"][0]
                normalized_in_init = true
            end
        end

        print("CONSO init: normalize changed=" + str(normalized_in_init))

        if normalized_in_init
            file = open("conso.json", "wt")
            ligne = json.dump(self.consojson)
            file.write(ligne)
            file.close()

            file = open("conso.json", "rt")
            ligne = file.read()
            file.close()
            self.consojson = json.load(ligne)
            print("fichier sauvegarde de consommation converti sans index !")
        else
            print("CONSO init: schema already non-indexed")
        end

        self.day_list = ["Dim", "Lun", "Mar", "Mer", "Jeu", "Ven", "Sam"]
        self.month_list = ["", "Jan", "Fev", "Mars", "Avr", "Mai", "Juin", "Juil", "Aout", "Sept", "Oct", "Nov", "Dec"]
        self.num_day_month = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        self.init_cout()
        if path.exists("couts.json")
            file = open("couts.json", "rt")
            ligne = file.read()
            self.week_couts_json = json.load(ligne)
            file.close()
        else
            self.week_couts_json = json.load('{"Lun":0,"Mar":0,"Mer":0,"Jeu":0,"Ven":0,"Sam":0,"Dim":0}')
            file = open("couts.json", "wt")
            ligne = json.dump(self.week_couts_json)
            file.write(ligne)
            file.close()
            print("fichier sauvegarde des couts cree !")
        end
    end

    def update(data)
        if self.normalize_conso_schema()
            var migrated = json.dump(self.consojson)
            var migrated_file = open("conso.json", "wt")
            migrated_file.write(migrated)
            migrated_file.close()
            print("fichier sauvegarde de consommation converti sans index (runtime) !")
        end

        var split = string.split(data, ":")
        if size(split) < 2
            return
        end

        if split[0] != "C"
            return
        end

        var now = tasmota.rtc()
        var rtc = tasmota.time_dump(now["local"])
        var hour = rtc["hour"]
        var month = rtc["month"]
        var year = rtc["year"]
            var day_of_week = rtc["weekday"] % 7

        # Vérification de l'année bissextile
        if month == 2  # Si c'est février
            if (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
                self.num_day_month[2] = 29  # Année bissextile, février a 29 jours
            else
                self.num_day_month[2] = 28  # Année non bissextile, février a 28 jours
            end
        end

        var delta = real(split[1])
        self.consojson["hours"]["DATA"][str(hour)] += delta
        self.consojson["days"]["DATA"][self.day_list[day_of_week]] += delta
        self.consojson["months"]["DATA"][self.month_list[month]] += delta
    end

    def sauvegarde()
        var ligne = json.dump(self.consojson)
        var file = open("conso.json", "wt")
        file.write(ligne)
        file.close()
        ligne = json.dump(self.week_couts_json)
        file = open("couts.json", "wt")
        file.write(ligne)
        file.close()
    end

    def mqtt_publish(scope)
        var now = tasmota.rtc()
        var rtc = tasmota.time_dump(now["local"])
        var hour = rtc["hour"]
        var day = rtc["day"]
        var month = rtc["month"]
            var day_of_week = rtc["weekday"] % 7
        var topic
        var payload_hours
        var payload_days
        var payload_months
        var payload_week
        var ligne

        # Cron runs at 23:59, so costs belong to current weekday
        var day_for_cost = day_of_week

        var stringdevice
        stringdevice = string.format("%s", global.device)
        var channel_name = global.configjson[global.device]["root"][0]
        if scope == "hours" && channel_name != "*"
            topic = string.format("gw/%s/%s/%s/tele/PWHOURS", global.client, global.ville, stringdevice)
            payload_hours = self.consojson["hours"]["DATA"]
            ligne = string.format('{"Device": "%s","Name":"%s_H","TYPE":"PWHOURS","DATA":%s}', global.device, channel_name, json.dump(payload_hours))
            mqtt.publish(topic, ligne, true)
            self.consojson["hours"]["DATA"][str((hour + 1) % 24)] = 0
        elif channel_name != "*"
            # Calculate current day's cost first (before resetting hour 0)
            self.calcul_cout(month, day_for_cost, self.consojson["hours"]["DATA"], channel_name)
            
            # THEN publish hours
            topic = string.format("gw/%s/%s/%s/tele/PWHOURS", global.client, global.ville, stringdevice)
            payload_hours = self.consojson["hours"]["DATA"]
            ligne = string.format('{"Device": "%s","Name":"%s_H","TYPE":"PWHOURS","DATA":%s}', global.device, channel_name, json.dump(payload_hours))
            mqtt.publish(topic, ligne, true)
            self.consojson["hours"]["DATA"][str(0)] = 0

            # Publish days
            topic = string.format("gw/%s/%s/%s/tele/PWDAYS", global.client, global.ville, stringdevice)
            payload_days = self.consojson["days"]["DATA"]
            ligne = string.format('{"Device": "%s","Name":"%s_D","TYPE":"PWDAYS","DATA":%s}', global.device, channel_name, json.dump(payload_days))
            mqtt.publish(topic, ligne, true)
            self.consojson["days"]["DATA"][self.day_list[(day_of_week + 1) % 7]] = 0
            
            # Publish months
            topic = string.format("gw/%s/%s/%s/tele/PWMONTHS", global.client, global.ville, stringdevice)
            payload_months = self.consojson["months"]["DATA"]
            ligne = string.format('{"Device": "%s","Name":"%s_M","TYPE":"PWMONTHS","DATA":%s}', global.device, channel_name, json.dump(payload_months))
            mqtt.publish(topic, ligne, true)
            
            # RAZ next month if end of the month
            if day == self.num_day_month[month]
                if month == 12
                    self.consojson["months"]["DATA"]["Jan"] = 0
                else
                    self.consojson["months"]["DATA"][self.month_list[month + 1]] = 0
                end
            end
        end

        # Publish costs
        channel_name = global.configjson[global.device]["root"][0]
        if scope != "hours" && channel_name != "*"
            var cost_key = string.format("c_%s", channel_name)

            # Cost of current day (cron runs at 23:59)
            topic = string.format("gw/%s/%s/%s/tele/COUT", global.client, global.ville, global.device)
            ligne = string.format('{"Device": "%s","Name":"%s", "surface":%d,"cout":%.2f,"jour":"%s"}', 
                global.device, cost_key, global.coutjson['surface'], self.cout[cost_key], self.day_list[day_for_cost])
            mqtt.publish(topic, ligne, true)

            # Week costs
            topic = string.format("gw/%s/%s/%s/tele/COUTS", global.client, global.ville, global.device)
            payload_week = self.week_couts_json
            ligne = string.format('{"Device": "%s","Name":"c_w_%s","Lun":%.2f,"Mar":%.2f,"Mer":%.2f,"Jeu":%.2f,"Ven":%.2f,"Sam":%.2f,"Dim":%.2f}', 
                global.device, channel_name, payload_week["Lun"], payload_week["Mar"], payload_week["Mer"], payload_week["Jeu"], payload_week["Ven"], payload_week["Sam"], payload_week["Dim"])
            mqtt.publish(topic, ligne, true)
        end
    end
end

return conso()