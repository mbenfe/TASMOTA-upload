# CC2652 Flasher Scripts: Detailed Purpose

This folder contains a small flashing framework written in Berry for Tasmota-based devices that use a TI CC2652 Zigbee MCU.

At a high level, the scripts are split into three layers:

1. Transport and protocol layer (raw CC2652 ROM BSL commands).
2. Firmware file parsing layer (Intel HEX parser and validator).
3. Device-specific flashing workflows (Sonoff and TubeZB safety checks and full flashing pipeline).

---

## 1) cc2652_flasher.be

### Primary purpose

`cc2652_flasher.be` is the low-level driver that talks directly to the CC2652 ROM Serial Boot Loader (BSL) over UART. It handles:

- GPIO control to force the MCU into bootloader mode.
- Serial framing, checksum, and ACK handling.
- ROM command wrappers (read memory, erase bank, CRC32, download/send data, status).
- Higher-level flash operations (write chunk, erase full flash, dump flash to file).

### Why this file exists

This script isolates all protocol details so higher-level flashing scripts can focus on firmware policy and validation instead of byte-level UART exchanges.

### Key responsibilities

- Resolves required pins (`rx`, `tx`, `rst`, `bsl`) from Tasmota GPIO mappings.
- Aborts active Zigbee stack before taking over UART (`zigbee.abort()`).
- Performs BSL entry sequence:
  - Pull BSL control low.
  - Pulse reset.
  - Send `0x55 0x55` for auto-baud.
  - Wait for expected BSL response (`0xCC`).
- Encodes/decodes command payloads with bootloader-specific framing and checksum.
- Exposes command wrappers:
  - `cmd_get_chip_id()`
  - `cmd_memory_read(addr, len)`
  - `cmd_download(addr, size)`
  - `cmd_send_data(data)`
  - `cmd_bank_erase()`
  - `cmd_crc32(addr, len)`
  - `cmd_get_status()`
- Provides practical flash APIs:
  - `flash_read()`
  - `flash_write()`
  - `flash_erase()`
  - `flash_crc32()`
  - `flash_dump_to_file()`

### Operational limits and behavior

- Most BSL transfer chunks are capped at 128 bytes.
- `flash_write()` only changes bits from `1 -> 0`; full erase is required before writing fresh firmware where `0 -> 1` is needed.
- Erasing flash removes valid app image and may leave chip booting only in BSL mode until reflashed.
- Dumping a full 0x58000 flash image can take minutes and may block normal Tasmota responsiveness during operation.

### Typical consumers

- `sonoff_zb_pro_flasher.be`
- `tubezb_cc2652_flasher.be`
- `cc2652_flasher_example.be`

---

## 2) intelhex.be

### Primary purpose

`intelhex.be` parses and validates Intel HEX firmware files, then streams each decoded data record to callbacks.

### Why this file exists

Firmware images are often distributed as `.hex` text records, not raw binary. This file centralizes parsing logic so flashing scripts can reuse it and apply device-specific verification before writing.

### Key responsibilities

- Opens a HEX file and parses line-by-line.
- Validates each record:
  - Basic format (`:` prefix).
  - Length consistency.
  - Supported record types (`00`, `01`, `02`, `04`).
  - Record checksum correctness.
- Builds absolute addresses by combining high address records (`02`/`04`) with data record offsets.
- Calls three user-supplied hooks:
  - `pre()` once before processing data.
  - `parse_cb(address, len, data, offset)` for each data record.
  - `post()` after parsing completes.
- Uses periodic `tasmota.yield()` to reduce long-loop blocking impact.

### Design pattern in this script

It implements a callback-driven streaming parser:

- Validation-only pass and flashing pass can reuse the same parser.
- No duplicated file decoding logic in device-specific scripts.
- Caller decides what to do with each data line (validate, write, checksum verification, etc.).

---

## 3) sonoff_zb_pro_flasher.be

### Primary purpose

`sonoff_zb_pro_flasher.be` is a device-specific workflow wrapper for Sonoff Zigbee Bridge Pro. It combines `intelhex` + `cc2652_flasher` into a safe, user-friendly flashing sequence.

### Why this file exists

Different boards require specific CCFG/bootloader pin settings to ensure BSL entry remains possible after flash. This script enforces Sonoff-specific validation before allowing programming.

### Key responsibilities

- Loads an Intel HEX firmware file (`load(filename)`).
- Runs a full check pass (`check()`):
  - Parses entire HEX.
  - Verifies CCFG word at `0x057FD8` matches Sonoff expected value `0xC5FE08C5`.
  - Marks firmware as checked/validated only if pass succeeds.
- Runs flash pass (`flash()`):
  - Refuses to flash if file was not checked/validated.
  - Starts low-level flasher.
  - Erases flash.
  - Streams each HEX data record into `flash_write()`.
  - Prints completion and a CRC32 snapshot.
- Supports full chip dump to file (`dump_to_file()`).

### Safety model

The check phase is mandatory before flash. This prevents writing firmware with wrong CCFG/BSL settings that could lock out normal serial recovery behavior.

---

## 4) tubezb_cc2652_flasher.be

### Primary purpose

`tubezb_cc2652_flasher.be` is the TubeZB-specific equivalent of the Sonoff wrapper, with different CCFG validation requirements.

### Why this file exists

TubeZB hardware expects a different bootloader pin configuration encoded in CCFG. This script ensures only compatible HEX images are accepted.

### Key responsibilities

- Same two-pass architecture as Sonoff script:
  - `check()` parse/validate pass.
  - `flash()` erase/program pass.
- Enforces TubeZB CCFG value:
  - CCFG address: `0x057FD8`
  - Expected value: `0xC5FE0FC5` (comment indicates DIO 15 for BSL).
- Adds additional payload sanity check during check callback:
  - Data length must be a multiple of 4.
- Supports firmware dump flow via low-level flasher.

### Relationship to Sonoff wrapper

Functionally almost identical structure, but with hardware-specific acceptance criteria (different `CCFG_reference` and one extra data-size validation).

---

## 5) cc2652_flasher_example.be

### Primary purpose

`cc2652_flasher_example.be` is a minimal usage example for directly testing the low-level flasher API.

### What it demonstrates

- Importing the low-level module.
- Entering BSL mode with verbose debug (`start(true)`).
- Reading and printing CCFG bytes from flash (`cmd_memory_read(0x57FD8,4)`).
- Computing and printing CRC32 for a flash region (`cmd_crc32(0x0,0x30000)`).

### Why this file is useful

It acts as a quick sanity test for wiring/protocol before running full erase/program flows.

---

## End-to-end workflow across scripts

Typical secure flashing flow is:

1. Choose board-specific wrapper (`sonoff_zb_pro_flasher` or `tubezb_cc2652_flasher`).
2. `load()` HEX file.
3. `check()` full parse and device-specific CCFG validation.
4. `flash()` to:
   - Start BSL session.
   - Erase flash.
   - Stream data records into flash writes.
   - Report completion + CRC.

Support utilities:

- `dump_to_file()` for backup/analysis.
- `cc2652_flasher_example` for low-level bring-up checks.

---

## Practical intent of this repository section

These scripts provide a complete in-device CC2652 firmware maintenance toolkit for Tasmota environments:

- Read/inspect existing firmware.
- Validate candidate firmware before riskier operations.
- Erase and reflash with hardware-specific safeguards.
- Produce binary dumps for backup, regression checks, or reverse engineering.

The separation into low-level protocol, generic HEX parsing, and board-specific policy keeps the code reusable while reducing the chance of flashing an incompatible image.
