# parse intelhex file
#
# local copy for STM32 flasher workflows

class intelhex
  var filename
  var f
  var file_parsed
  var file_validated

  def init(filename)
    self.filename = str(filename)
    self.file_parsed = false
    self.file_validated = true
  end

  def close()
    if self.f != nil
      self.f.close()
      self.f = nil
    end
  end

  def parse(pre, parse_cb, post)
    try
      self.f = open(self.filename, "rb")
      self.file_parsed = true
      pre()
      self.munch_line(parse_cb)
      post()
    except .. as e, m
      self.close()
      self.file_validated = false
      raise e, m
    end

    self.close()
  end

  def munch_line(parse_cb)
    import crc
    var crc_sum = crc.sum
    var tas = tasmota
    var yield = tasmota.yield

    var offset_high = 0
    var offset_low = 0
    var b = bytes()
    var b_get = b.get
    var b_fromhex = b.fromhex
    var self_f = self.f
    var readline = self_f.readline
    var defer = 10

    while true
      defer = defer - 1
      if defer <= 0
        yield(tas)
        defer = 10
      end

      var line = readline(self_f)
      if line[-1] == '\n' line = line[0..-2] end
      if line[-1] == '\r' line = line[0..-2] end

      if line == "" raise "value_error", "unexpected end of file" end
      if line[0] != ":" continue end

      b = b_fromhex(b, line, 1)
      var sz = b[0]
      if size(b) != sz + 5
        raise "value_error", f"invalid size for line: {line}"
      end

      var record_type = b[3]
      if record_type != 0 && record_type != 1 && record_type != 2 && record_type != 3 && record_type != 4 && record_type != 5
        raise "value_error", f"unsupported record_type: {record_type}"
      end

      offset_low = b_get(b, 1, -2)
      var checksum = crc_sum(b)
      if checksum != 0 raise "value_error", f"invalid checksum 0x{checksum:02X}" end

      if record_type == 1
        break
      elif record_type == 0
        var address = offset_high + offset_low
        parse_cb(address, sz, b, 4)
      elif record_type == 2
        if offset_low != 0 raise "value_error", "offset_low not null for cmd 02" end
        offset_high = b_get(b, 4, -2) << 4
      elif record_type == 4
        if offset_low != 0 raise "value_error", "offset_low not null for cmd 04" end
        offset_high = b_get(b, 4, -2) << 16
      elif record_type == 3
        # Start Segment Address record (CS:IP). Not needed for flash payload programming.
        if offset_low != 0 raise "value_error", "offset_low not null for cmd 03" end
        if sz != 4 raise "value_error", "invalid size for cmd 03 (expected 4)" end
      elif record_type == 5
        # Start Linear Address record (EIP). Not needed for flash payload programming.
        if offset_low != 0 raise "value_error", "offset_low not null for cmd 05" end
        if sz != 4 raise "value_error", "invalid size for cmd 05 (expected 4)" end
      end
    end
  end
end

return intelhex
