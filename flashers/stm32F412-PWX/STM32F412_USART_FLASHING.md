# STM32F412 PWX USART Flasher Notes

This document matches the scripts in this folder:
- `flasher.be`
- `intelhex.be`

## 1. What This Flasher Does

- Parses an Intel HEX file.
- Checks that all payload addresses are in STM32F412 flash range:
  - `0x08000000` to `0x080FFFFF`
- Enters STM32 system bootloader over USART.
- Performs mass erase.
- Writes flash content.
- Sends GO to flash start (`0x08000000`).
- Restores normal boot mode.

## 2. Hardware Pins Used By This Script

From `flasher.be` init:
- UART RX pin: `16`
- UART TX pin: `17`
- Boot select pin (`bsl`): `13`
- Reset pin (`rst`): `2`

Boot mode sequence used by script:
- Enter bootloader: `bsl=1`, pulse reset
- Leave bootloader: `bsl=0`, pulse reset

## 3. USART Settings and Protocol

- UART mode: `115200`, `8E1`
- Sync byte: `0x7F`
- ACK: `0x79`
- NACK: `0x1F`

Command framing follows STM32 USART ROM protocol (AN3155 style):
- `CMD`, `~CMD`
- Address + XOR checksum
- Payload + XOR checksum

## 4. Commands Used In This Implementation

- Get (supported commands + protocol version): `0x00`
- Get ID: `0x02`
- Write Memory: `0x31`
- Erase (auto-selected):
  - Extended Erase: `0x44` (mass erase `FFFF00`) when supported
  - Legacy Erase: `0x43` (mass erase `FF00`) fallback
- GO: `0x21`

## 5. Flash Write Strategy In This Script

The flasher repacks HEX payload into aligned 32-byte slots before writing.

Details:
- Slot base = `addr & ~0x1F`
- Slot offset = `addr & 0x1F`
- Missing bytes in a slot are kept as `0xFF`
- Each slot is written as one Write Memory operation

This avoids failures when HEX record sizes are fragmented or not naturally aligned to slot boundaries.

## 6. Berry Usage

```berry
import flasher as f
f.check("pwx12-legacy.hex")
or
import flasher as f
f.flash("pwx12-legacy.hex")
```

`check()` validates address range and payload presence before flashing.

## 7. Common Failure Hints

- No ACK after sync:
  - Verify UART wiring (cross TX/RX, shared GND)
  - Verify `8E1`
  - Verify boot/reset sequence and timing
- Erase/write NACK:
  - Retry from fresh bootloader entry
  - Confirm target really runs STM32 USART ROM bootloader on selected pins
