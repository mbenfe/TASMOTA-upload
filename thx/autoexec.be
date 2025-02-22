tasmota.cmd("setoption100 1")
tasmota.resp_cmnd('done')

tasmota.load('zb_handler.be')
