var version = "8.0.052026 versions"

import string
import global
import mqtt
import json
import gpio
import path

var device
var ville
var rst_out = 33
var rst_in = 19 
var bsl_in = 21

def mqttprint(texte)
    import mqtt
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", ville, device)
    mqtt.publish(topic, texte, true)
end

#-------------------------------- FONCTIONS -----------------------------------------#
def init()
    import json
    var file = open("esp32.cfg","rt")
    var buffer = file.read()
    file.close()
    var myjson=json.load(buffer)
    ville=myjson["ville"]
    device=myjson["device"]
    global.statistic_pin=14
    global.ready_pin=27
    gpio.pin_mode(global.statistic_pin,gpio.OUTPUT)
    gpio.pin_mode(global.ready_pin,gpio.OUTPUT)
    gpio.pin_mode(rst_out,gpio.OUTPUT)
    gpio.pin_mode(rst_in,gpio.OUTPUT)
    gpio.pin_mode(bsl_in,gpio.OUTPUT)
    gpio.digital_write(global.statistic_pin, 0)
    gpio.digital_write(global.ready_pin,1)
    gpio.digital_write(rst_out, 1)
    gpio.digital_write(rst_in, 1)
    gpio.digital_write(bsl_in, 0)

    # UART is owned by native C++ SNX driver
    # global.ser=serial(17,16,921600,serial.SERIAL_8N1)
    # global.ser.flush()

end

def mqttprint(texte)
    import mqtt
    var topic = string.format("gw/inter/%s/%s/tele/PRINT",ville,device)
    mqtt.publish(topic,texte,true)
end

#-------------------------------- COMMANDES -----------------------------------------#

def getfile(cmd, idx, payload, payload_json)
    import string
    import path
    var message
    var nom_fichier = string.split(payload, '/').pop()

    tasmota.cmd("hold")

    mqttprint(nom_fichier)
    var filepath = 'https://raw.githubusercontent.com/mbenfe/upload/main/' + payload
    mqttprint(filepath)

    var wc = webclient()
    if (wc == nil)
        mqttprint("Erreur: impossible d'initialiser le client web")
        tasmota.cmd("start")
        tasmota.resp_cmnd("Erreur d'initialisation du client web.")
        return
    end

    wc.set_follow_redirects(true)
    wc.begin(filepath)
    var st = wc.GET()
    if (st != 200)
        message = "Erreur: code HTTP " + str(st)
        mqttprint(message)
        tasmota.resp_cmnd("Erreur de telechargement.")
        wc.close()
        tasmota.cmd("start")
        return
    end

    var bytes_written = wc.write_file(nom_fichier)
    wc.close()
    mqttprint('Fetched ' + str(bytes_written))
    message = 'uploaded:' + nom_fichier
    tasmota.cmd("start")
    tasmota.resp_cmnd(message)
    return st
end

def dir(cmd, idx,payload, payload_json)
    import path
    var selector = ""
    if payload != nil
        selector = string.tolower(payload)
    end

    var want_all = (selector == "" || selector == "*.*" || selector == "all")
    var want_be = (want_all || selector == "*.be" || selector == ".be" || selector == "be")
    var want_hex = (want_all || selector == "*.hex" || selector == ".hex" || selector == "hex")
    var want_bin = (want_all || selector == "*.bin" || selector == ".bin" || selector == "bin")
    var want_json = (want_all || selector == "*.json" || selector == ".json" || selector == "json")

    if !want_be && !want_hex && !want_bin && !want_json
        mqttprint("dir: unknown filter '" + selector + "' (use *.be|*.hex|*.bin|*.json)")
        tasmota.resp_cmnd("invalid dir filter")
        return
    end

    var liste
    var file
    var taille
    var timestamp
    var matched = 0
    liste = path.listdir("/")
    mqttprint("dir: filter='" + selector + "'")
    for i:0..(liste.size()-1)
        var name_lc = string.tolower(liste[i])
        var match = want_all
        if !match
            if want_be && string.endswith(name_lc, ".be")
                match = true
            elif want_hex && string.endswith(name_lc, ".hex")
                match = true
            elif want_bin && string.endswith(name_lc, ".bin")
                match = true
            elif want_json && string.endswith(name_lc, ".json")
                match = true
            end
        end

        if match
            file = open(liste[i],"r")
            if file != nil
                taille = file.size()
                file.close()
                timestamp = path.last_modified(liste[i])
                mqttprint(liste[i] + ' ' + tasmota.time_str(timestamp) + ' ' + str(taille))
                matched += 1
            end
        end
    end
    mqttprint(str(matched) + " fichiers")
    tasmota.resp_cmnd_done()
