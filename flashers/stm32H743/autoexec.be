import global


def init()
    global.rx = 36
    global.tx = 1    
    gpio.pin_mode(global.rx,gpio.INPUT_PULLUP)
    gpio.pin_mode(global.tx,gpio.OUTPUT)

    global.serflash = serial(global.rx,global.tx,115200,serial.SERIAL_8E1)
    global.bsl = 32
    global.rst = 33
    gpio.pin_mode(global.bsl,gpio.OUTPUT)
    gpio.pin_mode(global.rst,gpio.OUTPUT)
    gpio.digital_write(global.bsl, 0)
    gpio.digital_write(global.rst, 1)
    print("flasher hardware setup completed")
end

init()
