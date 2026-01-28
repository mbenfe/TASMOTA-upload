# Frico Thermostat Control System - Copilot Instructions

## Project Overview

**Frico** is an ESP32-based MQTT-enabled thermostat system written in Berry (Tasmota's scripting language). It manages heating/cooling with temperature sensors, relay controls, and button/LED interfaces for multiple locations across France.

## Architecture & Key Components

### Core Modules
- **[autoexec.be](autoexec.be)**: Bootstrap loader; initializes config, registers Tasmota commands, launches drivers
- **[frico_driver.be](frico_driver.be)**: Main RDX thermostat logic class - handles MQTT subscriptions, temperature polling, relay control, schedule-based heating
- **[io.be](io.be)**: PCF8574A I2C I/O expander driver - manages 4 buttons and 5 LEDs (button/LED layout documented in file header)
- **[ds18b20.be](ds18b20.be)**: DS18B20 temperature sensor polling driver - supports 2 sensors via Tasmota's sensor API
- **[command.be](command.be)**: WebDAV file upload and maintenance utilities

### Data Flow
1. **Startup**: `autoexec.be` loads `esp32.cfg` (device identity), `config.json` (location/sensor setup), `setup.json` (user settings)
2. **Polling**: `RDX.every_minute()` runs via cron; reads primary temp source, checks schedule, publishes MQTT telemetry
3. **Control**: Temperature drives relay state (heating ON/OFF based on target vs current); buttons/LEDs via I2C expander reflect system state
4. **Configuration**: MQTT topic `app/{client}/{ville}/{device}/set/SETUP` triggers `RDX.mysetup()` to persist changes

### Global State Management
All critical state stored in `global.*` variables initialized by `loadconfig()`:
- `global.ville`, `global.device`, `global.location` - device identity
- `global.setup` - persistent settings (on/off, fan speed, heat power, schedules)
- `global.config` - sensor availability map per location
- `global.tempsource` - ordered list of active sensors (checked in priority order)
- `global.remote_temp`, `global.ds`, `global.dsin` - sensor readings
- `global.factor`, `global.dsin_offset`, `global.ds_offset` - calibration values

## Critical Patterns & Workflows

### Temperature Sensor Hierarchy
`global.tempsource` is a priority-ordered list built at startup from `config.json`:
```
["remote", "pt", "ds", "dsin"]  // Only non-"nok" sensors included; dsin always last
```
In `every_minute()`, uses **first active sensor** in this list. Sensor codes: `"remote"` (MQTT), `"pt"` (average), `"ds"` (DS18B20-1), `"dsin"` (DS18B20-2).

### Relay Control Logic
In `every_minute()`:
```
if (hour >= schedule[day].debut && hour < schedule[day].fin) {
    target = setup['ouvert']  // Daytime target
    power = (temperature < target && setup['onoff'] == 1) ? 1 : 0
} else {
    power = 0  // Outside schedule
    target = setup['ferme']   // Night target
}
```
Relay state controlled via `PCF.update_relays()` — buttons/LEDs must sync via same method after MQTT setup changes.

### MQTT Messaging
- **Command topic** (inbound): `app/{client}/{ville}/{device}/set/SETUP` → JSON with `DATA` object
- **Telemetry topic** (outbound): `gw/{client}/{ville}/{device}/tele/SENSOR` → current state JSON
- **Debug topic**: `gw/inter/{ville}/{device}/tele/PRINT` → all mqttprint() calls published as `{"texte":"..."}`

### Configuration File Organization
| File | Purpose | Format |
|------|---------|--------|
| `esp32.cfg` | Device identity, client | JSON: `{ville, client, device, location}` |
| `config.json` | Sensor mapping per location | JSON: `{ville: {device: {remote, pt, ds}}}` ("nok" = unavailable) |
| `setup.json` | User settings (persistent) | JSON: `{onoff, fanspeed, heatpower, ouvert, ferme, ...schedule...}` |
| `calibration.json` | Sensor offsets & factors | JSON: `{pt: factor, dsin_offset, ds_offset}` |

### Calibration System
- **PT (RTD) calibration**: `global.factor` = scale multiplier; `cal pt 21` recalculates from current average
- **DS18B20 calibration**: `cal dsin 21` and `cal ds 21` store temperature offsets in calibration.json
- Offsets applied in real-time during polling

### Command Registration Pattern
Tasmota commands via `tasmota.add_cmd(name, function)`:
```berry
tasmota.add_cmd('getfile', getfile)   // Download files from GitHub
tasmota.add_cmd('cal', cal)            // Calibration
tasmota.add_cmd('get', get)            // Fetch setup.json
tasmota.add_cmd('dir', dir)            // List files
tasmota.add_cmd('ville', ville)        // Update location ID
```

## Berry Language Specifics

- **Imports required at function scope** (not module-level unless at top of file)
- **String formatting**: `string.format(template, args...)` not printf
- **JSON handling**: `json.load(string)` and `json.dump(object)` only; no parse/stringify
- **File I/O**: Must check `file == nil` before operations; `file.size()` for size
- **Tasmota integration**: `tasmota.load(filename)` loads .be modules; `tasmota.add_driver(obj)` registers lifecycle hooks; `tasmota.cmd(cmd)` executes Tasmota commands; `tasmota.read_sensors()` returns JSON string of sensor data
- **Class drivers**: Must define `init()` method; can register cron jobs with `tasmota.set_timer()` or `tasmota.add_cron()`

## Common Tasks

### Adding a New Temperature Sensor
1. Update `config.json` with sensor mapping (change from `"nok"` to device ID)
2. In `frico_driver.be`, add branch in `every_minute()` to poll sensor via corresponding class (e.g., `ds18b20.poll()`)
3. Update `global.tempsource` priority order if needed in `loadconfig()`
4. Add calibration offset to `calibration.json` if applicable

### MQTT Setup Changes
1. Device publishes JSON to `app/{client}/{ville}/{device}/set/SETUP`
2. `RDX.mysetup()` parses, updates `global.setup`, persists to `setup.json`
3. Calls `pcf.update_onoff_led()`, `update_heat_power_leds()`, `update_fan_speed_leds()`, **and** `update_relays()` to sync hardware
4. Invokes `every_minute()` immediately for state refresh

### GPIO Configuration
ESP32 GPIO layout (from autoexec.be comments):
- **GPIO7**: DS18B20-1 (code 1312)
- **GPIO8**: SDA (code 640, I2C)
- **GPIO18**: SCL (code 608, I2C)
- **GPIO19**: DS18B20-2 (code 1313)
- `RDX.check_gpio()` auto-corrects misconfigured pins on every minute cycle

## Error Handling & Debugging

- **mqttprint()**: Debug output; publishes to `gw/inter/{ville}/{device}/tele/PRINT` topic for inspection
- **No exception handling**: Berry code lacks try/catch; guard with `if variable == nil` or `if file == nil`
- **Sensor reading failures**: Return `99` on error; checked downstream with `if temperature == 99`
- **File operations**: Always check return values; use `path.exists()` before opening

## Important Notes

- **Thread safety**: Single-threaded Berry VM; no concurrency concerns
- **Memory**: ESP32 constrained; avoid large buffer allocations
- **Tasmota dependency**: All code assumes Tasmota 12+ runtime; uses Tasmota drivers, MQTT, GPIO, sensors
- **Version tracking**: Each .be file starts with `var version = "x.y.z..."` comment for `getversion` command
- **Cron interval**: Main loop runs once per minute (`every_min_@0_s` cron); TelePeriod set to 60s
