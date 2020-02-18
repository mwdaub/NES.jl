import Base: read

@enum MirrorModes begin
  Horizontal = 0
  Vertical = 1
  Single0 = 2
  Single1 = 3
  Four = 4
end

struct Cartridge
  # PRG-ROM banks
  PRG::Vector{UInt8}
  # CHR-ROM banks
  CHR::Vector{UInt8}
  # Save RAM
  SRAM::Vector{UInt8}
  # mapper type
  mapper::UInt8
  # mirroring mode
  mirror::UInt8
  ## battery present
  battery::UInt8

  function Cartridge(PRG::Vector{UInt8}, CHR::Vector{UInt8}, mapper::UInt8, mirror::UInt8, battery::UInt8)
    new(PRG, CHR, zeros(UInt8, 0x2000), mapper, mirror, battery)
  end
end

const iNESFileMagic = 0x1a53454e

function fromfile(filename::String)::Cartridge
  open(filename) do f
    # read file header
    magic = read(f, UInt32)
    numPRG = read(f, UInt8)
    numCHR = read(f, UInt8)
    control1 = read(f, UInt8)
    control2 = read(f, UInt8)
    numRAM = read(f, UInt8)
    padding = read(f, 7)
    if magic != iNESFileMagic
      throw(ErrorException("File does not start with magic number."))
    end

    # mapper type
    mapper1 = control1 >> 0x04
    mapper2 = control2 >> 0x04
    mapper = mapper1 | (mapper2 << 0x04)

    # mirroring type
    mirror1 = control1 & 0x01
    mirror2 = (control1 >> 0x03) & 0x01
    mirror = mirror1 | (mirror2 << 0x01)

    # battery-backed RAM
    battery = (control1 >> 0x01) & 0x01

    # read trainer if present (unused)
    if (control1 & 0x04) == 0x04
      throw(ErrorException("Shouldn't be here."))
      # todo
    end

    # read prg-rom bank(s)
    prgLength = numPRG * 16384
    prg = read(f, prgLength)

    # read chr-rom bank(s)
    chrLength = 8192
    if numCHR != 0
      chrLength = numCHR * 8192
      chr = read(f, chrLength)
    else
      chr = zeros(UInt8, chrLength)
    end

    # success
    Cartridge(prg, chr, mapper, mirror, battery)
  end
end
