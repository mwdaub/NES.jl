using Match
using Printf

import Base: read

function mapperstep!(console::Console{T}) where {T <: Mapper}
end

# Mapper 1

mutable struct Mapper1 <: Mapper
  shiftRegister::UInt8
  control::UInt8
  prgMode::UInt8
  chrMode::UInt8
  prgBank::UInt8
  chrBank0::UInt8
  chrBank1::UInt8
  prgOffsets::Vector{Int32}
  chrOffsets::Vector{Int32}

  function Mapper1(cartridge::Cartridge)
    m = new(0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, zeros(Int32, 2), zeros(Int32, 2))
    @inbounds m.prgOffsets[2] = prgbankoffset(m, cartridge, Int32(-1))
    m
  end
end

function read(m::Mapper1, cartridge::Cartridge, address::UInt16)::UInt8
  if address < 0x2000
    bank = address ÷ 0x1000
    offset = address & 0x0FFF
    @inbounds cartridge.CHR[m.chrOffsets[bank + 1] + offset + 1]
  elseif address >= 0x8000
    address = address - 0x8000
    bank = address ÷ 0x4000
    offset = address & 0x3FFF
    @inbounds cartridge.PRG[m.prgOffsets[bank + 1] + offset + 1]
  elseif (address >= 0x6000)
    @inbounds cartridge.SRAM[address - 0x6000 + 1]
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper1 read at address: 0x%04X", address)
    0x00
  end
end

function write!(m::Mapper1, cartridge::Cartridge, address::UInt16, val::UInt8)
  if address < 0x2000
    bank = address ÷ 0x1000
    offset = address & 0x0FFF
    @inbounds cartridge.CHR[m.chrOffsets[bank + 1] + offset + 1] = val
  elseif address >= 0x8000
    loadregister!(m, cartridge, address, val)
  elseif address >= 0x6000
    @inbounds cartridge.SRAM[address - 0x6000 + 1] = val
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper1 write at address: 0x%04X", address)
  end
end

function loadregister!(m::Mapper1, cartridge::Cartridge, address::UInt16, val::UInt8)
  if (val & 0x80) == 0x80
    m.shiftRegister = 0x10
    writecontrol!(m, cartridge, m.control | 0x0C)
  else
    complete = (m.shiftRegister & 0x01) == 0x01
    m.shiftRegister = m.shiftRegister >> 0x01
    m.shiftRegister = m.shiftRegister | ((val & 0x01) << 0x04)
    if complete
      writeregister!(m, cartridge, address, m.shiftRegister)
      m.shiftRegister = 0x10
    end
  end
end

function writeregister!(m::Mapper1, cartridge::Cartridge, address::UInt16, val::UInt8)
  if address <= 0x9FFF
    writecontrol!(m, cartridge, val)
  elseif address <= 0xBFFF
    writechrbank0!(m, cartridge, val)
  elseif address <= 0xDFFF
    writechrbank1!(m, cartridge, val)
  else
    writeprgbank!(m, cartridge, val)
  end
end

# Control (internal, $8000-$9FFF)
function writecontrol!(m::Mapper1, cartridge::Cartridge, val::UInt8)
  m.control = val
  m.chrMode = (val >> 0x04) & 0x01
  m.prgMode = (val >> 0x02) & 0x03
  mirror = val & 0x03
  @match mirror begin
    0 => begin cartridge.mirror = UInt8(Single0::MirrorModes) end
    1 => begin cartridge.mirror = UInt8(Single1::MirrorModes) end
    2 => begin cartridge.mirror = UInt8(Vertical::MirrorModes) end
    3 => begin cartridge.mirror = UInt8(Horizontal::MirrorModes) end
    _ => throw(ErrorException("Unreachable code."))
  end
  updateoffsets!(m, cartridge)
end

# CHR bank 0 (internal, $A000-$BFFF)
function writechrbank0!(m::Mapper1, cartridge::Cartridge, val::UInt8)
  m.chrBank0 = val
  updateoffsets!(m, cartridge)
end

# CHR bank 1 (internal, $C000-$DFFF)
function writechrbank1!(m::Mapper1, cartridge::Cartridge, val::UInt8)
  m.chrBank1 = val
  updateoffsets!(m, cartridge)
end

# PRG bank (internal, $E000-$FFFF)
function writeprgbank!(m::Mapper1, cartridge::Cartridge, val::UInt8)
  m.prgBank = val & 0x0F
  updateoffsets!(m, cartridge)
end

