using Match
using Printf

import Base: read

function mapperstep!(console::Console{T}) where {T <: Mapper}
end

# Mapper2

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

function createmapper(cartridge::Cartridge)::Mapper
  @match cartridge.mapper begin
    0 => Mapper2(cartridge)
    2 => Mapper2(cartridge)
    _ => throw(ErrorException(@sprintf("Unimplemented mapper: %d", cartridge.mapper)))
  end
end
