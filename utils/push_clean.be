# push_clean.be
# Disable autoexec.be, run push, then restart

def disable_autoexec()
    # Rename autoexec.be to prevent auto-loading
    import path
    if path.exists("autoexec.be")
        var f_old = open("autoexec.be", "r")
        var content = f_old.read()
        f_old.close()
        
        var f_new = open("autoexec.be.disabled", "w")
        f_new.write(content)
        f_new.close()
        
        path.remove("autoexec.be")
        print("autoexec.be disabled")
    end
end

def restore_autoexec()
    import path
    if path.exists("autoexec.be.disabled")
        var f_old = open("autoexec.be.disabled", "r")
        var content = f_old.read()
        f_old.close()
        
        var f_new = open("autoexec.be", "w")
        f_new.write(content)
        f_new.close()
        
        path.remove("autoexec.be.disabled")
        print("autoexec.be restored")
    end
end

def main()
    print("=== PUSH CLEAN MODE ===")
    
    # Disable autoexec for next boot
    disable_autoexec()
    
    print("Restarting for clean environment...")
    tasmota.cmd("Restart 1")
end

main()
