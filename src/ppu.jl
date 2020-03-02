using Match

# Functions for performing PPU cycles.

function ppuread(console::Console, address::UInt16)::UInt8
  ppu = console.ppu
  address = address & 0x3FFF
  if address < 0x2000
    read(console.mapper, console.cartridge, address)
  elseif address < 0x3F00
    mode = console.cartridge.mirror
    @inbounds ppu.nameTableData[(mirroraddress(mode, address) & 0x07FF) + 0x01]
  else
    readpalette(ppu, address & 0x1F)
  end
end

function ppuwrite!(console::Console, address::UInt16, val::UInt8)
  ppu = console.ppu
  address = address & 0x3FFF
  if address < 0x2000
    write!(console.mapper, console.cartridge, address, val)
  elseif address < 0x3F00
    mode = console.cartridge.mirror
    @inbounds ppu.nameTableData[(mirroraddress(mode, address) & 0x07FF) + 0x01] = val
  else
    writepalette!(ppu, address & 0x1F, val)
  end
end

function ppureset!(ppu::PPU)
  ppu.cycle = 340
  ppu.scanline = 240
  ppu.frame = 0
  writecontrol!(ppu, 0x00)
  writemask!(ppu, 0x00)
  writeoamaddress!(ppu, 0x00)
end

function readpalette(ppu::PPU, address::UInt16)::UInt8
  if address >= 16 && (address & 3) == 0
    address -= 0x10
  end
  @inbounds return ppu.paletteData[address + 1]
end

function writepalette!(ppu::PPU, address::UInt16, val::UInt8)
  if address >= 16 && (address & 3) == 0
    address -= 0x10
  end
  @inbounds ppu.paletteData[address + 1] = val
end

function ppureadregister(console::Console, address::UInt16)::UInt8
  ppu = console.ppu
  @match address begin
    0x2002 => readstatus!(ppu)
    0x2004 => readoamdata(ppu)
    0x2007 => readdata!(console)
    _ => 0
  end
end

function ppuwriteregister!(console::Console, address::UInt16, val::UInt8)
  ppu = console.ppu
  ppu.reg = val
  @match address begin
    0x2000 => begin
      writecontrol!(ppu, val)
    end
    0x2001 => begin
      writemask!(ppu, val)
    end
    0x2003 => begin
      writeoamaddress!(ppu, val)
    end
    0x2004 => begin
      writeoamdata!(ppu, val)
    end
    0x2005 => begin
      writescroll!(ppu, val)
    end
    0x2006 => begin
      writeaddress!(ppu, val)
    end
    0x2007 => begin
      writedata!(console, val)
    end
    0x4014 => begin
      writedma!(console, val)
    end
  end
end

# $2000: PPUCTRL
function writecontrol!(ppu::PPU, val::UInt8)
  ppu.flagNameTable = (val >> 0) & 3
  ppu.flagIncrement = (val >> 2) & 1
  ppu.flagSpriteTable = (val >> 3) & 1
  ppu.flagBackgroundTable = (val >> 4) & 1
  ppu.flagSpriteSize = (val >> 5) & 1
  ppu.flagMasterSlave = (val >> 6) & 1
  ppu.nmiOutput = ((val >> 7) & 1) == 1
  nmichange!(ppu)
  # t: ....BA.. ........ = d: ......BA
  ppu.t = (ppu.t & 0xF3FF) | ((val & 0x0003) << 10)
end

# $2001: PPUMASK
function writemask!(ppu::PPU, val::UInt8)
  ppu.flagGrayscale = (val >> 0) & 1
  ppu.flagShowLeftBackground = (val >> 1) & 1
  ppu.flagShowLeftSprites = (val >> 2) & 1
  ppu.flagShowBackground = (val >> 3) & 1
  ppu.flagShowSprites = (val >> 4) & 1
  ppu.flagRedTint = (val >> 5) & 1
  ppu.flagGreenTint = (val >> 6) & 1
  ppu.flagBlueTint = (val >> 7) & 1
