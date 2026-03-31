#################################################################################
#
# STM32H743 flasher wrapper.
#
# Hardware must be initialized by autoexec/global before flashing.
#
#################################################################################

class esp32_stm32h743_flasher
  var core

  def init()
    import flasher_core
    self.core = flasher_core
  end

  def load(filename)
    self.core.load(filename)
  end

  # short alias: load
  def ld(filename)
    self.load(filename)
  end

  def check()
    self.core.check()
  end

  # short alias: check
  def chk()
    self.check()
  end

  def flash(debug)
    self.core.flash(debug)
  end

  # short alias: flash
  def fl(debug)
    self.flash(debug)
  end

  # one-shot helper: load + check + flash (hardware comes from autoexec/global)
  def run(filename, debug)
    self.load(filename)
    self.check()
    self.flash(debug)
  end
end

return esp32_stm32h743_flasher()

#-
# Example usage:
#
# import flasher
# flasher.ld("firmware.hex")
# flasher.chk()
# flasher.fl(true)
#
# shortest flow with defaults already set in this file:
# flasher.run("firmware.hex", true)
#
-#
