# Function to upload a file to the WebDAV server using webclient (wc)
def pushfile(cmd, idx, payload, payload_json)
    # Import the string module for string manipulation
    import string

    if payload == nil || payload == ""
        print("Invalid format: Expected <localFilePath>")
        return
    end

    var localFilePath = payload  # File to upload (e.g., "autoexec.be")

    # Read WebDAV credentials from .secrets file
    var file = open('.secrets', 'r')
    if file == nil
        print("Error opening file: .secrets")
        return
    end
    var secrets = file.read()
    file.close()

    # Read esp32.cfg to get 'ville' and 'device' parameters
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

    # Construct the remote WebDAV path dynamically
    var encodedPassword = string.replace(secrets, "#", "%23")
    var remoteFilePath = "http://" + encodedPassword + ":5005/webdav/tasmotafs/" + ville + "/" + device + "/" + localFilePath

    print("Uploading: " + localFilePath + " ? " + remoteFilePath)

    # Open the local file
    file = open(localFilePath, "r")
    if file == nil
        print("Error opening file: " + localFilePath)
        return
    end

    var fileContent = file.read()
    file.close()

    if fileContent == nil
        print("Error reading file: " + localFilePath)
        return
    end

    # Initialize WebClient
    var wc = webclient()
    wc.add_header("Content-Type", "text/plain")
    wc.begin(remoteFilePath)

    # Upload the file using PUT method
    var response = wc.PUT(fileContent)

    # Check response status
    if response == 200 || response == 201
        print("? File uploaded successfully: " + remoteFilePath)
    else
        print("? Upload failed. Status: " + str(response))
    end
end

# Register the command in Tasmota console
tasmota.add_cmd("pushfile", pushfile)
