# Tasmota Berry Thermostat Controller

## Project Overview
ESP32-based thermostat controller using Tasmota Berry scripting. Controls heating relays based on temperature sensors (DS18B20 or remote MQTT sensors) with time-scheduled setpoints and MQTT integration.

## Architecture

### Component Hierarchy
1. **[autoexec.be](berry/autoexec.be)** - Entry point, runs on boot
   - Validates GPIO configuration (DS18x20 on GPIO8/20)
   - Loads `esp32.cfg` (city, devices, locations)
   - Loads `config.json` (sensor mappings per device/city)
   - Loads `calibration.json` (temperature offsets)
   - Registers CLI commands (`getfile`, `dir`, `ville`, `device`, `cal`, etc.)
   - Delays 30s then loads drivers: `ds18b20.be` → `climair_driver.be`

2. **[climair_driver.be](berry/climair_driver.be)** - Main control logic class `CLIMAIR`
   - Subscribes to MQTT topics `app/{client}/{ville}/{device}/set/SETUP` for schedule updates
   - Runs `every_minute()` cron: reads sensors, compares to target temps, controls relays
   - Publishes telemetry to `gw/{client}/{ville}/{device}/tele/SENSOR`
   - Controls GPIO 18/19 relays based on temperature vs. time-based setpoints

3. **[ds18b20.be](berry/ds18b20.be)** - Temperature sensor driver
   - Polls `DS18B20-1` (internal) and `DS18B20-2` (external) via Tasmota API
   - Applies calibration offsets from `global.dsin_offset` / `global.ds_offset`

### Data Flow
```
Sensors (DS18B20/Remote MQTT) 
   → climair_driver.every_minute() 
   → Compare temp vs schedule (setup.json) 
  → Set relay GPIO 18/19 
  → Publish state to MQTT
```

### Global Variables Convention
Critical shared state stored in `global` namespace:
- `global.ville`, `global.client`, `global.device`, `global.location` - device identity
- `global.setup` - schedule config (loaded from `setup.json`)
- `global.config` - sensor mapping from `config.json`
- `global.tempsource[]` - available sensors (e.g., `["remote", "ds"]`)
- `global.remote_temp` - latest MQTT sensor reading
- `global.relay` - GPIO pin for relay

## Configuration Files

### esp32.cfg
Defines device identity (city, client, device IDs). Example:
```json
{"ville":"coubron","client":"inter","device":"aex-1","location":"zone1"}
```

### config.json
Maps sensors to devices per city. Sensor priority: `remote` > `ds` > `dsin` (always last).
```json
{"coubron":{"aex-1":{"remote":"th_boulangerie","ds":"ok"}}}
```

### setup.json
Schedule with daily time ranges and target temps:
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
- **Debug logs**: `gw/inter/{ville}/{device}/tele/PRINT`
- **Remote sensors**: `gw/{client}/{ville}/zb-{sensor}/tele/SENSOR`

### Temperature Control Logic
See [climair_driver.be](../berry/climair_driver.be):
1. Select sensor based on first entry in `global.tempsource`
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
1. Modify `setup.json` locally
2. Publish to `app/{client}/{ville}/{device}/set/SETUP` via MQTT
3. System auto-saves and republishes to `gw/{client}/{ville}/{device}/set/SETUP`
4. Call `every_minute()` immediately to test relay logic

### Calibration
Adjust sensor offsets via CLI:
```
cal dsin 22.0     // Sets DS18B20-1 offset
cal ds 20.5       // Sets DS18B20-2 offset
```

## Critical Gotchas

1. **Sensor Priority**: The first element in `global.tempsource` is used, not the last. See [climair_driver.be](../berry/climair_driver.be).

2. **Device Naming**: All MQTT topics use `global.device`.

3. **GPIO Auto-Config**: System auto-corrects GPIO settings on every boot and every minute. Don't manually set GPIOs via Tasmota console.

4. **Relay Pin Hardcoded**: GPIO 19 hardcoded in [climair_driver.be](../berry/climair_driver.be). Not configurable.

5. **Offset Field**: In `setup.json`, `offset` is loaded but should NOT be changed by MQTT updates.

6. **Driver Load Order**: Must be `ds18b20.be` → `climair_driver.be`.

## Berry Language Notes
- Uses Tasmota's Berry dialect (embedded scripting for ESP32)
- No `print()` in production - use `mqttprint()` for remote logging
- Lists are 0-indexed: `for i:0..size(list)-1`
- Class methods auto-bind `self`: `tasmota.add_cron("0 * * * * *", /-> self.every_minute())`
- JSON parsing: `json.load(string)` returns map/list, `json.dump(object)` returns string
