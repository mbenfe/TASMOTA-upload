# Function to upload a file to the WebDAV server using webclient (wc)
def pushfile(cmd, idx, payload, payload_json)
    # Import the string module for string manipulation
    import string

    var file = open('.secrets', 'r')
    if file == nil
        print("Error opening file: .secrets")
        return
    end
    var secrets = file.read(file)
    file.close()

    file = open("esp32.cfg", "r")
    if file == nil
        print("Error opening file: esp32.cfg")
        return
    end
    var buffer = file.read()
    var myjson = json.load(buffer)
    var ville = myjson["ville"]
    var device = myjson["device"]
    file.close()

    if payload == nil or payload == ""
        print("Invalid format: Expected <localFilePath>")
        return
    end

    var localFilePath = payload  # Local file path (from Tasmota filesystem)
    var webdavCredentials = secrets  # WebDAV server credentials part (username:password@server_ip)

    # Construct the full WebDAV URL with the specified subdirectory (webdav/tasmotafs/choisy/snx) and port 5005
    var remoteFilePath = "http://" + webdavCredentials + ":5005/webdav/tasmotafs/" + ville + "/" + device + "/" + localFilePath
    print(remoteFilePath)

    # Open the local file before reading
    var file = open(localFilePath, "r")
    if file == nil
        print("Error opening file: " + localFilePath)
        return
    end

    # Read file content
    var fileContent = file.read(file)
    if fileContent == nil
        print("Error reading file: " + localFilePath)
        file.close()
        return
    end

    # Close the file after reading
    file.close()

    # Create webclient for file upload (wc)
    var wc = webclient()
    wc.set_follow_redirects(true)
    wc.add_header("Content-Type","text/plain")
    wc.begin(remoteFilePath)
    print(remoteFilePath)

    # Use HTTP PUT method to upload the file with headers
    var response = wc.PUT(fileContent)

    # Check if the upload was successful
    if response == 200 || response == 201
        print("File uploaded successfully to: " + str(remoteFilePath))
    else
        print("Failed to upload file. Status: " + str(response))
    end
end

# Register the command so it can be run from the console
tasmota.add_cmd("pushfile", pushfile)
