# push_restore.be
# Restore autoexec.be after clean push

import path

if path.exists("autoexec.be.disabled")
    var f_old = open("autoexec.be.disabled", "r")
    var content = f_old.read()
    f_old.close()
    
    var f_new = open("autoexec.be", "w")
    f_new.write(content)
    f_new.close()
    
    path.remove("autoexec.be.disabled")
    print("autoexec.be restored - restarting...")
    tasmota.cmd("Restart 1")
else
    print("Nothing to restore")
end