function prgbankoffset(m::Mapper1, cartridge::Cartridge, index::Int32)::Int32
  if index >= 0x80
    index -= 0x100
  end
  index %= length(cartridge.PRG) >> 14
  offset = index * 0x4000
  if offset < 0
    offset += length(cartridge.PRG)
  end
  offset
end

function chrbankoffset(m::Mapper1, cartridge::Cartridge, index::Int32)::Int32
  if index >= 0x80
    index -= 0x100
  end
  index %= length(cartridge.CHR) >> 12
  offset = index * 0x1000
  if offset < 0
    offset += length(cartridge.CHR)
  end
  offset
end

# PRG ROM bank mode (0, 1: switch 32 KB at $8000, ignoring low bit of bank number;
#                    2: fix first bank at $8000 and switch 16 KB bank at $C000;
#                    3: fix last bank at $C000 and switch 16 KB bank at $8000)
# CHR ROM bank mode (0: switch 8 KB at a time; 1: switch two separate 4 KB banks)
function updateoffsets!(m::Mapper1, cartridge::Cartridge)
  @match m.prgMode begin
    0 => begin
      @inbounds m.prgOffsets[1] = prgbankoffset(m, cartridge::Cartridge, Int32(m.prgBank & 0xFE))
      @inbounds m.prgOffsets[2] = prgbankoffset(m, cartridge::Cartridge, Int32(m.prgBank | 0x01))
    end
    1 => begin
      @inbounds m.prgOffsets[1] = prgbankoffset(m, cartridge::Cartridge, Int32(m.prgBank & 0xFE))
      @inbounds m.prgOffsets[2] = prgbankoffset(m, cartridge::Cartridge, Int32(m.prgBank | 0x01))
    end
    2 => begin
      @inbounds m.prgOffsets[1] = 0
      @inbounds m.prgOffsets[2] = prgbankoffset(m, cartridge::Cartridge, Int32(m.prgBank))
    end
    3 => begin
      @inbounds m.prgOffsets[1] = prgbankoffset(m, cartridge::Cartridge, Int32(m.prgBank))
      @inbounds m.prgOffsets[2] = prgbankoffset(m, cartridge::Cartridge, Int32(-1))
    end
    _ => throw(ErrorException("Unreachable code."))
  end
  @match m.chrMode begin
    0 => begin
      @inbounds m.chrOffsets[1] = chrbankoffset(m, cartridge::Cartridge, Int32(m.chrBank0 & 0xFE))
      @inbounds m.chrOffsets[2] = chrbankoffset(m, cartridge::Cartridge, Int32(m.chrBank0 | 0x01))
    end
    1 => begin
      @inbounds m.chrOffsets[1] = chrbankoffset(m, cartridge::Cartridge, Int32(m.chrBank0))
      @inbounds m.chrOffsets[2] = chrbankoffset(m, cartridge::Cartridge, Int32(m.chrBank1))
    end
    _ => throw(ErrorException("Unreachable code."))
  end
end

# Mapper 2

mutable struct Mapper2 <: Mapper
  prgBanks::Int32
  prgBank1::Int32
  prgBank2::Int32

  function Mapper2(cartridge::Cartridge)
    m = new(0, 0, 0)
    m.prgBanks = length(cartridge.PRG) ÷ 0x4000
    m.prgBank2 = m.prgBanks - Int32(1)
    m
  end
end


function read(m::Mapper2, cartridge::Cartridge, address::UInt16)::UInt8
  if address < 0x2000
    cartridge.CHR[address + 1]
  elseif address >= 0xC000
    index = m.prgBank2 * Int32(0x4000) + Int32(address - 0xC000)
    cartridge.PRG[index + 1]
  elseif address >= 0x8000
    index = m.prgBank1 * Int32(0x4000) + Int32(address - 0x8000)
    cartridge.PRG[index + 1]
  elseif address >= 0x6000
    index = address - 0x6000
    cartridge.SRAM[index + 1]
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper2 read at address: 0x%04X", address)
    0x00
  end
end

function write!(m::Mapper2, cartridge::Cartridge, address::UInt16, val::UInt8)
  if address < 0x2000
    cartridge.CHR[address + 1] = val
  elseif address >= 0x8000
    m.prgBank1 = Int32(val) % m.prgBanks
  elseif address >= 0x6000
    index = address - 0x6000
    cartridge.SRAM[index + 1] = val
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper2 write at address: 0x%04X", address)
  end
end

# Mapper 225

mutable struct Mapper225 <: Mapper
  chrBank::Int32
  prgBank1::Int32
  prgBank2::Int32

  Mapper225() = new(0, 0, 0)
end

