#################################################################################
#
# STM32C071 flasher (single-file implementation).
#
# Depends only on:
# - global runtime (initialized in this class init)
# - intelhex parser
#
# User API:
#   import flasher as f
#   f.check("auto_mery.hex")
#   f.flash("auto_mery.hex")
#
#################################################################################

import global

class stm32c071_flasher
  static FLASH_START = 0x08000000
  static FLASH_END = 0x08010000
  static CORE_VERSION = "2026-04-09-c071-64k"

  var file_hex
  var checked_filename
  var saw_flash_data
  var check_records
  var check_bytes

  var rxbuf
  var pending_slot_addr
  var pending_slot
  var pending_slot_has_data
  var flash_records
  var flash_bytes
  var flash_writes
  var bl_version
  var bl_cmds

  def init()
    global.rx = 18
    global.tx = 19    
    gpio.pin_mode(global.rx,gpio.INPUT_PULLUP)
    gpio.pin_mode(global.tx,gpio.OUTPUT)

    global.serflash = serial(global.rx,global.tx,115200,serial.SERIAL_8E1)
    global.bsl = 6
    global.rst = 9
    gpio.pin_mode(global.bsl,gpio.OUTPUT)
    gpio.pin_mode(global.rst,gpio.OUTPUT)
    gpio.digital_write(global.bsl, 0)
    gpio.digital_write(global.rst, 1)
    print("flasher hardware setup completed")
   self.file_hex = nil
    self.checked_filename = nil
    self.saw_flash_data = false
    self.check_records = 0
    self.check_bytes = 0

    self.rxbuf = bytes()
    self.pending_slot_addr = -1
    self.pending_slot = nil
    self.pending_slot_has_data = false
    self.flash_records = 0
    self.flash_bytes = 0
    self.flash_writes = 0
    self.bl_version = nil
    self.bl_cmds = nil
  end

  def _load_hex(filename)
    import intelhex
    if type(filename) != 'string' raise "value_error", "invalid file name" end
    self.file_hex = intelhex(filename)
    self.saw_flash_data = false
  end

  def check(filename)
    self._load_hex(filename)
    self.file_hex.parse(/ -> self._check_pre(),
                        / address, len, data, offset -> self._check_cb(address, len, data, offset),
                        / -> self._check_post())
    self.checked_filename = filename
  end

  def flash(filename)
    if type(filename) != 'string' raise "value_error", "invalid file name" end
    if self.file_hex == nil || self.checked_filename != filename
      self._load_hex(filename)
      self.checked_filename = filename
    end

    if global.serflash == nil
      raise "value_error", "global.serflash not initialized"
    end
    if type(global.bsl) != 'int' || type(global.rst) != 'int'
      raise "value_error", "global.bsl/global.rst not initialized"
    end

    print("FLH: flashing started")
    self._start_link()
    self._cmd_get()
    print(format("FLH: bootloader version=0x%02X", self.bl_version))
    var idb = self._cmd_get_id()
    print("FLH: chip id bytes=" + str(idb))

    self._cmd_erase_mass_auto()

    self.file_hex.parse(/ -> self._flash_pre(),
                        / address, len, data, offset -> self._flash_cb(address, len, data, offset),
                        / -> self._flash_post())

    print("FLH: flashing completed")
  end

  def _check_pre()
    print("FLH: checking HEX file")
    print("FLH: core version " + self.CORE_VERSION)
    self.saw_flash_data = false
    self.check_records = 0
    self.check_bytes = 0
  end

  def _check_cb(addr, sz, data, offset)
    if addr < self.FLASH_START || addr + sz > self.FLASH_END
      raise "value_error", format("address out of flash range addr=0x%08X len=%i", addr, sz)
    end
    self.saw_flash_data = true
    self.check_records += 1
    self.check_bytes += sz
  end

  def _check_post()
    if !self.saw_flash_data raise "value_error", "no flash payload found in HEX" end
    print(format("FLH: HEX check OK records=%i bytes=%i", self.check_records, self.check_bytes))
  end

  def _start_link()
    self.rxbuf = bytes()
    self._enter_system_bootloader()
    self._sync()
  end

  def _enter_system_bootloader()
    global.serflash.flush()
    gpio.digital_write(global.bsl, 1)
    gpio.digital_write(global.rst, 0)
    tasmota.delay(20)
    gpio.digital_write(global.rst, 1)
    global.serflash = serial(global.rx, global.tx, 115200, serial.SERIAL_8E1)
    global.serflash.flush()
    tasmota.delay(120)
  end

  def _leave_system_bootloader()
    gpio.digital_write(global.bsl, 0)
    gpio.digital_write(global.rst, 0)
    tasmota.delay(20)
    gpio.digital_write(global.rst, 1)
    tasmota.delay(120)
  end

  def _sync()
    global.serflash.flush()
    global.serflash.write(bytes("7F"))

    var due = tasmota.millis() + 300
    var last = -1
    while !tasmota.time_reached(due)
      if global.serflash.available()
        var b = global.serflash.read()
        if size(b) == 0
          tasmota.delay(1)
          continue
        end

        for i:0..size(b)-1
          var v = b[i]
          last = v
          if v == 0x79 return true end
          if v == 0x1F raise "protocol_error", "sync: received NACK" end
        end
      else
        tasmota.delay(1)
      end
    end

    if last >= 0 raise "protocol_error", format("sync: timeout waiting ACK, last=0x%02X", last) end
    raise "protocol_error", "sync: timeout waiting ACK (no response)"
  end

  def _recv_exact(sz, timeout)
    var out = bytes()

    if size(self.rxbuf) > 0
      out += self.rxbuf
      self.rxbuf = bytes()
      if size(out) >= sz
        var ret = out[0..sz-1]
        if size(out) > sz self.rxbuf = out[sz..] end
        return ret
      end
    end

    var due = tasmota.millis() + timeout
    while !tasmota.time_reached(due)
      if global.serflash.available()
        var b = global.serflash.read()
        if size(b) > 0
          out += b
          if size(out) >= sz
            var ret = out[0..sz-1]
            if size(out) > sz self.rxbuf = out[sz..] end
            return ret
          end
        end
      end
      tasmota.delay(2)
    end
    raise "timeout_error", f"serial timeout waiting {sz} bytes"
  end

  def _recv_byte(timeout)
    return self._recv_exact(1, timeout)[0]
  end

  def _expect_ack(timeout, stage)
    var due = tasmota.millis() + timeout
    var last = bytes()
    var defer = 16
    while !tasmota.time_reached(due)
      defer = defer - 1
      if defer <= 0
        tasmota.yield()
        defer = 16
      end

      var b = bytes()
      if size(self.rxbuf) > 0
        b = self.rxbuf
        self.rxbuf = bytes()
      elif global.serflash.available()
        b = global.serflash.read()
      else
        tasmota.delay(2)
        continue
      end

      if size(b) == 0 continue end
      last = b

      for i:0..size(b)-1
        var v = b[i]
        if v == 0x00 || v == 0x7F continue end

        if v == 0x79
          if i + 1 < size(b) self.rxbuf += b[i+1..] end
          return true
        end

        if v == 0x1F
          if i + 1 < size(b) self.rxbuf += b[i+1..] end
          raise "protocol_error", format("%s: received NACK", stage)
        end

        if i + 1 < size(b) self.rxbuf += b[i+1..] end
        raise "protocol_error", format("%s: expected ACK/NACK got 0x%02X", stage, v)
      end
    end

    if size(last) > 0
      raise "protocol_error", format("%s: expected ACK/NACK timeout, last=%s", stage, str(last))
    end
    raise "protocol_error", format("%s: expected ACK/NACK timeout (no response)", stage)
  end

  static def _u32be_bytes(v)
    var b = bytes("00000000")
    b[0] = (v >> 24) & 0xFF
    b[1] = (v >> 16) & 0xFF
    b[2] = (v >> 8) & 0xFF
    b[3] = v & 0xFF
    return b
  end

  static def _xor_checksum(b)
    var c = 0
    for i:0..size(b)-1
      c = c ^ b[i]
    end
    return c & 0xFF
  end

  def _send_cmd(cmd)
    var p = bytes("0000")
    p[0] = cmd & 0xFF
    p[1] = (~cmd) & 0xFF
    global.serflash.write(p)
    self._expect_ack(500, format("send_cmd 0x%02X", cmd))
  end

  def _send_addr(addr)
    var a = self._u32be_bytes(addr)
    var p = bytes()
    p += a
    p.add(self._xor_checksum(a))
    global.serflash.write(p)
    self._expect_ack(500, format("send_addr 0x%08X", addr))
  end

  def _cmd_get_id()
    self._send_cmd(0x02)
    var n = self._recv_byte(500)
    var idb = self._recv_exact(n + 1, 500)
    self._expect_ack(500, "cmd_get_id payload")
    return idb
  end

  def _cmd_get()
    self._send_cmd(0x00)
    var n = self._recv_byte(500)
    var payload = self._recv_exact(n + 1, 500)
    self._expect_ack(500, "cmd_get payload")

    if size(payload) <= 0
      raise "protocol_error", "cmd_get: empty payload"
    end

    self.bl_version = payload[0]
    self.bl_cmds = payload
  end

  def _supports_cmd(cmd)
    if self.bl_cmds == nil || size(self.bl_cmds) <= 1
      return false
    end
    for i:1..size(self.bl_cmds)-1
      if self.bl_cmds[i] == (cmd & 0xFF)
        return true
      end
    end
    return false
  end

  def _cmd_write_memory(addr, data)
    var len = size(data)
    if len <= 0 || len > 256
      raise "value_error", "data length must be in range 1..256"
    end

    self._send_cmd(0x31)
    self._send_addr(addr)

    var p = bytes()
    p.add((len - 1) & 0xFF)
    p += data
    p.add(self._xor_checksum(p))
    global.serflash.write(p)
    self._expect_ack(2000, format("cmd_write_memory addr=0x%08X len=%i", addr, len))
  end

  def _cmd_extended_erase_mass()
    self._send_cmd(0x44)
    global.serflash.write(bytes("FFFF00"))
    self._expect_ack(30000, "cmd_extended_erase_mass")
  end

  def _cmd_erase_mass_legacy()
    self._send_cmd(0x43)
    global.serflash.write(bytes("FF00"))
    self._expect_ack(30000, "cmd_erase_mass_legacy")
  end

  def _cmd_erase_mass_auto()
    if self._supports_cmd(0x44)
      print("FLH: erase command=0x44 (extended erase)")
      self._cmd_extended_erase_mass()
      return
    end
    if self._supports_cmd(0x43)
      print("FLH: erase command=0x43 (legacy erase)")
      self._cmd_erase_mass_legacy()
      return
    end
    raise "protocol_error", "no supported erase command (0x44/0x43)"
  end

  def _cmd_go(addr)
    self._send_cmd(0x21)
    self._send_addr(addr)
  end

  def _flash_pre()
    self.pending_slot_addr = -1
    self.pending_slot = nil
    self.pending_slot_has_data = false
    self.flash_records = 0
    self.flash_bytes = 0
    self.flash_writes = 0
    print("FLH: step 6/7 - writing aligned 32-byte flash words")
  end

  def _flush_pending_slot()
    if self.pending_slot != nil && self.pending_slot_has_data
      self._cmd_write_memory(self.pending_slot_addr, self.pending_slot)
      self.flash_writes += 1
    end
    self.pending_slot_addr = -1
    self.pending_slot = nil
    self.pending_slot_has_data = false
  end

  def _flash_cb(addr, sz, data, offset)
    if addr < self.FLASH_START || addr + sz > self.FLASH_END
      raise "value_error", format("address out of flash range addr=0x%08X len=%i", addr, sz)
    end

    var payload = data[offset .. offset + sz - 1]
    if size(payload) != sz raise "flash_error", "incomplete payload" end

    self.flash_records += 1
    self.flash_bytes += sz

    for i:0..sz-1
      var a = addr + i
      var slot_addr = a & ~0x1F
      var slot_off = a & 0x1F

      if slot_addr != self.pending_slot_addr
        self._flush_pending_slot()
        self.pending_slot_addr = slot_addr
        self.pending_slot = bytes("FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF")
      end

      self.pending_slot[slot_off] = payload[i]
      self.pending_slot_has_data = true
    end
    tasmota.yield()
  end

  def _flash_post()
    self._flush_pending_slot()
    print(format("FLH: write summary records=%i bytes=%i aligned_writes=%i", self.flash_records, self.flash_bytes, self.flash_writes))
    print("FLH: step 6.5/7 - jump to user firmware")
    try
      self._cmd_go(self.FLASH_START)
    except .. as e, m
      print("FLH: warning: GO handshake non-fatal: " + m)
    end
    print("FLH: step 6.9/7 - restore normal boot mode")
    self._leave_system_bootloader()
  end

end

return stm32c071_flasher()
