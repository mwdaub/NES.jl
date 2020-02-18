include("console.jl")
include("mapper.jl")

# Load a game into a new Console instance.
function loadgame(path::String)::Console
  cartridge = fromfile(path)
  mapper = createmapper(cartridge)
  c = createconsole(cartridge, mapper)
  c
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

# Set the input for controller 2.
function setbuttons2!(console::Console, buttons::UInt8)
  console.controller2.buttons = buttons
end

# Update the sample rate for the audio component.
function setaudiosamplesperframe!(console::Console, samplesPerFrame::UInt32)
  setsamplesperframe!(console.apu, samplesPerFrame)
end