function read(m::Mapper225, cartridge::Cartridge, address::UInt16)::UInt8
  if address < 0x2000
    index = m.chrBank * Int32(0x2000) + Int32(address)
    cartridge.CHR[index + 1]
  elseif address >= 0xC000
    index = m.prgBank2 * Int32(0x4000) + Int32(address-0xC000)
    cartridge.PRG[index + 1]
  elseif address >= 0x8000
    index = m.prgBank1 * Int32(0x4000) + Int32(address - 0x8000)
    cartridge.PRG[index + 1]
  elseif address >= 0x6000
    index = address - 0x6000
    cartridge.SRAM[index + 1]
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper225 read at address: 0x%04X", address)
    0
  end
end

function write!(m::Mapper225, cartridge::Cartridge, address::UInt16, val::UInt8)
  if address < 0x8000
    return
  end

  A = Int32(address)
  bank = (A >> 14) & 1
  m.chrBank = (A & 0x3f) | (bank << 6)
  prg = ((A >> 6) & 0x3f) | (bank << 6)
  mode = (A >> 12) & 1
  if mode == 1
    m.prgBank1 = prg
    m.prgBank2 = prg
  else
    m.prgBank1 = prg
    m.prgBank2 = prg + 1
  end
  mirr = (A >> 13) & 1
  if mirr == 1
    cartridge.mirror = UInt8(Horizontal::MirrorModes)
  else
    cartridge.mirror = UInt8(Vertical::MirrorModes)
  end
end

# Mapper 3

mutable struct Mapper3 <: Mapper
  chrBank::Int32
  prgBank1::Int32
  prgBank2::Int32

  function Mapper3(cartridge::Cartridge)
    m = new(0, 0, 0)
    m.prgBank2 = length(cartridge.PRG) ÷ 0x4000 - 1;
    m
  end
end

function read(m::Mapper3, cartridge::Cartridge, address::UInt16)::UInt8
  if address < 0x2000
    index = m.chrBank * Int32(0x2000) + address
    cartridge.CHR[index + 1]
  elseif address >= 0xC000
    index = m.prgBank2 * Int32(0x4000) + Int32(address - 0xC000)
    cartridge.PRG[index + 1]
  elseif address >= 0x8000
    index = m.prgBank1 * Int32(0x4000) + Int32(address - 0x8000)
    cartridge.PRG[index + 1]
  elseif address >= 0x6000
    index = address - 0x6000
    cartridge.SRAM[index + 1]
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper3 read at address: 0x%04X", address)
    0
  end
end

function write!(m::Mapper3, cartridge::Cartridge, address::UInt16, val::UInt8)
  if address < 0x2000
    index = m.chrBank * Int32(0x2000) + address
    cartridge.CHR[index + 1] = val
  elseif address >= 0x8000
    m.chrBank = val & 3
  elseif address >= 0x6000
    index = address - 0x6000
    cartridge.SRAM[index + 1] = val
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper3 write at address: 0x%04X", address)
  end
end

# Mapper4

mutable struct Mapper4 <: Mapper
  reg::UInt8
  registers::Vector{UInt8}
  prgMode::UInt8
  chrMode::UInt8
  prgOffsets::Vector{Int32}
  chrOffsets::Vector{Int32}
  reload::UInt8
  counter::UInt8
  irqEnable::Bool

  function Mapper4(cartridge::Cartridge)
    m = new(0x00, zeros(UInt8, 8), 0x00, 0x00, zeros(Int32, 4), zeros(Int32, 8), 0x00, 0x00, false)
    m.prgOffsets[1] = prgbankoffset(m, cartridge, Int32(0))
    m.prgOffsets[2] = prgbankoffset(m, cartridge, Int32(1))
    m.prgOffsets[3] = prgbankoffset(m, cartridge, Int32(-2))
    m.prgOffsets[4] = prgbankoffset(m, cartridge, Int32(-1))
    m
  end
end

function mapperstep!(console::Console{Mapper4})
  m = console.mapper
  ppu = console.ppu
  if ppu.cycle != 280 # TODO: this *should* be 260
    return
  end
  if (ppu.scanline > 239) && (ppu.scanline < 261)
    return
  end
  if (ppu.flagShowBackground == 0) && (ppu.flagShowSprites == 0)
    return
  end
  handlescanline(m, console)
end

