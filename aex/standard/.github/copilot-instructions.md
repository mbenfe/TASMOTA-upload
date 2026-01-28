# Tasmota Berry Thermostat Controller

## Project Overview
Multi-zone ESP32-based thermostat controller using Tasmota Berry scripting. Controls heating relays based on temperature sensors (DS18B20, PT1000, or remote MQTT sensors) with time-scheduled setpoints and MQTT integration.

## Architecture

### Component Hierarchy
1. **[autoexec.be](berry/autoexec.be)** - Entry point, runs on boot
   - Validates GPIO configuration (I2C on GPIO6/7, DS18x20 on GPIO8/20)
   - Loads `esp32.cfg` (city, devices, locations)
   - Loads `config.json` (sensor mappings per device/city)
   - Loads `calibration.json` (temperature offsets)
   - Registers CLI commands (`getfile`, `dir`, `ville`, `device`, `cal`, etc.)
   - Delays 30s then loads drivers: `io.be` → `ds18b20.be` → `aerotherme_driver.be`

2. **[aerotherme_driver.be](berry/aerotherme_driver.be)** - Main control logic class `AEROTHERME`
   - Subscribes to MQTT topics `app/{client}/{ville}/{device}/set/SETUP` for schedule updates
   - Runs `every_minute()` cron: reads sensors, compares to target temps, controls relays
   - Publishes telemetry to `gw/{client}/{ville}/{device}/tele/SENSOR`
   - Controls GPIO 18/19 relays based on temperature vs. time-based setpoints

3. **[io.be](berry/io.be)** - PCF8574A I/O expander driver
   - Manages 3 buttons (P1/P2/P3) + 4 LEDs (P0/P4/P5/P7)
   - Button press toggles thermostat on/off state and publishes to MQTT
   - Polls every 250ms via `every_250ms()` driver method

4. **[ds18b20.be](berry/ds18b20.be)** - Temperature sensor driver
   - Polls `DS18B20-1` (internal) and `DS18B20-2` (external) via Tasmota API
   - Applies calibration offsets from `global.dsin_offset` / `global.ds_offset`

### Data Flow
```
Sensors (DS18B20/PT1000/Remote MQTT) 
  → aerotherme_driver.every_minute() 
  → Compare temp vs schedule (setup_N.json) 
  → Set relay GPIO 18/19 
  → Publish state to MQTT
```

### Global Variables Convention
Critical shared state stored in `global` namespace:
- `global.ville`, `global.client`, `global.devices[]`, `global.location[]` - device identity
- `global.esp_device` - concatenated device name (e.g., "aex-1-2")
- `global.setups[]` - array of schedule configs (loaded from `setup_N.json`)
- `global.config[]` - sensor mappings per device (from `config.json`)
- `global.tempsource[][]` - available sensors per zone (e.g., `[["remote", "ds"]]`)
- `global.remote_temp[]` - latest MQTT sensor readings
- `global.pcf` - I/O expander driver instance
- `global.wire` - I2C bus object
- `global.relay[]` - GPIO pins for relays

## Configuration Files

### esp32.cfg
Defines device identity (city, client, device IDs). Example:
```json
{"ville":"coubron","client":"inter","devices":["aex-1","aex-2"],"location":["zone1","zone2"],"nombre":2}
```

### config.json
Maps sensors to devices per city. Sensor priority: `remote` > `pt` > `ds` > `dsin` (always last).
```json
{"coubron":{"aex-1":{"remote":"th_boulangerie","pt":"nok","ds":"ok"}}}
```

### setup_N.json
Per-zone schedules with daily time ranges and target temps:
```json
{
  "onoff": 1,
  "offset": 0.0,
  "ouvert": 19.0,    // Target temp during open hours
  "ferme": 11.0,     // Target temp during closed hours
  "lundi": {"debut": 8.0, "fin": 18.0}
}
```

## Key Patterns

### Driver Registration
All Berry modules use Tasmota's driver system:
```berry
var my_driver = MY_CLASS()
tasmota.add_driver(my_driver)
```