end

# $2002: PPUSTATUS
function readstatus!(ppu::PPU)::UInt8
  result = ppu.reg & 0x1F
  result |= ppu.flagSpriteOverflow << 5
  result |= ppu.flagSpriteZeroHit << 6
  if ppu.nmiOccurred
    result |= 0x01 << 7
  end
  ppu.nmiOccurred = false
  nmichange!(ppu)
  # w:                   = 0
  ppu.w = 0
  result
end

# $2003: OAMADDR
function writeoamaddress!(ppu::PPU, val::UInt8)
  ppu.oamAddress = val
end

# $2004: OAMDATA (read)
function readoamdata(ppu::PPU)::UInt8
  @inbounds ppu.oamData[ppu.oamAddress + 1]
end

# $2004: OAMDATA (write)
function writeoamdata!(ppu::PPU, val::UInt8)
  @inbounds ppu.oamData[ppu.oamAddress + 1] = val
  ppu.oamAddress += 0x01
end

# $2005: PPUSCROLL
function writescroll!(ppu::PPU, val::UInt8)
  if ppu.w == 0
    # t: ........ ...HGFED = d: HGFED...
    # x:               CBA = d: .....CBA
    # w:                   = 1
    ppu.t = (ppu.t & 0xFFE0) | (UInt16(val) >> 3)
    ppu.x = val & 0x07
    ppu.w = 1
  else
    # t: .CBA..HG FED..... = d: HGFEDCBA
    # w:                   = 0
    ppu.t = (ppu.t & 0x8FFF) | ((val & 0x0007) << 12)
    ppu.t = (ppu.t & 0xFC1F) | ((val & 0x00F8) << 2)
    ppu.w = 0
  end
end

# $2006: PPUADDR
function writeaddress!(ppu::PPU, val::UInt8)
  if ppu.w == 0
    # t: ..FEDCBA ........ = d: ..FEDCBA
    # t: .X...... ........ = 0
    # w:                   = 1
    ppu.t = (ppu.t & 0x80FF) | ((val & 0x003F) << 8)
    ppu.w = 1
  else
    # t: ........ HGFEDCBA = d: HGFEDCBA
    # v                    = t
    # w:                   = 0
    ppu.t = (ppu.t & 0xFF00) | val
    ppu.v = ppu.t
    ppu.w = 0
  end
end

# $2007: PPUDATA (read)
function readdata!(console::Console)::UInt8
  ppu = console.ppu
  val = ppuread(console, ppu.v)
  # emulate buffered reads
  if ppu.v & 0x3FFF < 0x3F00
    buffered = ppu.bufferedData
    ppu.bufferedData = val
    val = buffered
  else
    ppu.bufferedData = ppuread(console, ppu.v - 0x1000)
  end
  # increment address
  if ppu.flagIncrement == 0
    ppu.v += 0x01
  else
    ppu.v += 0x20
  end
  return val
end

# $2007: PPUDATA (write)
function writedata!(console::Console, val::UInt8)
  ppu = console.ppu
  ppuwrite!(console, ppu.v, val)
  if ppu.flagIncrement == 0
    ppu.v += 0x01
  else
    ppu.v += 0x20
  end
end

# $4014: OAMDMA
function writedma!(console::Console, val::UInt8)
  ppu = console.ppu
  cpu = console.cpu
  address = UInt16(val) << 8
  for i in 0:255
    @inbounds ppu.oamData[ppu.oamAddress + 1] = cpuread(console, address)
    ppu.oamAddress += 0x01
    address += 0x0001
  end
  cpu.stall += Int32(513)
  if cpu.cycles & 1 == 1
    cpu.stall += 0x01
  end
end

# NTSC Timing Helper Functions

