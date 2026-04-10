# STM32C071 USART Flashing Checklist

Source references used for this checklist:
- AN2606: STM32C0 system memory boot mode and interface mapping
- AN3155: USART bootloader protocol framing and command flow

## 1. Hardware Setup

- Connect host UART and target UART with crossed data lines:
  - Host TX -> STM32 RX
  - Host RX -> STM32 TX
  - GND <-> GND
- Use a USART interface supported by STM32C071 system bootloader (see AN2606 for exact pins/instances on your package/board).

Notes:
- Keep unused bootloader-detection pins in a defined state during startup to avoid false interface detection.

## 2. Enter System Bootloader

- Assert BOOT0 for system memory boot mode for STM32C071 (see AN2606).
- Reset or power-cycle the MCU.
- Keep BOOT0 asserted until host connection is established.

## 3. USART Framing and Handshake (AN3155)

- UART framing must be 8E1:
  - 8 data bits
  - Even parity
  - 1 stop bit
- Send sync byte 0x7F.
- Wait for response:
  - ACK = 0x79
  - NACK = 0x1F

## 4. Packet Rules

- Commands are sent as CMD byte + bitwise complement (~CMD).
- For payload packets, use XOR checksum as defined by AN3155.
- If checksum/parity is invalid, bootloader returns NACK.

## 5. Recommended Command Sequence

1. Get (0x00) to read supported commands and protocol version.
2. Get Version (0x01).
3. Get ID (0x02) and verify expected device ID family.
4. If needed, Readout Unprotect (0x92):
   - This can trigger mass erase and reset.
   - Reconnect and repeat handshake after reset.
5. Erase (prefer Extended Erase 0x44 when supported; fallback to legacy Erase 0x43 if 0x44 is not advertised by GET).
6. Write Memory (0x31) in chunks to user flash.
7. Optional verify:
   - Read Memory (0x11), or
   - Checksum-related command if your reported version supports it.
8. Go (0x21) to user flash start address (commonly 0x08000000).

## 6. Exit Bootloader

- Deassert BOOT0 (normal boot mode).
- Reset MCU.
- Application should start from internal flash.

## 7. STM32C071 Specific Cautions

- STM32C071 flash size for this profile is 64 KBytes (0x08000000..0x0800FFFF).
- Keep your HEX payload inside this range; out-of-range records must be rejected.
- Bootloader versions differ in known limitations. Always check the returned version first and verify programmed content.

## 8. Practical Recovery Tips

- If no ACK after 0x7F:
  - Recheck 8E1 framing.
  - Recheck BOOT0 and reset timing.
  - Swap TX/RX lines.
  - Lower baud rate.
- If erase/write fails:
  - Check active protection state.
  - Try Readout Unprotect, reconnect, and retry full flow.
- If Go does not start app:
  - Ensure valid vector table and reset handler at flash start.
  - Ensure BOOT0 is back to normal boot state before reset.

## 9. Use This Workspace (Berry)

From the Tasmota Berry console:

1. Import the STM32 flasher wrapper.
2. Load your Intel HEX file.
3. Validate the HEX.
4. Flash.

Command sequence (two commands):

import flasher as f
f.check("auto_mery.hex")

import flasher as f
f.flash("auto_mery.hex")

## 10. Alignment Error: write alignment violation

Symptom example:
- write alignment violation addr=0x08...... len=12 (need 8-byte aligned)

Cause:
- Intel HEX data records are often 16 bytes, but they can also be 12 bytes or other sizes.
- This flasher implementation writes aligned 32-byte chunks internally before sending write commands.
- A strict per-record alignment check can fail even when the firmware is valid.

Current workspace behavior:
- The flasher core repacks HEX records into 32-byte aligned flash slots internally.
- Missing bytes in a partial 32-byte slot are filled with 0xFF before write.

Result:
- Valid HEX files with non-8-byte record lengths (such as 12-byte records) are accepted and flashed correctly.