### MQTT Topic Structure
- **Inbound config**: `app/{client}/{ville}/{device}/set/SETUP`
- **Outbound telemetry**: `gw/{client}/{ville}/{device}/tele/SENSOR`
- **Debug logs**: `gw/inter/{ville}/{esp_device}/tele/PRINT`
- **Remote sensors**: `gw/{client}/{ville}/zb-{sensor}/tele/SENSOR`

### Temperature Control Logic
See [aerotherme_driver.be](berry/aerotherme_driver.be#L192-L222):
1. Select sensor based on `global.tempsource[zone][0]` priority
2. Check if current hour is within schedule window (`debut`-`fin`)
3. Compare temp to `ouvert` or `ferme` target (minus `offset`)
4. Set relay high if `temp < target` AND `onoff == 1`

### CLI Command Pattern
Commands registered in [autoexec.be](berry/autoexec.be#L282-L288):
```berry
def mycommand(cmd, idx, payload, payload_json)
    # Modify JSON config file
    tasmota.resp_cmnd('done')
end
tasmota.add_cmd('mycommand', mycommand)
```

### File Operations
Always check file handles:
```berry
var file = open("config.json", "rt")
if file == nil
    mqttprint("Error: Failed to open file")
    return
end
var content = file.read()
file.close()
```

## Development Workflows

### Deploying Changes
Use `getfile` command to download from GitHub:
```
getfile aex/standard/berry/autoexec.be
```
Fetches from `https://raw.githubusercontent.com/mbenfe/upload/main/{payload}`

### Debugging
- Use `mqttprint("message")` - publishes to MQTT topic for remote logging
- Check GPIO config: Run `check_gpio()` - auto-fixes incorrect GPIO assignments
- List files: `dir` command shows all files with timestamps/sizes
- Version check: `getversion` reads version strings from `.be` files

### Testing Schedules
1. Modify `setup_N.json` locally
2. Publish to `app/{client}/{ville}/{device}/set/SETUP` via MQTT
3. System auto-saves and republishes to `gw/{client}/{ville}/{device}/set/SETUP`
4. Call `every_minute()` immediately to test relay logic

### Calibration
Adjust sensor offsets via CLI:
```
cal pt 21.5       // Sets PT1000 factor based on current reading vs. actual
cal dsin 22.0     // Sets DS18B20-1 offset
cal ds 20.5       // Sets DS18B20-2 offset
```

## Critical Gotchas

1. **Sensor Priority**: The first element in `global.tempsource[i]` is used, not the last. See [aerotherme_driver.be](berry/aerotherme_driver.be#L192-L199).

2. **Device Naming**: `global.esp_device` is concatenated from `devices[]` array (e.g., "aex-1" + "aex-2" → "aex-1-2"), but MQTT topics use individual device names.

3. **GPIO Auto-Config**: System auto-corrects GPIO settings on every boot and every minute. Don't manually set GPIOs via Tasmota console.

4. **Relay Pins Hardcoded**: GPIO 18/19 hardcoded in [aerotherme_driver.be](berry/aerotherme_driver.be#L162-L166). Not configurable.

5. **Offset Field**: In `setup_N.json`, `offset` is loaded but should NOT be changed by MQTT updates (see comment in [aerotherme_driver.be](berry/aerotherme_driver.be#L87)).

6. **Driver Load Order**: Must be `io.be` → `ds18b20.be` → `aerotherme_driver.be` (dependencies on `global.pcf`, sensor APIs).

## Berry Language Notes
- Uses Tasmota's Berry dialect (embedded scripting for ESP32)
- No `print()` in production - use `mqttprint()` for remote logging
- Lists are 0-indexed: `for i:0..size(list)-1`
- Class methods auto-bind `self`: `tasmota.add_cron("0 * * * * *", /-> self.every_minute())`
- JSON parsing: `json.load(string)` returns map/list, `json.dump(object)` returns string