function incrementx!(ppu::PPU)
  # increment hori(v)
  # if coarse X == 31
  if (ppu.v & 0x001F) == 31
    # coarse X = 0
    ppu.v &= 0xFFE0
    # switch horizontal nametable
    ppu.v ⊻= 0x0400
  else
    # increment coarse X
    ppu.v += 0x01
  end
end

function incrementy!(ppu::PPU)
  # increment vert(v)
  # if fine Y < 7
  if (ppu.v&0x7000) != 0x7000
    # increment fine Y
    ppu.v += 0x1000
  else
    # fine Y = 0
    ppu.v &= 0x8FFF
    # let y = coarse Y
    y::UInt16 = (ppu.v & 0x03E0) >> 5
    if y == 29
      # coarse Y = 0
      y = 0x0000
      # switch vertical nametable
      ppu.v ⊻= 0x0800
    elseif y == 31
      # coarse Y = 0, nametable not switched
      y = 0x0000
    else
      # increment coarse Y
      y += 0x0001
    end
    # put coarse Y back into v
    ppu.v = (ppu.v & 0xFC1F) | (y << 5)
  end
end

function copyx!(ppu::PPU)
  # hori(v) = hori(t)
  # v: .....F.. ...EDCBA = t: .....F.. ...EDCBA
  ppu.v = (ppu.v & 0xFBE0) | (ppu.t & 0x041F)
end

function copyy!(ppu::PPU)
  # vert(v) = vert(t)
  # v: .IHGF.ED CBA..... = t: .IHGF.ED CBA.....
  ppu.v = (ppu.v & 0x841F) | (ppu.t & 0x7BE0)
end

function nmichange!(ppu::PPU)
  nmi = ppu.nmiOutput && ppu.nmiOccurred
  if nmi && !ppu.nmiPrevious
    # TODO: this fixes some games but the delay shouldn't have to be so
    # long, so the timings are off somewhere
    ppu.nmiDelay = 15
  end
  ppu.nmiPrevious = nmi
end

function setverticalblank!(ppu::PPU)
  temp = ppu.front
  ppu.front = ppu.back
  ppu.back = temp
  ppu.nmiOccurred = true
  nmichange!(ppu)
end

function clearverticalblank!(ppu::PPU)
  ppu.nmiOccurred = false
  nmichange!(ppu)
end

function fetchnametablebyte!(console::Console, ppu::PPU)
  address = 0x2000 | (ppu.v & 0x0FFF)
  ppu.nameTableByte = ppuread(console, address)
end

function fetchattributetablebyte!(console::Console, ppu::PPU)
  address = 0x23C0 | (ppu.v & 0x0C00) | ((ppu.v >> 4) & 0x38) | ((ppu.v >> 2) & 0x07)
  shift = ((ppu.v >> 4) & 4) | (ppu.v & 2)
  ppu.attributeTableByte = ((ppuread(console, address) >> shift) & 0x03) << 2
end

function fetchlowtilebyte!(console::Console, ppu::PPU)
  fineY = (ppu.v >> 12) & 0x07
  table = ppu.flagBackgroundTable
  tile = ppu.nameTableByte
  address = 0x1000 * table + tile * 0x0010 + fineY
  ppu.lowTileByte = ppuread(console, address)
end

function fetchhightilebyte!(console::Console, ppu::PPU)
  fineY = (ppu.v >> 0x0C) & 0x07
  table = ppu.flagBackgroundTable
  tile = ppu.nameTableByte
  address = 0x1000 * table + tile * 0x0010 + fineY
  ppu.highTileByte = ppuread(console, address + 0x08)
end

function storetiledata!(ppu::PPU)
  data = 0x00000000
  for i = 1:8
    a = ppu.attributeTableByte
    p1 = (ppu.lowTileByte & 0x80) >> 7
    p2 = (ppu.highTileByte & 0x80) >> 6
    ppu.lowTileByte <<= 1
    ppu.highTileByte <<= 1
    data <<= 4
    data |= a | p1 | p2
  end
  ppu.tileData |= data