function read(m::Mapper4, cartridge::Cartridge, address::UInt16)::UInt8
  if address < 0x2000
    bank = address >> 10
    offset = address & 0x03FF
    cartridge.CHR[m.chrOffsets[bank + 1] + offset + 1]
  elseif address >= 0x8000
    address = address - 0x8000
    bank = address >> 13
    offset = address & 0x1FFF
    cartridge.PRG[m.prgOffsets[bank + 1] + offset + 1]
  elseif address >= 0x6000
    cartridge.SRAM[address - 0x6000 + 1]
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper4 read at address: 0x%04X", address)
    0
  end
end

function write!(m::Mapper4, cartridge::Cartridge, address::UInt16, val::UInt8)
  if address < 0x2000
    bank = address >> 10
    offset = address & 0x03FF
    cartridge.CHR[m.chrOffsets[bank + 1] + offset + 1] = val
  elseif address >= 0x8000
    writeregister!(m, cartridge, address, val)
  elseif address >= 0x6000
    cartridge.SRAM[address - 0x6000 + 1] = val
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper4 write at address: 0x%04X", address)
  end
end

function handlescanline!(m::Mapper4, console::Console)
  if m.counter == 0
    m.counter = m.reload
  else
    m.counter -= 1
    if (m.counter == 0) && m.irqEnable
      triggerirq(console.cpu)
    end
  end
end

function writeregister!(m::Mapper4, cartridge::Cartridge, address::UInt16, val::UInt8)
  if (address <= 0x9FFF) && (address & 1 == 0)
    writebankselect!(m, cartridge, val)
  elseif (address <= 0x9FFF) && (address & 1 == 1)
    writebankdata!(m, cartridge, val)
  elseif (address <= 0xBFFF) && (address & 1 == 0)
    writemirror!(m, cartridge, val)
  elseif (address <= 0xBFFF) && (address & 1 == 1)
    writeprotect!(m, val)
  elseif (address <= 0xDFFF) && (address & 1 == 0)
    writeirqlatch!(m, val)
  elseif (address <= 0xDFFF) && (address & 1 == 1)
    writeirqreload!(m, val)
  elseif address & 1 == 0
    writeirqdisable!(m, val)
  elseif address & 1 == 1
    writeirqenable!(m, val)
  end
end

function writebankselect!(m::Mapper4, cartridge::Cartridge, val::UInt8)
  m.prgMode = (val >> 6) & 1
  m.chrMode = (val >> 7) & 1
  m.reg = val & 7
  updateoffsets!(m, cartridge)
end

function writebankdata!(m::Mapper4, cartridge::Cartridge, val::UInt8)
  m.registers[reg] = val
  updateoffsets!(m, cartridge)
end

function writemirror!(m::Mapper4, cartridge::Cartridge, val::UInt8)
  c = val & 1
  @match c begin
    0 => begin
      cartridge.mirror = UInt8(Vertical::MirrorModes)
    end
    1 => begin
      cartridge.mirror = UInt8(Horizontal::MirrorModes)
    end
    _ => throw(ErrorException("Unreachable code."))
  end
end

function writeprotect!(m::Mapper4, val::UInt8)
  # Not sure why this function exists...
  return
end

function writeirqlatch!(m::Mapper4, val::UInt8)
  m.reload = val
end

function writeirqreload!(m::Mapper4, val::UInt8)
  m.counter = 0
end

function writeirqdisable!(m::Mapper4, val::UInt8)
  m.irqEnable = false
end

function writeirqenable!(m::Mapper4, val::UInt8)
  m.irqEnable = true
end

function prgbankoffset(m::Mapper4, cartridge::Cartridge, index::Int32)::Int32
  if index >= 0x80
    index -= 0x100
  end
  index %= length(cartridge.PRG) >> 13
  offset = index * Int32(0x2000)
  if offset < 0
    offset += length(cartridge.PRG)
  end
  offset
end

function chrbankoffset(m::Mapper4, cartridge::Cartridge, index::Int32)::Int32
  if index >= 0x80
    index -= 0x100
  end
  index %= length(cartridge.CHR) >> 10
  offset = index * Int32(0x0400)
  if offset < 0
    offset += length(cartridge.CHR)
  end
  offset
end

