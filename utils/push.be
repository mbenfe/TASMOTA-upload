# push_v2.be
# Complete upload: check/create directory + upload files via WebDAV
# Uses Mem1 for password storage (no secrets in code)

import json
import string
import path

# ================== CONFIG ==================
var BASE_URL   = "http://malek4b.synology.me:5000"
var WEBDAV_HOST = "malek4b.synology.me"
var WEBDAV_PORT = 5005
var SHARE_NAME = "webdav"
var ROOT_FIXED = "tasmotafs"
var USERNAME   = "tasmota"

# Password retrieved from Mem1 (set once: Mem1 PushToulouse#86)
var PASSWORD = tasmota.cmd("Mem1")["Mem1"]

# WebDAV Basic Auth computed at runtime
var AUTH_BASIC = ""

# Loaded from esp32.cfg
var ville = ""
var device = ""
# ============================================

def step(msg)
    print("-> " + msg)
end

def ok(msg)
    print("  OK: " + msg)
end

def fail(msg, detail)
    print("X ERREUR: " + msg)
    if detail != nil
        print("  " + str(detail))
    end
end

def url_encode(texte)
    var result = ""
    var i = 0
    while i < size(texte)
        var ch = texte[i]
        var b = bytes().fromstring(ch)
        var code = b[0]
        
        if (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || code == 45 || code == 46 || code == 95 || code == 126
            result += ch
        else
            result += format("%%%02X", code)
        end
        i += 1
    end
    return result
end

def base64_encode(text)
    var b64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var input_bytes = bytes().fromstring(text)
    var result = ""
    var i = 0
    
    while i < size(input_bytes)
        var b1 = input_bytes[i]
        var b2 = (i + 1 < size(input_bytes)) ? input_bytes[i + 1] : 0
        var b3 = (i + 2 < size(input_bytes)) ? input_bytes[i + 2] : 0
        
        var n = (b1 << 16) | (b2 << 8) | b3
        
        result += b64[(n >> 18) & 0x3F]
        result += b64[(n >> 12) & 0x3F]
        result += (i + 1 < size(input_bytes)) ? b64[(n >> 6) & 0x3F] : "="
        result += (i + 2 < size(input_bytes)) ? b64[n & 0x3F] : "="
        
        i += 3
    end
    
    return result
end

def init_auth()
    AUTH_BASIC = "Basic " + base64_encode(USERNAME + ":" + PASSWORD)
end

# ============================================
# PART 1: Directory Check (from dir_check.be)
# ============================================

def login_synology()
    step("Connexion a l'API Synology (File Station)")
    
    var encoded_user = url_encode(USERNAME)
    var encoded_pass = url_encode(PASSWORD)
    
    var url = BASE_URL + "/webapi/auth.cgi"
    url += "?api=SYNO.API.Auth"
    url += "&version=6"
    url += "&method=login"
    url += "&account=" + encoded_user
    url += "&passwd=" + encoded_pass
    url += "&session=FileStation"
    url += "&format=sid"
    
    var client = webclient()
    client.set_timeouts(30000)
    client.begin(url)
    
    var status = client.GET()
    var resp = client.get_string()
    client.close()
    
    if status != 200
        fail("HTTP login echoue", "HTTP " + str(status))
        return nil
    end
    
    if resp == nil || resp == ""
        fail("Login reponse vide", nil)
        return nil
    end
    
    var json_data = json.load(resp)
    if json_data == nil || !json_data["success"]
        fail("Login Synology echoue", resp)
        return nil
    end
    
    var sid = json_data["data"]["sid"]
    ok("Login")
    return sid
end

def fs_folder_exists(sid, folder_path)
    var encoded_path = url_encode(folder_path)
    
    var url = BASE_URL + "/webapi/entry.cgi"
    url += "?_sid=" + sid
    url += "&api=SYNO.FileStation.List"
    url += "&version=2"
    url += "&method=list"
    url += "&folder_path=" + encoded_path
    
    var client = webclient()
    client.set_timeouts(30000)
    client.begin(url)
    
    var status = client.GET()
    var resp = client.get_string()
    client.close()
    
    if status != 200
        return false
    end
    
    if resp == nil || resp == ""
        return false
    end
    
    var json_data = json.load(resp)
    if json_data != nil && json_data["success"]
        return true
    end
    
    return false
end

def fs_create_folder(sid, parent_path, name)
    var encoded_parent = url_encode(parent_path)
    var encoded_name   = url_encode(name)
    
    var url = BASE_URL + "/webapi/entry.cgi"
    url += "?_sid=" + sid
    url += "&api=SYNO.FileStation.CreateFolder"
    url += "&version=2"
    url += "&method=create"
    url += "&folder_path=" + encoded_parent
    url += "&name=" + encoded_name
    url += "&force_parent=true"
    
    var client = webclient()
    client.set_timeouts(30000)
    client.begin(url)
    
    var status = client.GET()
    client.close()
    
    if status != 200
        return false
    end
    
    return true
end

def ensure_target_directory(sid)
    var full_path = "/" + SHARE_NAME + "/" + ROOT_FIXED + "/" + ville + "/" + device
    step("Verifier repertoire")
    
    if !fs_folder_exists(sid, full_path)
        fs_create_folder(sid, "/" + SHARE_NAME + "/" + ROOT_FIXED + "/" + ville, device)
    end
    
    ok("Repertoire pret")
end

# ============================================
# PART 2: WebDAV Upload (from push_fs.be)
# ============================================

def build_put_request(path_http, content_bytes)
    var body_len = size(content_bytes)
    var req = bytes()

    var header = ""
    header += "PUT " + path_http + " HTTP/1.1\r\n"
    header += "Host: " + WEBDAV_HOST + ":" + str(WEBDAV_PORT) + "\r\n"
    header += "Authorization: " + AUTH_BASIC + "\r\n"
    header += "Content-Length: " + str(body_len) + "\r\n"
    header += "Connection: close\r\n"
    header += "Content-Type: application/octet-stream\r\n"
    header += "\r\n"

    req += bytes().fromstring(header)
    req += content_bytes
    return req
end

def upload_one_file(local_path)
    var file = open(local_path, "rb")
    if file == nil
        fail("Impossible de lire le fichier", local_path)
        return false
    end
    var content = file.readbytes()
    file.close()

    var fname = local_path
    if size(fname) > 0 && fname[0..0] == "/"
        fname = fname[1..]
    end

    var fname_enc = url_encode(fname)
    var http_path = "/webdav/" + ROOT_FIXED + "/" + ville + "/" + device + "/" + fname_enc

    var req = build_put_request(http_path, content)

    var tcp = tcpclient()
    var ok_conn = tcp.connect(WEBDAV_HOST, WEBDAV_PORT, 30000)
    if !ok_conn
        fail("Connexion TCP échouée", WEBDAV_HOST + ":" + str(WEBDAV_PORT))
        tcp.close()
        return false
    end

    var sent = tcp.write(req)
    if sent != size(req)
        fail("Echec d'envoi complet", "envoyé=" + str(sent) + " / total=" + str(size(req)))
        tcp.close()
        return false
    end

    var wait_ms = 0
    while wait_ms < 5000 && tcp.available() == 0
        tasmota.delay(100)
        wait_ms += 100
    end

    var resp = tcp.read()
    tcp.close()

    if resp == nil || resp == ""
        fail("Pas de réponse HTTP", fname)
        return false
    end

    var pos = string.find(resp, "\r\n", 0)
    var status_line = resp
    if pos >= 0
        status_line = resp[0..pos-1]
    end

    if string.find(status_line, " 200 ") >= 0 || string.find(status_line, " 201 ") >= 0 || string.find(status_line, " 204 ") >= 0
        ok(fname)
        return true
    end

    fail("Upload HTTP non OK", status_line)
    return false
end

def upload_all_files()
    step("Upload fichiers")
    
    var files = path.listdir("/")
    if files == nil
        files = []
    end
    
    var uploaded = 0
    var skipped = 0
    
    for filename : files
        var filepath = "/" + filename
        if !path.isdir(filepath)
            if size(filename) > 0 && filename[0..0] == "."
                skipped += 1
            elif filename == "push_v2.be" || filename == "esp32.cfg"
                skipped += 1
            else
                if upload_one_file(filepath)
                    uploaded += 1
                else
                    fail("Echec", filename)
                    print("  Uploads: " + str(uploaded) + " / Skips: " + str(skipped))
                    return false
                end
            end
        end
    end

    ok("Complete - " + str(uploaded) + " fichiers")
    return true
end

# ============================================
# MAIN: Execute both parts in sequence
# ============================================

def process_device(ville_param, device_param, sid)
    ville = ville_param
    device = device_param
    
    print("============================================================")
    print("PUSH_V2 - " + ville + "/" + device)
    print("============================================================")
    
    ensure_target_directory(sid)
    
    if !upload_all_files()
        fail("Upload echoue", nil)
        return false
    end
    
    print("============================================================")
    ok("TERMINE")
    return true
end

def main()
    init_auth()
    
    var file = open("esp32.cfg", "rt")
    if file == nil
        fail("Impossible de lire esp32.cfg", nil)
        return
    end
    var buffer = file.read()
    file.close()
    
    var cfg = json.load(buffer)
    if cfg == nil
        fail("esp32.cfg JSON invalide", nil)
        return
    end
    
    var ville_cfg = cfg["ville"]
    
    var sid = login_synology()
    if sid == nil
        fail("Login echoue", nil)
        return
    end
    
    if cfg.contains("devices")
        for device_name : cfg["devices"]
            process_device(ville_cfg, device_name, sid)
        end
    else
        var device_cfg = cfg["device"]
        process_device(ville_cfg, device_cfg, sid)
    end
end

main()
