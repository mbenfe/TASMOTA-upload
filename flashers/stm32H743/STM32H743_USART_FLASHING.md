# STM32H743 USART Flashing Checklist

Source references used for this checklist:
- AN2606: STM32H74xxx/75xxx system memory boot mode and interface mapping
- AN3155: USART bootloader protocol framing and command flow

## 1. Hardware Setup

- Connect host UART and target UART with crossed data lines:
  - Host TX -> STM32 RX
  - Host RX -> STM32 TX
  - GND <-> GND
- Use one supported bootloader USART on STM32H743:
  - USART1: PA9 (TX), PA10 (RX)
  - USART1 alternate: PB14 (TX), PB15 (RX)
  - USART2: PA2 (TX), PA3 (RX)
  - USART3: PB10 (TX), PB11 (RX)

Notes:
- For USART1 on PB14/PB15, send two sync bytes and keep baud rate <= 115200.
- Keep unused bootloader-detection pins in a defined state during startup to avoid false interface detection.

## 2. Enter System Bootloader

- Assert BOOT0 for system memory boot mode (AN2606 Pattern 10 for H74/H75 family).
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
5. Erase (usually Extended Erase 0x44 on modern protocol versions).
6. Write Memory (0x31) in chunks to user flash.
7. Optional verify:
   - Read Memory (0x11), or
   - Checksum-related command if your reported version supports it.
8. Go (0x21) to user flash start address (commonly 0x08000000).

## 6. Exit Bootloader

- Deassert BOOT0 (normal boot mode).
- Reset MCU.
- Application should start from internal flash.

## 7. STM32H743 Specific Cautions

- STM32H74/75 USART bootloader protocol is listed as USART V3.1 in AN2606.
- Flash programming alignment constraints for STM32H7 (except H7R/H7S) are 8-byte aligned writes.
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
2. Ensure hardware was initialized at boot by autoexec/global.
3. Load your Intel HEX file.
4. Validate the HEX.
5. Flash with debug enabled.

Command sequence:

import flasher as f
f.ld("mery_auto.hex")
f.chk()
f.fl(true)

## 10. Alignment Error: write alignment violation

Symptom example:
- write alignment violation addr=0x08...... len=12 (need 8-byte aligned)

Cause:
- Intel HEX data records are often 16 bytes, but they can also be 12 bytes or other sizes.
- STM32H743 flash programming requires 8-byte aligned writes.
- A strict per-record alignment check can fail even when the firmware is valid.

Current workspace behavior:
- The flasher core now repacks HEX records into 8-byte aligned flash writes internally.
- Missing bytes in a partial 8-byte slot are filled with 0xFF before write.

Result:
- Valid HEX files with non-8-byte record lengths (such as 12-byte records) are accepted and flashed correctly.