end

def del_file(cmd, idx, payload, payload_json)
    import path
    var filename = payload

    if filename == nil || filename == ""
        tasmota.resp_cmnd("usage: del <filename>")
        return
    end

    if string.find(filename, "*") != -1 || string.find(filename, "?") != -1
        tasmota.resp_cmnd("wildcards not allowed")
        return
    end

    if string.find(filename, "/") != -1 || string.find(filename, "\\") != -1
        tasmota.resp_cmnd("strict filename only")
        return
    end

    if !path.exists(filename)
        tasmota.resp_cmnd("file not found")
        return
    end

    path.remove(filename)
    if path.exists(filename)
        tasmota.resp_cmnd("delete failed")
    else
        tasmota.resp_cmnd("deleted:" + filename)
    end
end

def launch_driver()
    mqttprint('mqtt connected -> launch driver')
    tasmota.load('snx_driver.be')
    tasmota.cmd("start")
    mqttprint('AUTOEXEC: start sent to STM32')
 end

def update(cmd, idx, payload, payload_json)
    var selector = ""
    if payload != nil
        selector = string.tolower(payload)
    end

    var want_all = (selector == "" || selector == "*.*" || selector == "all")
    var want_be = (want_all || selector == "*.be" || selector == ".be" || selector == "be")
    var want_hex = (want_all || selector == "*.hex" || selector == ".hex" || selector == "hex")
    var want_bin = (want_all || selector == "*.bin" || selector == ".bin" || selector == "bin")
    var want_json = (want_all || selector == "*.json" || selector == ".json" || selector == "json")

    if !want_be && !want_hex && !want_bin && !want_json
        mqttprint("update: unknown filter '" + selector + "' (use *.be|*.hex|*.bin|*.json)")
        tasmota.resp_cmnd("invalid update filter")
        return
    end

    mqttprint("update: start")
    tasmota.cmd("hold")

    var app_file = string.format("snx/apps/auto_%s.bin", ville)
    var to_fetch = []

    if want_be
        to_fetch.push("snx/berry/autoexec.be")
        to_fetch.push("snx/berry/snx_driver.be")
        to_fetch.push("snx/berry/flasher.be")
        to_fetch.push("snx/berry/intelhex.be")
        to_fetch.push("snx/berry/bootflasher.be")
    end

    if want_json
        to_fetch.push("snx/berry/config_cout.json")
    end

    if want_hex
        to_fetch.push("snx/H7/H7-bootloader.hex")
    end

    if want_bin
        to_fetch.push(app_file)
        to_fetch.push("snx/c031/modbus_chip_flashed.bin")
        to_fetch.push("snx/c031/lonworks_chip_flashed.bin")
        to_fetch.push("snx/c031/mbjc_chip_flashed.bin")
    end

    mqttprint("update: filter='" + selector + "' files=" + str(to_fetch.size()))
    for i:0..to_fetch.size()-1
        mqttprint("update: getfile " + to_fetch[i])
        tasmota.cmd("getfile " + to_fetch[i])
    end

    tasmota.cmd("start")
    mqttprint("update: done")
    tasmota.resp_cmnd_done()
end


def setmode(cmd, idx, payload, payload_json)
    if global.stm32 == nil
        tasmota.resp_cmnd("driver not ready")
        return
    end

    var requested = ""
    if payload != nil
        requested = string.tolower(str(payload))
    end

    if requested == ""
        tasmota.resp_cmnd("mode=" + global.stm32.get_publish_mode())
        return
    end

    var set_to = global.stm32.set_publish_mode(requested)
    if set_to == nil
        tasmota.resp_cmnd("invalid mode: " + requested + " (standard|error|debug|log|danfosslog|danfoss|consign)")
        return
    end

    mqttprint("publish mode=" + set_to)
    tasmota.resp_cmnd("mode=" + set_to)
