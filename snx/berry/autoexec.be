var version = "1.0.032026 flasher"

import string
import global
import mqtt
import json
import gpio
import path

var device
var ville

def mqttprint(texte)
    import mqtt
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", ville, device)
    mqtt.publish(topic, texte, true)
end

var rst_out=33
var bsl_out=32   

# keep STM32 OUT in reset from boot start
gpio.pin_mode(rst_out,gpio.OUTPUT)
gpio.pin_mode(bsl_out,gpio.OUTPUT)
gpio.digital_write(bsl_out, 0)
gpio.digital_write(rst_out, 0)

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
 
    gpio.digital_write(global.statistic_pin, 0)
    gpio.digital_write(global.ready_pin,1)

    gpio.pin_mode(rst_out,gpio.OUTPUT)
    gpio.pin_mode(bsl_out,gpio.OUTPUT)
    gpio.digital_write(bsl_out, 0)
    gpio.digital_write(rst_out, 0)

    global.ser=serial(17,16,921600,serial.SERIAL_8N1)

end

def mqttprint(texte)
    import mqtt
    var topic = string.format("gw/inter/%s/%s/tele/PRINT",ville,device)
    mqtt.publish(topic,texte,true)
end

#-------------------------------- COMMANDES -----------------------------------------#
def Stm32Reset()
    if global.stm32 != nil
        global.stm32.stm32reset()
    else
        # Driver not loaded yet: fallback to OUT-only reset.
        gpio.digital_write(rst_out, 0)
        tasmota.delay(100)
        gpio.digital_write(rst_out, 1)
        tasmota.delay(100)
    end
    tasmota.resp_cmnd('STM32 OUT reset')
end

def hold()
    gpio.pin_mode(rst_out, gpio.OUTPUT)
    gpio.pin_mode(bsl_out, gpio.OUTPUT)
    gpio.digital_write(bsl_out, 0)
    gpio.digital_write(rst_out, 0)
    tasmota.resp_cmnd("done")
end

def start()
    gpio.pin_mode(rst_out, gpio.OUTPUT)
    gpio.pin_mode(bsl_out, gpio.OUTPUT)
    gpio.digital_write(bsl_out, 0)
    gpio.digital_write(rst_out, 1)
    tasmota.resp_cmnd("done")
end

def getfile(cmd, idx, payload, payload_json)
    import string
    import path
    var message
    var nom_fichier = string.split(payload, '/').pop()

    hold()

    mqttprint(nom_fichier)
    var filepath = 'https://raw.githubusercontent.com/mbenfe/upload/main/' + payload
    mqttprint(filepath)

    var wc = webclient()
    if (wc == nil)
        mqttprint("Erreur: impossible d'initialiser le client web")
        start()
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
        start()
        return
    end

    var bytes_written = wc.write_file(nom_fichier)
    wc.close()
    mqttprint('Fetched ' + str(bytes_written))
    message = 'uploaded:' + nom_fichier
    start()
    tasmota.resp_cmnd(message)
    return st
end

def dir(cmd, idx,payload, payload_json)
    import path
    var liste
    var file
    var taille
    var date
    var timestamp
    liste = path.listdir("/")
    mqttprint(str(liste.size())+" fichiers")
    for i:0..(liste.size()-1)
        file = open(liste[i],"r")
        taille = file.size()
        file.close()
        timestamp = path.last_modified(liste[i])
        mqttprint(liste[i]+' '+tasmota.time_str(timestamp)+' '+str(taille))
    end
    tasmota.resp_cmnd_done()
end

def launch_driver()
    mqttprint('mqtt connected -> launch driver')
    tasmota.load('snx_driver.be')
    gpio.digital_write(rst_out, 1)
    mqttprint('AUTOEXEC: STM32 OUT reset released')
 end

 def getversion()
    var fichier
    var files = path.listdir("/")
    for i:0..files.size()-1
        if string.endswith(files[i],".be")
            fichier = open(files[i], "r")
            var content = fichier.readline()
            var version_match = string.find(content, 'var version')
            if version_match != -1
                var liste = string.split(content,' ')
                mqttprint(files[i] + " version: " + liste[3])
            else
                mqttprint(files[i] + " version: undefined version")
            end
            fichier.close()
        end
    end
    tasmota.resp_cmnd_done()
end

def update()
    mqttprint("update: start")
    hold()

    mqttprint("update: getfile snx/berry/autoexec.be")
    tasmota.cmd("getfile snx/berry/autoexec.be")

    mqttprint("update: getfile snx/berry/snx_driver.be")
    tasmota.cmd("getfile snx/berry/snx_driver.be")

    mqttprint("update: getfile flashers/stm32H743-SNX/flasher.be")
    tasmota.cmd("getfile flashers/stm32H743-SNX/flasher.be")

    mqttprint("update: getfile flashers/stm32H743-SNX/intelhex.be")
    tasmota.cmd("getfile flashers/stm32H743-SNX/intelhex.be")

    start()
    mqttprint("update: done")
end

def statistic()
    if global.ser == nil
        tasmota.resp_cmnd("serial not ready")
        return
    end
    var mybytes = bytes().fromstring("s")
    global.ser.flush()
    global.ser.write(mybytes)
    tasmota.resp_cmnd("s sent")
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




#-------------------------------- BASH -----------------------------------------#
tasmota.cmd("seriallog 0")
mqttprint("serial log disabled")

mqttprint('AUTOEXEC: create commande Stm32Reset')
tasmota.add_cmd('Stm32reset',Stm32Reset)
tasmota.add_cmd('hold',hold)
tasmota.add_cmd('start',start)

mqttprint('AUTOEXEC: create commande getfile')
tasmota.add_cmd('getfile',getfile)

tasmota.add_cmd('dir',dir)

tasmota.add_cmd('getversion',getversion)
tasmota.add_cmd('update',update)
tasmota.add_cmd('statistic',statistic)
tasmota.add_cmd('set',setmode)


init()
mqttprint('load snx_driver & loader')
mqttprint('wait for 5 seconds ....')
tasmota.set_timer(5000,launch_driver)

