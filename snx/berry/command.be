# Function to upload a file to the WebDAV server using WebClient (wc)
def pushfile(cmd, idx, payload, payload_json)
    # Split the payload into local file path and WebDAV URL components
    var parts = payload.split(" ")
    if parts.len() < 2
        print("Invalid format: Expected <localFilePath> <username:password@server_ip>")
        return
    end

    var localFilePath = parts[0]  # Local file path (from Tasmota filesystem)
    var webdavCredentials = parts[1]  # WebDAV server credentials part (username:password@server_ip)

    # Construct the full WebDAV URL (with port 5005)
    var remoteFilePath = "http://" + webdavCredentials + ":5005/" + localFilePath

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

    # Create WebClient for file upload (wc)
    var wc = webclient()
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
