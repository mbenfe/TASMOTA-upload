# Custom Base64 encoding function
def base64Encode(data)
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    var output = ""
    var i = 0
    var dataLength = data.len()

    while i < dataLength
        var byte1 = data[i]
        var byte2 = (i + 1 < dataLength) ? data[i + 1] : 0
        var byte3 = (i + 2 < dataLength) ? data[i + 2] : 0

        var enc1 = byte1 >> 2
        var enc2 = ((byte1 & 3) << 4) | (byte2 >> 4)
        var enc3 = ((byte2 & 15) << 2) | (byte3 >> 6)
        var enc4 = byte3 & 63

        if (i + 1) >= dataLength
            enc3 = 64
        end
        if (i + 2) >= dataLength
            enc4 = 64
        end

        output += chars[enc1] + chars[enc2] + chars[enc3] + chars[enc4]
        i += 3
    end

    return output
end

# Function to upload a file to the WebDAV server using WebClient (wc)
def pushfile(cmd, idx, payload, credentials)
    # Split payload into two arguments: local file path and WebDAV details
    var parts = payload.split(" ")
    if parts.len() < 2
        print("Missing local file path or WebDAV details")
        return
    end

    var localFilePath = parts[0]
    var webdavDetails = parts[1]

    # Credentials are received as a comma-separated string in the second argument
    var creds = webdavDetails.split(",")
    if creds.len() < 3
        print("Missing server, username, or password in WebDAV details")
        return
    end

    var server_ip = creds[0]
    var username = creds[1]
    var password = creds[2]
    
    # Construct URL with username and password before IP
    var remoteFilePath = "http://" + server_ip + localFilePath

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

    # Create Authorization Header (Basic Auth)
    var credentials = username + ":" + password
    var authHeader = "Basic " + base64Encode(credentials)

    # Create WebClient for file upload (wc)
    var wc = WebClient()
    wc.setHeader("Authorization", authHeader)
    wc.setHeader("Content-Type", "text/plain")  # Adjust content type based on the file

    # Use HTTP PUT method to upload the file
    var response = wc.put(remoteFilePath, fileContent)

    # Check if the upload was successful
    if response.status == 200 or response.status == 201
        print("File uploaded successfully to: " + remoteFilePath)
    else
        print("Failed to upload file. Status: " + response.status)
    end
end

# Register the command so it can be run from the console
tasmota.add_cmd("pushfile", pushfile)
