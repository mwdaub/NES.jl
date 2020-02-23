include("audio.jl")
include("cartridge.jl")
include("controller.jl")
include("video.jl")

# CPU

# interrupt types
@enum InterruptTypes begin
  InterruptNone = 0
  InterruptNMI = 1
  InterruptIRQ = 2
end

# addressing modes
@enum AddressingModes begin
  ModeAbsolute = 1
  ModeAbsoluteX = 2
  ModeAbsoluteY = 3
  ModeAccumulator = 4
  ModeImmediate = 5
  ModeImplied = 6
  ModeIndexedIndirect = 7
  ModeIndirect = 8
  ModeIndirectIndexed = 9
  ModeRelative = 10
  ModeZeroPage = 11
  ModeZeroPageX = 12
  ModeZeroPageY = 13
end

const cpuFrequency = Int32(1789773)

mutable struct CPU
  cycles::UInt64            # number of cycles
  PC::UInt16                # program counter
  SP::UInt8                 # stack pointer
  A::UInt8                  # accumulator
  X::UInt8                  # x register
  Y::UInt8                  # y register
  C::UInt8                  # carry flag
  Z::UInt8                  # zero flag
  I::UInt8                  # interrupt disable flag
  D::UInt8                  # decimal mode flag
  B::UInt8                  # break command flag
  U::UInt8                  # unused flag
  V::UInt8                  # overflow flag
  N::UInt8                  # negative flag
  interrupt::InterruptTypes # interrupt type to perform
  stall::Int32              # number of cycles to stall

  CPU() = new(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, InterruptNone::InterruptTypes, 0)
end

# triggerNMI causes a non-maskable interrupt to occur on the next cycle
function triggernmi!(cpu::CPU)
  cpu.interrupt = InterruptNMI::InterruptTypes
end

# triggerIRQ causes an IRQ interrupt to occur on the next cycle
function triggerirq!(cpu::CPU)
  if cpu.I == 0
    cpu.interrupt = InterruptIRQ::InterruptTypes
  end
end

# PPU

const palettedatasize = 32
const nametabledatasize = 2048
const oamdatasize = 256
const spritepatternssize = 8
const spritepositionssize = 8
const spriteprioritiessize = 8
const spriteindexessize = 8

mutable struct PPU
  cycle::Int32    # 0-340
  scanline::Int32 # 0-261, 0-239=visible, 240=post, 241-260=vblank, 261=pre
  frame::UInt64   # frame counter

  # storage variables
  paletteData::Vector{UInt8}
  nameTableData::Vector{UInt8}
  oamData::Vector{UInt8}

  # PPU registers
  v::UInt16 # current vram address (15 bit)
  t::UInt16 # temporary vram address (15 bit)
  x::UInt8  # fine x scroll (3 bit)
  w::UInt8  # write toggle (1 bit)
  f::UInt8  # even/odd frame flag (1 bit)

  reg::UInt8

  # NMI flags
  nmiOccurred::Bool
  nmiOutput::Bool
  nmiPrevious::Bool
  nmiDelay::UInt8

  # background temporary variables
  nameTableByte::UInt8
  attributeTableByte::UInt8
  lowTileByte::UInt8
  highTileByte::UInt8
  tileData::UInt64

  # sprite temporary variables
  spriteCount::Int32
  spritePatterns::Vector{UInt32}
  spritePositions::Vector{UInt8}
  spritePriorities::Vector{UInt8}
  spriteIndexes::Vector{UInt8}

  # $2000 PPUCTRL
  flagNameTable::UInt8       # 0: $2000; 1: $2400; 2: $2800; 3: $2C00
  flagIncrement::UInt8       # 0: add 1; 1: add 32
  flagSpriteTable::UInt8     # 0: $0000; 1: $1000; ignored in 8x16 mode
  flagBackgroundTable::UInt8 # 0: $0000; 1: $1000
  flagSpriteSize::UInt8      # 0: 8x8; 1: 8x16
  flagMasterSlave::UInt8     # 0: read EXT; 1: write EXT

  # $2001 PPUMASK
  flagGrayscale::UInt8          # 0: color; 1: grayscale
  flagShowLeftBackground::UInt8 # 0: hide; 1: show
  flagShowLeftSprites::UInt8    # 0: hide; 1: show
  flagShowBackground::UInt8     # 0: hide; 1: show
  flagShowSprites::UInt8        # 0: hide; 1: show
  flagRedTint::UInt8            # 0: normal; 1: emphasized
  flagGreenTint::UInt8          # 0: normal; 1: emphasized
  flagBlueTint::UInt8           # 0: normal; 1: emphasized

  # $2002 PPUSTATUS
  flagSpriteZeroHit::UInt8
  flagSpriteOverflow::UInt8

  # $2003 OAMADDR
  oamAddress::UInt8

  # $2007 PPUDATA
  bufferedData::UInt8 # for buffered reads

  # Current frame and next frame
  front::Frame
  back::Frame

  PPU() = new(0, 0, 0, zeros(UInt8, palettedatasize),
              zeros(UInt8, nametabledatasize), zeros(UInt8, oamdatasize),
              0, 0, 0, 0, 0, 0, false, false, false, 0, 0, 0, 0, 0, 0, 0,
              zeros(UInt32, spritepatternssize),
              zeros(UInt8, spritepositionssize),
              zeros(UInt8, spriteprioritiessize),
              zeros(UInt8, spriteindexessize), 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0, 0, 0, 0, Frame(), Frame())
