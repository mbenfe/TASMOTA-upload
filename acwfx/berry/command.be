# Define mqttprint function
def mqttprint(texte)
    var topic = string.format("gw/inter/%s/%s/tele/PRINT", global.ville, global.device)
    mqtt.publish(topic, texte, true)
end

# Function to upload a file to the WebDAV server using webclient (wc)
def pushfile(cmd, idx, payload, payload_json)
    # Import the string module for string manipulation
    import string
    import path

    # Open the .secret file to read WebDAV credentials
    var file = open(".secret", "rt")
    if file == nil
        mqttprint("Error opening .secret file for WebDAV credentials")
        return
    end

    var webdavCredentials = file.read()
    file.close()

    # Check if WebDAV credentials are empty
    if webdavCredentials == ""
        mqttprint("WebDAV credentials are empty")
        return
    end

    # Construct the base WebDAV URL with the specified subdirectory and port 5005
    var baseUrl = "http://" + webdavCredentials + ":5005/webdav/tasmotafs/" + global.ville + "/" + global.device

    # Function to upload a single file
    def upload_file(localFilePath)
        var remoteFilePath = baseUrl + "/" + localFilePath

        # Open the local file before reading
        var file = open(localFilePath, "r")
        if file == nil
            mqttprint("Error opening file: " + localFilePath)
            return
        end

        # Read file content
        var fileContent = file.read()
        if fileContent == nil
            mqttprint("Error reading file: " + localFilePath)
            file.close()
            return
        end

        # Close the file after reading
        file.close()

        # Create webclient for file upload (wc)
        var wc = webclient()
        wc.set_follow_redirects(true)
        wc.add_header("Content-Type", "text/plain")  # Adjust MIME type if necessary
        wc.begin(remoteFilePath)
        mqttprint("Uploading to: " + remoteFilePath)

        # Use HTTP PUT method to upload the file with headers
        var response = wc.PUT(fileContent)

        # Check if the upload was successful
        if response == 200 || response == 201
            mqttprint("File uploaded successfully to: " + remoteFilePath)
        else
            mqttprint("Failed to upload file. Status: " + str(response))
        end
    end

    # Create the directory if it does not exist
    var wc = webclient()
    wc.set_follow_redirects(true)
    wc.begin(baseUrl)
    var response = wc.MKCOL()
    if response != 201 && response != 405  # 201 Created, 405 Method Not Allowed (if the directory already exists)
        mqttprint("Failed to create directory. Status: " + str(response))
        return
    end

    # Check if the payload is "all" to upload all files
    if payload == "all"
        var files = path.listdir("/")
        for i:0..files.size() - 1
            upload_file(files[i])
        end
    else
        upload_file(payload)
    end
end

# Register the command so it can be run from the console
tasmota.add_cmd("pushfile", pushfile)