#################################################################################
#
# class `stm32h743_usart_flasher`
#
# Low-level STM32 ROM USART bootloader driver (AN3155 style).
#
#################################################################################

import global

class stm32h743_usart_flasher
  var debug
  var rxbuf

  def init(rx, tx, boot0, nrst, baud)
    self.debug = false
    self.rxbuf = bytes()
  end

  def start(debug)
    if global.serflash == nil raise "value_error", "global.serflash not initialized, call autoexec.init()" end
    if type(global.bsl) != 'int' || type(global.rst) != 'int'
      raise "value_error", "global.bsl/global.rst not initialized, call autoexec.init()"
    end

    self.debug = bool(debug)
    print(format("FLH: stm32h743_usart_flasher using global.bsl=%i global.rst=%i", global.bsl, global.rst))
    self.enter_system_bootloader()
    self.sync()
  end

  def enter_system_bootloader()
    global.serflash.flush()
    gpio.digital_write(global.bsl, 1)
    gpio.digital_write(global.rst, 0)
    tasmota.delay(20)
    gpio.digital_write(global.rst, 1)
    # Reopen UART right after reset release (test path) using autoexec settings.
    global.serflash = serial(global.rx, global.tx, 115200, serial.SERIAL_8E1)
    global.serflash.flush()
    tasmota.delay(120)
  end

  def leave_system_bootloader()
    gpio.digital_write(global.bsl, 0)
    gpio.digital_write(global.rst, 0)
    tasmota.delay(20)
    gpio.digital_write(global.rst, 1)
    tasmota.delay(120)
  end

  def sync()
    global.serflash.flush()
    global.serflash.write(bytes("7F"))

    var due = tasmota.millis() + 300
    var last = -1
    var ok = false
    while !tasmota.time_reached(due)
      if global.serflash.available()
        var b = global.serflash.read()
        if size(b) == 0
          tasmota.delay(1)
          continue
        end

        # Consume all bytes from this chunk and stop on first ACK/NACK.
        for i:0..size(b)-1
          var v = b[i]
          last = v
          if v == 0x79
            ok = true
            break
          end
          if v == 0x1F raise "protocol_error", "sync: received NACK" end
        end
        if ok break end
      else
        tasmota.delay(1)
      end
    end

    if ok
      if self.debug print("FLH: sync OK") end
      return true
    end

    if last >= 0
      raise "protocol_error", format("sync: timeout waiting ACK, last=0x%02X", last)
    end
    raise "protocol_error", "sync: timeout waiting ACK (no response)"
  end

  # receive raw serial buffer and give up if timeout (CC2652-inspired)
  def recv_raw(timeout)
    var due = tasmota.millis() + timeout
    while !tasmota.time_reached(due)
      if global.serflash.available()
        var b = global.serflash.read()
        if self.debug print("rx:", b) end
        if size(b) > 0
          return b
        end
      end
      tasmota.delay(5)
    end
    raise "timeout_error", "serial timeout"
  end

  def recv_exact(sz, timeout)
    var out = bytes()

    if size(self.rxbuf) > 0
      out += self.rxbuf
      self.rxbuf = bytes()
      if size(out) >= sz
        var ret = out[0..sz-1]
        if size(out) > sz
          self.rxbuf = out[sz..]
        end
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
            if size(out) > sz
              self.rxbuf = out[sz..]
            end
            return ret
          end
        end
      end
      tasmota.delay(2)
    end
    raise "timeout_error", f"serial timeout waiting {sz} bytes"
  end

  def recv_byte(timeout)
    return self.recv_exact(1, timeout)[0]
  end

  def expect_ack(timeout, stage)
    var due = tasmota.millis() + timeout
    var last = bytes()
    while !tasmota.time_reached(due)
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

      if size(b) == 0
        continue
      end

      last = b
      if self.debug print("rx:", b) end

      for i:0..size(b)-1
        var v = b[i]
        if v == 0x00 || v == 0x7F
          continue
        end

        if v == 0x79
          if i + 1 < size(b)
            self.rxbuf += b[i+1..]
          end
          return true
        end

        if v == 0x1F
          if i + 1 < size(b)
            self.rxbuf += b[i+1..]
          end
          raise "protocol_error", format("%s: received NACK", stage)
        end

        if i + 1 < size(b)
          self.rxbuf += b[i+1..]
        end
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

  def send_cmd(cmd)
    var p = bytes("0000")
    p[0] = cmd & 0xFF
    p[1] = (~cmd) & 0xFF
    if self.debug print(format("FLH: cmd=0x%02X", cmd)) end
    global.serflash.write(p)
    self.expect_ack(500, format("send_cmd 0x%02X", cmd))
  end

  def send_addr(addr)
    var a = self._u32be_bytes(addr)
    var p = bytes()
    p += a
    p.add(self._xor_checksum(a))
    global.serflash.write(p)
    self.expect_ack(500, format("send_addr 0x%08X", addr))
  end

  def cmd_get()
    self.send_cmd(0x00)
    var n = self.recv_byte(500)
    var payload = self.recv_exact(n + 1, 500)
    self.expect_ack(500, "cmd_get payload")
    return payload
  end

  def cmd_get_version()
    self.send_cmd(0x01)
    var payload = self.recv_exact(3, 500)
    self.expect_ack(500, "cmd_get_version payload")
    return payload
  end

  def cmd_get_id()
    self.send_cmd(0x02)
    var n = self.recv_byte(500)
    var idb = self.recv_exact(n + 1, 500)
    self.expect_ack(500, "cmd_get_id payload")
    return idb
  end

  def cmd_read_memory(addr, len)
    if len <= 0 || len > 256
      raise "value_error", "len must be in range 1..256"
    end

    self.send_cmd(0x11)
    self.send_addr(addr)

    var p = bytes("0000")
    p[0] = (len - 1) & 0xFF
    p[1] = p[0] ^ 0xFF
    global.serflash.write(p)
    self.expect_ack(500, format("cmd_read_memory len=%i", len))

    return self.recv_exact(len, 1000)
  end

  def cmd_write_memory(addr, data)
    var len = size(data)
    if len <= 0 || len > 256
      raise "value_error", "data length must be in range 1..256"
    end

    self.send_cmd(0x31)
    self.send_addr(addr)

    var p = bytes()
    p.add((len - 1) & 0xFF)
    p += data
    p.add(self._xor_checksum(p))
    global.serflash.write(p)
    self.expect_ack(2000, format("cmd_write_memory addr=0x%08X len=%i", addr, len))
  end

  def cmd_extended_erase_mass()
    self.send_cmd(0x44)
    global.serflash.write(bytes("FFFF00"))
    self.expect_ack(30000, "cmd_extended_erase_mass")
  end

  def cmd_readout_unprotect()
    self.send_cmd(0x92)
    self.expect_ack(30000, "cmd_readout_unprotect")
  end

  def cmd_go(addr)
    self.send_cmd(0x21)
    self.send_addr(addr)
  end

end

return stm32h743_usart_flasher()