end

# APU

# Counters per CPU-second.
const apuCounterFrequency = 240

const defaultSampleRate = 44100

const defaultSamplesPerFrame = defaultSampleRate ÷ 60

mutable struct APU
  cycle::UInt64
  frameCounter::UInt32
  framePeriod::UInt8
  frameValue::UInt8
  frameIRQ::Bool
  channel::AudioChannel
  sampleCounter::Float64
  sampleRate::Float64
  pulse1::Pulse
  pulse2::Pulse
  triangle::Triangle
  noise::Noise
  dmc::DMC
  filterChain::FilterChain

  function APU()
    apu = new(0, 0, 0, 0, false, AudioChannel(0), 0.0, Inf, Pulse(1), Pulse(2), Triangle(),
        Noise(), DMC(), FilterChain())
    setsamplesperframe!(apu, defaultSamplesPerFrame)
    apu
  end
end

function setsamplesperframe!(apu::APU, samplesPerFrame::Integer)
  apu.channel = AudioChannel(samplesPerFrame)
  # Convert samples per frame to cpu steps per sample.
  # This uses the minimum possible value of 29780 cpu
  # cycles per frame to ensure enough samples are gathered
  # between frames.
  apu.sampleRate = 29780.0 / Float64(samplesPerFrame)
  # Convert samples per frame to samples per second.
  rate = 60.0f0 * Float32(samplesPerFrame)
  setsamplerate!(apu.filterChain, rate)
end

# Mapper

abstract type Mapper end

function read(m::Mapper, cartridge::Cartridge, address::UInt16)::UInt8
  throw(ErrorException("Not implemented."))
end

function write!(m::Mapper, cartridge::Cartridge, address::UInt16, val::UInt8)
  throw(ErrorException("Not implemented."))
end

# Console

const RAMSize = 0x0800

const MirrorLookup = [
  [0x00 0x00 0x01 0x01];
  [0x00 0x01 0x00 0x01];
  [0x00 0x00 0x00 0x00];
  [0x01 0x01 0x01 0x01];
  [0x00 0x01 0x02 0x03];
]

function mirroraddress(mode::UInt8, address::UInt16)::UInt16
  address = (address - 0x2000) & 0x0FFF
  table = address >> 0x0A
  offset = address & 0x03FF
  0x2000 + MirrorLookup[mode + 0x01, table + 0x01] * 0x0400 + offset
end

struct Console{T <: Mapper}
  RAM::Vector{UInt8}
  cpu::CPU
  ppu::PPU
  apu::APU
  cartridge::Cartridge
  controller1::Controller
  controller2::Controller
  mapper::T
  Console{T}(c::Cartridge, m::T) where {T <: Mapper} = new{T}(zeros(UInt8, RAMSize),
                                                      CPU(), PPU(), APU(), c,
                                                      Controller(),
                                                      Controller(), m)
end

function createconsole(c::Cartridge, m::T) where {T <: Mapper}
  Console{T}(c, m)
end
