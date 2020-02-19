include("console.jl")
include("apu.jl")
include("cpu.jl")
include("mapper.jl")
include("ppu.jl")

# Load a game into a new Console instance.
function loadgame(path::String)::Console
  cartridge = fromfile(path)
  mapper = createmapper(cartridge)
  c = createconsole(cartridge, mapper)
  c
end

# Single step of emulation: one CPU instruction, three PPU and Mapper cycles
# per CPU cycle, and one APU cycle per CPU cycle. Each component is passed
# seperately because fetching them from console on every call incurs a small
# performance hit.
function step!(console::Console, cpu::CPU, ppu::PPU, apu::APU)::Int32
  cpuCycles = cpustep!(console, cpu)
  #ppuCycles = cpuCycles * Int32(3)
  #for i = 1:ppuCycles
    #ppustep!(console, ppu)
    #mapperstep!(console)
  #end
  for i = 1:cpuCycles
    apustep!(console, apu)
  end
  cpuCycles
end

step!(console::Console)::Int32 = step!(console, console.cpu, console.ppu, console.apu)

# Current frame, where pixels are represented as palette indices.
function frame(console::Console)::Frame
  copy(console.ppu.front)
end

# Current frame rendered as a screen with palette RGB values.
function screen(console::Console)::Screen
  Screen(console.ppu.front)
end

# Set the input for controller 1.
function setbuttons1!(console::Console, buttons::UInt8)
  console.controller1.buttons = buttons
end

# Set the input for controller 2.
function setbuttons2!(console::Console, buttons::UInt8)
  console.controller2.buttons = buttons
end

# Update the sample rate for the audio component.
function setaudiosamplesperframe!(console::Console, samplesPerFrame::UInt32)
  setsamplesperframe!(console.apu, samplesPerFrame)
end

# Private functions for performing emulation that need interactions between
# components.

function steptimer!(console::Console, apu::APU)
  if (apu.cycle & 1) == 0
    steptimer!(apu.pulse1)
    steptimer!(apu.pulse2)
    steptimer!(apu.noise)
    steptimer!(apu.dmc, console)
  end
  steptimer!(apu.triangle)
end

function steptimer!(dmc::DMC, console::Console)
  if !dmc.enabled
    return
  end
  stepreader!(console)
  if dmc.tickValue == 0
    dmc.tickValue = dmc.tickPeriod
    stepshifter!(dmc)
  else
    dmc.tickValue -= 1
  end
end

function stepreader!(console::Console)
  dmc = console.apu.dmc
  if dmc.currentLength > 0 && dmc.bitCount == 0
    console.cpu.stall += 4
    dmc.shiftRegister = cpuread(console, dmc.currentAddress)
    dmc.bitCount = 8
    dmc.currentAddress += 1
    if dmc.currentAddress == 0
      dmc.currentAddress = 0x8000
    end
    dmc.currentLength -= 1
    if dmc.currentLength == 0 && dmc.loop
      restart!(dmc)
    end
  end
end