end

def sendsimu(cmd, idx, payload, payload_json)
    if global.ser == nil
        tasmota.resp_cmnd("serial not ready")
        return
    end

    var sim_file = string.format("simulation_%s.json", ville)
    var file = open(sim_file, "rt")
    if file == nil
        tasmota.resp_cmnd("missing file: " + sim_file)
        return
    end

    var raw = file.read()
    file.close()
    var sim = json.load(raw)
    if sim == nil
        tasmota.resp_cmnd("invalid json: " + sim_file)
        return
    end

    var sent = 0
    gpio.pin_mode(global.ready_pin, gpio.OUTPUT)
    gpio.digital_write(global.ready_pin, 0)

    global.ser.write(bytes().fromstring("dummy"))
    tasmota.delay(20)
    var last_id = -1
    while true
        var next_key = nil
        var next_id = 2147483647
        for k: sim.keys()
            var kid = int(k)
            if kid > last_id && kid < next_id
                next_id = kid
                next_key = k
            end
        end

        if next_key == nil
            break
        end

        var id = next_key
        last_id = next_id
        var entry = sim[id]
        if entry != nil && entry.contains("DATA") && entry["DATA"] != nil
            var line = string.format("simu %s", str(id))
            var data = entry["DATA"]
            for k: data.keys()
                line += string.format(":%s:%s", str(k), str(data[k]))
            end
            var frame = bytes().fromstring(line)
            # global.ser.flush()
            global.ser.write(frame)
            tasmota.delay(20)
            sent += 1
        end
    end
    gpio.digital_write(global.ready_pin, 1)

    tasmota.resp_cmnd(string.format("sendsimu sent %s frames from %s", str(sent), sim_file))
end

def snxhelp(cmd, idx, payload, payload_json)
    mqttprint("=== Generic autoexec commands (Berry) ===")
    mqttprint("Stm32Reset [out|in] : pulse reset pins for STM32 out/in")
    mqttprint("getfile <repo/path/file> : download file from GitHub upload repo")
    mqttprint("dir [*.be|*.hex|*.bin|*.json] : list local files with optional filter")
    mqttprint("del <filename> : delete one local file (strict filename, no wildcard)")
    mqttprint("getversion : show versions of berry scripts and H7/C031 firmware")
    mqttprint("update [*.be|*.hex|*.bin|*.json] : fetch selected update files")

    mqttprint("=== Embedded C++ SNX driver commands ===")
    mqttprint("hold : send 'hold' over UART to pause the external STM32")
    mqttprint("start : send 'start' over UART to resume the external STM32")
    mqttprint("statistic : send 's' over UART (request statistics)")
    mqttprint("mapstatistic : send 'm' over UART (request map statistics)")
    mqttprint("stm32mode <log|debug> : send 'ml' or 'md' over UART")
    mqttprint("sendsimu : reserved by C++ driver (not implemented yet)")
    mqttprint("snxstatus : show C++ runtime counters (queue/drops/published)")
    mqttprint("snxsend <text> : send raw text over UART from C++ driver")

    mqttprint("=== Notes ===")
    mqttprint("UART capture + MQTT telemetry publish are handled by C++ driver")
    mqttprint("snx_driver.be is loaded only for non-fastloop/non-50ms logic")
    tasmota.resp_cmnd_done()
end




#-------------------------------- BASH -----------------------------------------#
tasmota.cmd("seriallog 0")
mqttprint("serial log disabled")

tasmota.add_cmd('getfile',getfile)

tasmota.add_cmd('dir',dir)

tasmota.add_cmd('del',del_file)

tasmota.add_cmd('update',update)
tasmota.add_cmd('snxhelp',snxhelp)


init()
mqttprint('load snx_driver & loader')
mqttprint('wait for 5 seconds ....')
tasmota.set_timer(5000,launch_driver)

