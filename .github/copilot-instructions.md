# Copilot Instructions for TASMOTA-upload Repository

## Project Overview
This is a **Tasmota firmware configuration & deployment system** for IoT energy/climate management devices. It manages multiple device types (PWX, CHX, RDX, SNX, THX, WFX, AEX, ACWFX) connected to an MQTT broker, with Berry scripts running on ESP32 controllers communicating with STM32 slave devices via serial (UART).

## Architecture & Key Components

### Device Type Directories
- **4-pwx12, 5-pwx12-mono, 6-pwx4, 7-pwx4-mono**: Power monitoring/calibration devices
- **2-chx, 3-chx-p**: Thermostat heating controllers  
- **8-rdx**: Radiator/climate control with frico/thermoscreen variants
- **aex, acwfx, thx, snx, wfx**: Specialized monitoring/bridge devices
- **zb-sonoff, zb-bridge-sonoff, znp**: Zigbee bridge devices

### Data Flow Pattern
1. **esp32.cfg** (device identity): JSON with `{"ville": "location", "client": "inter", "device": "device_id", "location": "zone"}`
2. **autoexec.be** (startup): Loads configuration, establishes MQTT connection, registers commands, launches driver after 10s delay
3. **[device]_driver.be** (main logic): Classes handling UART/serial communication with STM32, MQTT pub/sub, state management
4. **config/*.json** (setup): Device registers, control parameters, mapping for Modbus/protocol parsing

### MQTT Communication Pattern
```
Topics: gw/{client}/{ville}/{device}/...
- tele/PRINT: Debug messages
- tele/PWDAYS, PWMONTHS: Power aggregation  
- set/SETUP: Configuration from cloud
- set/HORAIRES, ISEMAINE: Schedule management
```

## Critical Patterns & Conventions

### 1. Initialization Flow
All devices follow this sequence:
```berry
# 1. Load esp32.cfg → global variables (ville, device, client, location)
# 2. Register commands (getfile, dir, ville, device, etc.)
# 3. MQTT connect trigger
# 4. launch_driver() delayed 10s → loads device_driver.be
# 5. Driver registers handlers (mqtt.subscribe, tasmota.add_driver)
```

### 2. Configuration & Global State
- **esp32.cfg**: Device identity (loaded by all devices)
- **setup_device.json**: Device-specific parameters
- **global.ville, global.device, global.client**: Always set during loadconfig()
- **Driver instances** stored in global (e.g., `global.pwx12`, `global.pcf`)

### 3. Serial/UART Communication
Devices use **3-pin UART to STM32**:
```berry
rx = 3|16, tx = 1|17, rst = 2, bsl = 13  # GPIO pins vary by device
serial(rx, tx, 115200, serial.SERIAL_8N1)
# Boot sequence: Set bsl=0, rst=1 for normal operation
```

### 4. Berry Patterns
- **mqttprint()**: Debug via MQTT - used everywhere for visibility
- **json.load/dump**: All config files are JSON
- **path.listdir()**: File enumeration
- **tasmota.load()**: Module loading deferred until startup complete
- **Tasmota hooks**: `tasmota.add_driver()`, `tasmota.add_fast_loop()`, `tasmota.add_cron()`

### 5. Error Recovery
- STM32 reset: `gpio.digital_write(rst, 0); tasmota.delay(100); gpio.digital_write(rst, 1)`
- Configuration missing: Auto-create esp32.cfg with defaults
- Serial flush before sending: `global.serialSend.flush()` before `write()`

## Developer Workflows

### Adding a New Device Type
1. Create `{device-number}-{name}/berry/` directory
2. Copy `autoexec.be` template (adjust GPIO pins + MQTT topics)
3. Create `{name}_driver.be` with serial/MQTT handlers
4. Test esp32.cfg loading: `tasmota.cmd("getfile esp32.cfg")`
5. Verify MQTT topics match pattern `gw/inter/{ville}/{device}/*`

### Debugging Device Issues
```berry
# Check device identity
br import json; var f=open("esp32.cfg"); print(json.load(f.read()))

# Monitor serial input
br import serial; print(global.ser.read())

# List loaded modules
br tasmota.cmd("dir")

# Reset STM32
br import gpio; gpio.digital_write(2, 0); tasmota.delay(100); gpio.digital_write(2, 1)
```

### Binary Flasher Workflow (pwx12/4-pwx12)
- **flasher.be**: Converts `.bin` → `.binc` (flashing format)
- Command: `br import flasher as f; f.convert('file.bin'); f.flash('file.binc')`
- See [instruction.txt](../../instruction.txt) for urlfetch pattern

## Configuration Files

### config/device.json & config/controler.json
Maps register IDs (hex) to properties for Modbus/protocol parsing:
```json
{
  "0064": {
    "name": "Cutout°C",
    "type": "float",
    "ratio": 0.1,
    "device": "AK-CC55xx",
    "unit": ""
  }
}
```
Used by drivers to decode register values from STM32.

### City-Specific Configs
**config/c_*.json, f_*.json, m_*.json, p_*.json, w_*.json**: City-specific device mappings (c=control, f=froid, m=monitoring, p=power, w=waste heat)

## Common Tasks

### Reading Device State
```berry
# From setup JSON
var f = open("setup_device.json", "rt")
var data = json.load(f.read())
f.close()
# Access: data["field_name"]
```

### Publishing Telemetry
```berry
var payload = string.format("{\"device\":\"%s\",\"temp\":%.2f}", global.device, temp_val)
var topic = string.format("gw/%s/%s/%s/tele/STATUS", global.client, global.ville, global.device)
mqtt.publish(topic, payload, true)  # retain=true
```

### Command Registration
```berry
tasmota.add_cmd('commandname', function_name)
# Auto-responds via tasmota.resp_cmnd() or tasmota.resp_cmnd_done()
```

## Files to Know
- [4-pwx12/berry/autoexec.be](../../4-pwx12/berry/autoexec.be): PWX12 startup template
- [4-pwx12/berry/pwx12_driver.be](../../4-pwx12/berry/pwx12_driver.be): Power monitoring serial handler
- [8-rdx/frico/berry/frico_driver.be](../../8-rdx/frico/berry/frico_driver.be): Climate control with IO extension
- [config/device.json](../../config/device.json): Register mapping reference
- [instruction.txt](../../instruction.txt): Setup scripts & urlfetch examples

## Important Notes
- **MQTT retains ON**: `mqtt.publish(topic, payload, true)` - used for all telemetry
- **Version tracking**: First line of .be files: `var version = "X.X.XYYMMDD details"`
- **Heap monitoring**: `tasmota.get_free_heap()` often checked after serial init
- **No async waits**: Use `tasmota.set_timer()` for delayed operations, not `tasmota.delay()` in loops