end

function fetchtiledata(ppu::PPU)::UInt32
  ppu.tileData >> 32
end

function backgroundpixel(ppu::PPU)::UInt8
  if ppu.flagShowBackground == 0x00
    0x00
  else
    data = fetchtiledata(ppu) >> ((0x07 - ppu.x) << 2)
    data & 0x0F
  end
end

function spritepixel(ppu::PPU)::Tuple{UInt8, UInt8}
  if ppu.flagShowSprites != 0
    for i = 0:(ppu.spriteCount-1)
      @inbounds offset = (ppu.cycle - Int32(1)) - Int32(ppu.spritePositions[i + 1])
      if offset < 0 || offset > 7
        continue
      end
      offset = Int32(7) - offset
      @inbounds color = (ppu.spritePatterns[i + 1] >> (offset * 4)) & 0x0F
      if color & 3 == 0
        continue
      end
      return (UInt8(i), UInt8(color))
    end
  end
  (0x00, 0x00)
end

function renderpixel!(ppu::PPU, x::Int32, y::Int32)
  background = backgroundpixel(ppu)
  i, sprite = spritepixel(ppu)
  ppux = ppu.x
  if ppux < 8 && ppu.flagShowLeftBackground == 0
    background = 0x00
  end
  if ppux < 8 && ppu.flagShowLeftSprites == 0
    sprite = 0x00
  end
  b = (background & 3) != 0
  s = (sprite & 3) != 0
  color = 0x00
  if !b && !s
    color = 0x00
  elseif !b && s
    color = sprite | 0x10
  elseif b && !s
    color = background
  else
    @inbounds if ppu.spriteIndexes[i + 1] == 0 && ppux < 255
      ppu.flagSpriteZeroHit = 1
    end
    @inbounds if ppu.spritePriorities[i + 1] == 0
      color = sprite | 0x10
    else
      color = background
    end
  end
  pixel = readpalette(ppu, UInt16(color)) & 0x3F
  @inbounds ppu.back[y + 1, x] = pixel
end

function fetchspritepattern(console::Console, i::Int32, row::Int32)::UInt32
  ppu = console.ppu
  @inbounds tile = ppu.oamData[4 * i + 2]
  @inbounds attributes = ppu.oamData[4 * i + 3]
  address = 0x0000
  if ppu.flagSpriteSize == 0
    if (attributes & 0x80) == 0x80
      row = Int32(7) - row
    end
    table = ppu.flagSpriteTable
    address = 0x1000 * table + 0x0010 * tile + UInt16(row)
  else
    if (attributes & 0x80) == 0x80
      row = Int32(15) - row
    end
    table = tile & 0x01
    tile &= 0xFE
    if row > 7
      tile += 0x01
      row -= Int32(8)
    end
    address = 0x1000 * table + 0x0010 * tile + UInt16(row)
  end
  a = (attributes & 0x03) << 0x02
  lowTileByte = ppuread(console, address)
  highTileByte = ppuread(console, address + 0x08)
  data = 0x00000000
  for i = 1:8
    p1 = 0x00
    p2 = 0x00
    if (attributes & 0x40) == 0x40
      p1 = (lowTileByte & 0x01) << 0x00
      p2 = (highTileByte & 0x01) << 0x01
      lowTileByte >>= 1
      highTileByte >>= 1
    else
      p1 = (lowTileByte & 0x80) >> 0x07
      p2 = (highTileByte & 0x80) >> 0x06
      lowTileByte <<= 1
      highTileByte <<= 1
    end
    data <<= 4
    data |= a | p1 | p2
  end
  data
end

