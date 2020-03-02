include("console.jl")
include("apu.jl")
include("cpu.jl")
include("mapper.jl")
include("ppu.jl")

function reset!(console::Console)
  cpureset!(console)
  ppureset!(console.ppu)
end

# Load a game into a new Console instance.
function loadgame(path::String)::Console
  cartridge = fromfile(path)
  mapper = createmapper(cartridge)
  c = createconsole(cartridge, mapper)
  reset!(c)
  c
end

# Single step of emulation: one CPU instruction, three PPU and Mapper cycles
# per CPU cycle, and one APU cycle per CPU cycle. Each component is passed
# seperately because fetching them from console on every call incurs a small
# performance hit.
function step!(console::Console, cpu::CPU, ppu::PPU, apu::APU)::Int32
  cpuCycles = cpustep!(console, cpu)
  ppuCycles = cpuCycles * Int32(3)
  for i = 1:ppuCycles
    ppustep!(console, ppu)
    mapperstep!(console)
  end
  for i = 1:cpuCycles
    apustep!(console, apu)
  end
  cpuCycles
end

step!(console::Console)::Int32 = step!(console, console.cpu, console.ppu, console.apu)

# Execute emulation steps until the next frame.
function stepframe!(console::Console)::Int32
  reset!(console.apu.channel)
  cpuCycles = Int32(0)
  cpu = console.cpu
  ppu = console.ppu
  apu = console.apu
  frame = ppu.frame
  while ppu.frame == frame
    cpuCycles += step!(console, cpu, ppu, apu)
  end
  cpuCycles
end

function stepframes!(console::Console, numFrames::Integer)::Int64
  cpuCycles = Int64(0)
  for i = 1:numFrames
    cpuCycles += Int64(stepframe!(console))
  end
  cpuCycles
end

function stepframes!(console::Console, input::UInt8, numFrames::Integer)::Int64
  setbuttons1!(console, input)
  stepframes!(console, numFrames)
end

function stepframes!(console::Console, inputs::Vector{Tuple{UInt8, UInt8}})::Int64
  cpuCycles = Int64(0)
  for (input, numFrames) in inputs
    cpuCycles += stepframes!(console, input, numFrames)
  end
  cpuCycles
end

# Frame number of the current state.
function framenumber(console::Console)::UInt64
  console.ppu.frame
end

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

# Update the input for controller 1 by adding the indicated button, leaving
# previous inputs set.
function setbutton1!(console::Console, index::UInt8)
  console.controller1.buttons |= (0x01 << index)
end

# Update the input for controller 1 by removing the indicated button, leaving
# previous inputs set.
function removebutton1!(console::Console, index::UInt8)
  console.controller1.buttons -= (console.controller1.buttons & (0x01 << index))
end

# Set the input for controller 2.
function setbuttons2!(console::Console, buttons::UInt8)
  console.controller2.buttons = buttons
end

# Update the input for controller 2 by adding the indicated button, leaving
# previous inputs set.
function setbutton2!(console::Console, index::UInt8)
  console.controller1.buttons |= (0x01 << index)
end

# Update the input for controller 2 by removing the indicated button, leaving
# previous inputs set.
function removebutton2!(console::Console, index::UInt8)
  console.controller2.buttons -= (console.controller2.buttons & (0x01 << index))
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

function fireirq!(console::Console)
  if console.apu.frameIRQ
    triggerirq!(console.cpu)
  end
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
