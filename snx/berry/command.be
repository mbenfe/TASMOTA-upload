# Function to upload a file to the WebDAV server using webclient (wc)
def pushfile(cmd, idx, payload, payload_json)
    # # Import the string module for string manipulation
    # import string

    # # Split the payload into local file path and WebDAV URL components using string.split
    # var parts = string.split(payload, " ")
    # if parts.size() < 2
    #     print("Invalid format: Expected <localFilePath> <username:password@server_ip>")
    #     return
    # end

    # var localFilePath = parts[0]  # Local file path (from Tasmota filesystem)
    # var webdavCredentials = parts[1]  # WebDAV server credentials part (username:password@server_ip)

    # # Construct the full WebDAV URL with the specified subdirectory (webdav/tasmotafs/choisy/snx) and port 5005
    # var remoteFilePath = "http://" + webdavCredentials + ":5005/webdav/tasmotafs/choisy/snx/" + localFilePath

    # # Open the local file before reading
    # var file = open(localFilePath, "r")
    # if file == nil
    #     print("Error opening file: " + localFilePath)
    #     return
    # end

    # # Read file content
    # var fileContent = file.read(file)
    # if fileContent == nil
    #     print("Error reading file: " + localFilePath)
    #     file.close()
    #     return
    # end

    # # Close the file after reading
    # file.close()

    # # Create webclient for file upload (wc)
    # var wc = webclient()
    # wc.set_follow_redirects(true)
    # wc.add_header("Content-Type","text/plain")
    # wc.begin(remoteFilePath)
    # print(remoteFilePath)

    # # Use HTTP PUT method to upload the file with headers
    # var response = wc.PUT(fileContent)

    # # Check if the upload was successful
    # if response == 200 || response == 201
    #     print("File uploaded successfully to: " + str(remoteFilePath))
    # else
    #     print("Failed to upload file. Status: " + str(response))
    # end
end

# Register the command so it can be run from the console
tasmota.add_cmd("pushfile", pushfile)