function evaluatesprites!(console::Console)
  ppu = console.ppu
  h::Int32 = ppu.flagSpriteSize == 0 ? 8 : 16
  count::Int32 = 0
  for i = Int32(0):Int32(63)
    @inbounds y = ppu.oamData[4 * i + 1]
    @inbounds a = ppu.oamData[4 * i + 3]
    @inbounds x = ppu.oamData[4 * i + 4]
    row = ppu.scanline - y
    if row < 0 || row >= h
      continue
    end
    if count < 8
      @inbounds ppu.spritePatterns[count + 1] = fetchspritepattern(console, i, row)
      @inbounds ppu.spritePositions[count + 1] = x
      @inbounds ppu.spritePriorities[count + 1] = (a >> 5) & 1
      @inbounds ppu.spriteIndexes[count + 1] = i
    end
    count += Int32(1)
  end
  if count > 8
    count = Int32(8)
    ppu.flagSpriteOverflow = 1
  end
  ppu.spriteCount = count
end

# tick updates cycle, scanline and frame counters
function tick!(console::Console, ppu::PPU)
  if ppu.nmiDelay > 0
    ppu.nmiDelay -= 0x01
    if ppu.nmiDelay == 0 && ppu.nmiOutput && ppu.nmiOccurred
      triggernmi!(console.cpu)
    end
  end

  if ppu.flagShowBackground != 0 || ppu.flagShowSprites != 0
    if ppu.f == 1 && ppu.scanline == 261 && ppu.cycle == 339
      ppu.cycle = 0
      ppu.scanline = 0
      ppu.frame += 1
      ppu.f ⊻= 0x01
      return
    end
  end
  ppu.cycle += Int32(1)
  if ppu.cycle > 340
    ppu.cycle = 0
    ppu.scanline += Int32(1)
    if ppu.scanline > 261
      ppu.scanline = 0
      ppu.frame += 1
      ppu.f ⊻= 1
    end
  end
end

# Step executes a single PPU cycle
function ppustep!(console::Console, ppu::PPU)
  tick!(console, ppu)

  renderingEnabled = ppu.flagShowBackground != 0x00 || ppu.flagShowSprites != 0x00
  scanline = ppu.scanline
  preLine = (scanline == Int32(261))
  visibleLine = (scanline < Int32(240))
  # postLine := scanline == 240
  renderLine = (preLine || visibleLine)
  cycle = ppu.cycle
  preFetchCycle = (cycle >= Int32(321) && cycle <= Int32(336))
  visibleCycle = (cycle >= Int32(1) && cycle <= Int32(256))
  fetchCycle = (preFetchCycle || visibleCycle)

  # background logic
  if renderingEnabled
    if visibleLine && visibleCycle
      renderpixel!(ppu, cycle, scanline)
    end
    if renderLine && fetchCycle
      tdb = ppu.tileData
      ppu.tileData <<= 4
      b = ppu.cycle & 7
      @match b begin
        1 => begin
          fetchnametablebyte!(console, ppu)
        end
        3 => begin
          fetchattributetablebyte!(console, ppu)
        end
        5 => begin
          fetchlowtilebyte!(console, ppu)
        end
        7 => begin
          fetchhightilebyte!(console, ppu)
        end
        0 => begin
          storetiledata!(ppu)
        end
      end
    end
    if preLine && ppu.cycle >= 280 && ppu.cycle <= 304
      copyy!(ppu)
    end
    if renderLine
      if fetchCycle && (ppu.cycle & 7 == 0)
        incrementx!(ppu)
      end
      if ppu.cycle == 256
        incrementy!(ppu)
      end
      if ppu.cycle == 257
        copyx!(ppu)
      end
    end
  end

  # sprite logic
  if renderingEnabled
    if ppu.cycle == 257
      if visibleLine
        evaluatesprites!(console)
      else
        ppu.spriteCount = 0
      end
    end
  end

  # vblank logic
  if ppu.scanline == 241 && ppu.cycle == 1
    setverticalblank!(ppu)
  end
  if preLine && ppu.cycle == 1
    clearverticalblank!(ppu)
    ppu.flagSpriteZeroHit = 0
    ppu.flagSpriteOverflow = 0
  end
  0x00
end