function updateoffsets!(m::Mapper4, cartridge::Cartridge)
  @match m.prgMode begin
    0 => begin
      m.prgOffsets[1] = prgbankoffset(m, cartridge::Cartridge, Int32(m.registers[7]))
      m.prgOffsets[2] = prgbankoffset(m, cartridge::Cartridge, Int32(m.registers[8]))
      m.prgOffsets[3] = prgbankoffset(m, cartridge::Cartridge, Int32(-2))
      m.prgOffsets[4] = prgbankoffset(m, cartridge::Cartridge, Int32(-1))
    end
    1 => begin
      m.prgOffsets[1] = prgbankoffset(m, cartridge::Cartridge, Int32(-2))
      m.prgOffsets[2] = prgbankoffset(m, cartridge::Cartridge, Int32(m.registers[8]))
      m.prgOffsets[3] = prgbankoffset(m, cartridge::Cartridge, Int32(m.registers[7]))
      m.prgOffsets[4] = prgbankoffset(m, cartridge::Cartridge, Int32(-1))
    end
    _ => throw(ErrorException("Invalid prgMode."))
  end
  @match m.chrMode begin
    0 => begin
      m.chrOffsets[1] = chrbankoffset(m, cartridge::Cartridge, Int32(m.registers[1] & 0xFE))
      m.chrOffsets[2] = chrbankoffset(m, cartridge::Cartridge, Int32(m.registers[1] | 0x01))
      m.chrOffsets[3] = chrbankoffset(m, cartridge::Cartridge, Int32(m.registers[2] & 0xFE))
      m.chrOffsets[4] = chrbankoffset(m, cartridge::Cartridge, Int32(m.registers[2] | 0x01))
      m.chrOffsets[5] = chrbankoffset(m, cartridge::Cartridge, Int32(m.registers[3]))
      m.chrOffsets[6] = chrbankoffset(m, cartridge::Cartridge, Int32(m.registers[4]))
      m.chrOffsets[7] = chrbankoffset(m, cartridge::Cartridge, Int32(m.registers[5]))
      m.chrOffsets[8] = chrbankoffset(m, cartridge::Cartridge, Int32(m.registers[6]))
    end
    1 => begin
      m.chrOffsets[1] = chrBankOffset(m, cartridge::Cartridge, Int32(m.registers[3]))
      m.chrOffsets[2] = chrBankOffset(m, cartridge::Cartridge,  Int32(m.registers[4]))
      m.chrOffsets[3] = chrBankOffset(m, cartridge::Cartridge,  Int32(m.registers[5]))
      m.chrOffsets[4] = chrBankOffset(m, cartridge::Cartridge,  Int32(m.registers[6]))
      m.chrOffsets[5] = chrBankOffset(m, cartridge::Cartridge,  Int32(m.registers[1] & 0xFE))
      m.chrOffsets[6] = chrBankOffset(m, cartridge::Cartridge,  Int32(m.registers[1] | 0x01))
      m.chrOffsets[7] = chrBankOffset(m, cartridge::Cartridge,  Int32(m.registers[2] & 0xFE))
      m.chrOffsets[8] = chrBankOffset(m, cartridge::Cartridge,  Int32(m.registers[2] | 0x01))
    end
    _ => throw(ErrorException("Invalid prgMode."))
  end
end

# Mapper7

mutable struct Mapper7 <: Mapper
  prgBank::Int32

  Mapper7() = new(0)
end

function read(m::Mapper7, cartridge::Cartridge, address::UInt16)::UInt8
  if address < 0x2000
    cartridge.CHR[address + 1]
  elseif address >= 0x8000
    index = m.prgBank * Int32(0x8000) + Int32(address - 0x8000)
    cartridge.PRG[index + 1]
  elseif address >= 0x6000
    index = address - 0x6000
    cartridge.SRAM[index + 1]
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper7 read at address: 0x%04X", address)
    0
  end
end

function write!(m::Mapper7, cartridge::Cartridge, address::UInt16, val::UInt8)
  if address < 0x2000
    cartridge.CHR[address + 1] = val
  elseif address >= 0x8000
    m.prgBank = val & 7
    c = val & 0x10
    @match c begin
      0x00 => begin
        cartridge.mirror = UInt8(Single0::MirrorModes)
      end
      0x10 => begin
        cartridge.mirror = UInt8(Single1::MirrorModes)
      end
      _ => throw(ErrorException("Unreachable code"))
    end
  elseif address >= 0x6000
    index = address - 0x6000
    cartridge.SRAM[index + 1] = val
  else
    # TODO: add logging
    # log.Fatalf("unhandled mapper7 write at address: 0x%04X", address)
  end
end

function createmapper(cartridge::Cartridge)::Mapper
  @match cartridge.mapper begin
    0 => Mapper2(cartridge)
    1 => Mapper1(cartridge)
    2 => Mapper2(cartridge)
    3 => Mapper3(cartridge)
    4 => Mapper4(cartridge)
    7 => Mapper7()
    225 => Mapper225()
    _ => throw(ErrorException(@sprintf("Unimplemented mapper: %d", cartridge.mapper)))
  end
end
