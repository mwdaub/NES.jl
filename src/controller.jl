mutable struct Controller
  buttons::UInt8
  index::UInt8
  strobe::UInt8
  Controller() = new(0, 0, 0)
end

function read(c::Controller)::UInt8
  val = 0x00
  if c.index < 0x08 && (c.buttons & (0x01 << c.index)) != 0x00
    val = 0x01
  end
  c.index += 0x01
  if (c.strobe & 0x01) == 0x01
    c.index = 0x00
  end
  val
end

function write!(c::Controller, val::UInt8)
  c.strobe = val
  if (c.strobe & 0x01) == 0x01
    c.index = 0x00
  end
end
