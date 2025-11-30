var version = "1.0.0 minimal"

class WebUI
    def init()
        print("WebUI: init")
    end
    
    def web_add_main_button()
        import webserver
        webserver.content_send("<p>TEST BUTTON WORKS</p>")
    end
    
    def web_add_handler()
        print("WebUI: handler called")
    end
end

return WebUI()