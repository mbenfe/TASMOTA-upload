#################################################################################
#
# class `stm32h743_flasher`
#
# High-level STM32H743 flashing workflow from Intel HEX over ROM USART bootloader.
#
#################################################################################

import global

class stm32h743_flasher
  static FLASH_START = 0x08000000
  static FLASH_END = 0x08200000      # exclusive, 2 MB window for H743 variants
  static CORE_VERSION = "2026-03-31-align-pack-v2-32b"

  var filename
  var file_checked
  var file_validated
  var file_hex
  var flasher
  var saw_flash_data
  var pending_slot_addr
  var pending_slot
  var pending_slot_has_data
  var check_records
  var check_bytes
  var flash_records
  var flash_bytes
  var flash_writes

  def init()
    self.file_checked = false
    self.file_validated = false
    self.saw_flash_data = false
    self.pending_slot_addr = -1
    self.pending_slot = nil
    self.pending_slot_has_data = false
    self.check_records = 0
    self.check_bytes = 0
    self.flash_records = 0
    self.flash_bytes = 0
    self.flash_writes = 0
  end

  def load(filename)
    import intelhex

    if type(filename) != 'string' raise "value_error", "invalid file name" end
    self.filename = filename
    self.file_hex = intelhex(filename)
    self.file_checked = false
    self.file_validated = false
    self.saw_flash_data = false
  end

  def check()
    self.file_hex.parse(/ -> self._check_pre(),
                        / address, len, data, offset -> self._check_cb(address, len, data, offset),
                        / -> self._check_post())
  end

  def flash(debug)
    if !self.file_checked
      raise "flash_error", "firmware not checked"
    end
    if !self.file_validated
      raise "flash_error", "firmware not validated"
    end
    if global.serflash == nil
      raise "value_error", "global.serflash not initialized, call autoexec.init()"
    end
    if type(global.bsl) != 'int' || type(global.rst) != 'int'
      raise "value_error", "global.bsl/global.rst not initialized, call autoexec.init()"
    end

    print(format("FLH: using global bsl=%i rst=%i", global.bsl, global.rst))

    import flasher_ll
    self.flasher = flasher_ll
    self.flasher.init(nil, nil, nil, nil, nil)

    print("FLH: step 1/7 - stm32h743 flashing started")

    print("FLH: step 2/7 - enter ROM bootloader and sync")
    self.flasher.start(debug)
    print("FLH: step 3/7 - read chip ID")
    var idb = self.flasher.cmd_get_id()
    print("FLH: chip id bytes=" + str(idb))

    print("FLH: step 4/7 - mass erase")
    self.flasher.cmd_extended_erase_mass()
    print("FLH: step 5/7 - program flash from HEX")

    self.file_hex.parse(/ -> self._flash_pre(),
                        / address, len, data, offset -> self._flash_cb(address, len, data, offset),
                        / -> self._flash_post())

    print("FLH: step 7/7 - stm32h743 flashing completed")
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
    if !self.saw_flash_data
      raise "value_error", "no flash payload found in HEX"
    end

    self.file_checked = true
    self.file_validated = true
    print(format("FLH: HEX check OK records=%i bytes=%i", self.check_records, self.check_bytes))
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
      self.flasher.cmd_write_memory(self.pending_slot_addr, self.pending_slot)
      self.flash_writes += 1
      if self.flash_writes <= 8 || (self.flash_writes & 0x7F) == 0
        print(format("FLH: write progress writes=%i addr=0x%08X len=32", self.flash_writes, self.pending_slot_addr))
      end
    end
    self.pending_slot_addr = -1
    self.pending_slot = nil
    self.pending_slot_has_data = false
  end

  def _flash_cb(addr, sz, data, offset)
    var payload = data[offset .. offset + sz - 1]
    if size(payload) != sz
      raise "flash_error", "incomplete payload"
    end

    self.flash_records += 1
    self.flash_bytes += sz
    if (self.flash_records & 0x3F) == 0
      print(format("FLH: parse progress records=%i bytes=%i last=0x%08X len=%i", self.flash_records, self.flash_bytes, addr, sz))
    end

    # Pack arbitrary HEX records into aligned 32-byte flash words for STM32H743.
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
      self.flasher.cmd_go(self.FLASH_START)
    except .. as e, m
      # Some targets jump immediately and may emit trailing noise bytes.
      # Flashing is already complete at this stage; keep this as warning only.
      print("FLH: warning: GO handshake non-fatal: " + m)
    end
    print("FLH: step 6.9/7 - restore normal boot mode")
    self.flasher.leave_system_bootloader()
  end

end

return stm32h743_flasher()
