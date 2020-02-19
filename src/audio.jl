# Pulse

mutable struct Pulse
  enabled::Bool
  channel::UInt8
  lengthEnabled::Bool
  lengthValue::UInt8
  timerPeriod::UInt16
  timerValue::UInt16
  dutyMode::UInt8
  dutyValue::UInt8
  sweepReload::Bool
  sweepEnabled::Bool
  sweepNegate::Bool
  sweepShift::UInt8
  sweepPeriod::UInt8
  sweepValue::UInt8
  envelopeEnabled::Bool
  envelopeLoop::Bool
  envelopeStart::Bool
  envelopePeriod::UInt8
  envelopeValue::UInt8
  envelopeVolume::UInt8
  constantVolume::UInt8

  Pulse() = new(false, 0, false, 0, 0, 0, 0, 0, false, false, false, 0, 0, 0,
                false, false, false, 0, 0, 0, 0)
end

const LengthTable = [
  0x0A, 0xFE, 0x14, 0x02, 0x28, 0x04, 0x50, 0x06,
  0xA0, 0x08, 0x3C, 0x0A, 0x0E, 0x0C, 0x1A, 0x0E,
  0x0C, 0x10, 0x18, 0x12, 0x30, 0x14, 0x60, 0x16,
  0xC0, 0x18, 0x48, 0x1A, 0x10, 0x1C, 0x20, 0x1E
]

const DutyTable = [
  [0x00 0x01 0x00 0x00 0x00 0x00 0x00 0x00];
  [0x00 0x01 0x01 0x00 0x00 0x00 0x00 0x00];
  [0x00 0x01 0x01 0x01 0x01 0x00 0x00 0x00];
  [0x01 0x00 0x00 0x01 0x01 0x01 0x01 0x01]
]

function writecontrol!(pulse::Pulse, val::UInt8)
  pulse.dutyMode = (val >> 6) & 0x03
  pulse.lengthEnabled = ((val >> 5) & 0x01) == 0x00
  pulse.envelopeLoop = ((val >> 5) & 0x01) == 0x01
  pulse.envelopeEnabled = ((val >> 4) & 0x01) == 0x00
  pulse.envelopePeriod = val & 0x0F
  pulse.constantVolume = val & 0x0F
  pulse.envelopeStart = true
end

function writesweep!(pulse::Pulse, val::UInt8)
  pulse.sweepEnabled = ((val >> 7) & 0x01) == 0x01
  pulse.sweepPeriod = ((val >> 4) & 0x07) + 0x01
  pulse.sweepNegate = ((val >> 3) & 0x01) == 0x01
  pulse.sweepShift = val & 0x07
  pulse.sweepReload = true
end

function writetimerlow!(pulse::Pulse, val::UInt8)
  pulse.timerPeriod = (pulse.timerPeriod & 0xFF00) | val
end

function writetimerhigh!(pulse::Pulse, val::UInt8)
  pulse.lengthValue = LengthTable[(val >> 3) + 1]
  pulse.timerPeriod = (pulse.timerPeriod & 0x00FF) | (UInt16(val & 0x07) << 8)
  pulse.envelopeStart = true
  pulse.dutyValue = 0
end

function steptimer!(pulse::Pulse)
  if pulse.timerValue == 0
    pulse.timerValue = pulse.timerPeriod
    pulse.dutyValue = (pulse.dutyValue + 0x01) & 0x07
  else
    pulse.timerValue -= 1
  end
end

function stepenvelope!(pulse::Pulse)
  if pulse.envelopeStart
    pulse.envelopeVolume = 15
    pulse.envelopeValue = pulse.envelopePeriod
    pulse.envelopeStart = false
  elseif pulse.envelopeValue > 0
    pulse.envelopeValue -= 1
  else
    if pulse.envelopeVolume > 0
      pulse.envelopeVolume -= 1
    elseif pulse.envelopeLoop
      pulse.envelopeVolume = 15
    end
    pulse.envelopeValue = pulse.envelopePeriod
  end
end

function stepsweep!(pulse::Pulse)
  if pulse.sweepReload
    if pulse.sweepEnabled && pulse.sweepValue == 0
      sweep!(pulse)
    end
    pulse.sweepValue = pulse.sweepPeriod
    pulse.sweepReload = false
  elseif pulse.sweepValue > 0
    pulse.sweepValue -= 1
  else
    if pulse.sweepEnabled
      sweep!(pulse)
    end
    pulse.sweepValue = pulse.sweepPeriod
  end
end

function steplength!(pulse::Pulse)
  if pulse.lengthEnabled && pulse.lengthValue > 0
    pulse.lengthValue -= 1
  end
end

function sweep!(pulse::Pulse)
  delta = pulse.timerPeriod >> pulse.sweepShift
  if pulse.sweepNegate
    pulse.timerPeriod -= delta
    if pulse.channel == 1
      pulse.timerPeriod -= 1
    end
  else
    pulse.timerPeriod += delta
  end
end

function output!(pulse::Pulse)::UInt8
  if !pulse.enabled
    return 0x00
  end
  if pulse.lengthValue == 0
    return 0x00
  end
  if DutyTable[pulse.dutyMode + 1, pulse.dutyValue + 1] == 0
    return 0x00
  end
  if pulse.timerPeriod < 8 || pulse.timerPeriod > 0x7FF
    return 0x00
  end
  # if !sweepNegate && timerPeriod+(timerPeriod>>sweepShift) > 0x7FF
  #   return 0
  # }
  if pulse.envelopeEnabled
    return pulse.envelopeVolume
  else
    return pulse.constantVolume
  end
end

# Triangle

mutable struct Triangle
  enabled::Bool
  lengthEnabled::Bool
  lengthValue::UInt8
  timerPeriod::UInt16
  timerValue::UInt16
  dutyValue::UInt8
  counterPeriod::UInt8
  counterValue::UInt8
  counterReload::Bool

  Triangle() = new(false, false, 0, 0, 0, 0, 0, 0, false)
end

const TriangleTable = [
  0x0F, 0x0E, 0x0D, 0x0C, 0x0B, 0x0A, 0x09, 0x08,
  0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01, 0x00,
  0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07,
  0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
]

function writecontrol!(triangle::Triangle, val::UInt8)
  triangle.lengthEnabled = ((val >> 7) & 0x01) == 0x00
  triangle.counterPeriod = val & 0x7F
end

function writetimerlow!(triangle::Triangle, val::UInt8)
  triangle.timerPeriod = (triangle.timerPeriod & 0xFF00) | val
end

function writetimerhigh!(triangle::Triangle, val::UInt8)
  triangle.lengthValue = LengthTable[(val >> 3) + 1]
  triangle.timerPeriod = (triangle.timerPeriod & 0x00FF) | (UInt16(val & 0x07) << 8)
  triangle.timerValue = triangle.timerPeriod
  triangle.counterReload = true
end

function steptimer!(triangle::Triangle)
  if triangle.timerValue == 0
    triangle.timerValue = triangle.timerPeriod
    if triangle.lengthValue > 0 && triangle.counterValue > 0
      triangle.dutyValue = (triangle.dutyValue + 0x01) & 0x1F
    end
  else
    triangle.timerValue -= 1
  end
end

function steplength!(triangle::Triangle)
  if triangle.lengthEnabled && triangle.lengthValue > 0
    triangle.lengthValue -= 1
  end
end

function stepcounter!(triangle::Triangle)
  if triangle.counterReload
    triangle.counterValue = triangle.counterPeriod
  elseif triangle.counterValue > 0
    triangle.counterValue -= 1
  end
  if triangle.lengthEnabled
    triangle.counterReload = false
  end
end

function output!(triangle::Triangle)::UInt8
  if !triangle.enabled
    return 0x00
  end
  if triangle.lengthValue == 0
    return 0x00
  end
  if triangle.counterValue == 0
    return 0x00
  end
  TriangleTable[dutyValue + 1]
end

# Noise

mutable struct Noise
  enabled::Bool
  mode::Bool
  shiftRegister::UInt16
  lengthEnabled::Bool
  lengthValue::UInt8
  timerPeriod::UInt16
  timerValue::UInt16
  envelopeEnabled::Bool
  envelopeLoop::Bool
  envelopeStart::Bool
  envelopePeriod::UInt8
  envelopeValue::UInt8
  envelopeVolume::UInt8
  constantVolume::UInt8

  Noise() = new(false, false, 0, false, 0, 0, 0, false, false, false, 0, 0,
                  0, 0)
end

const NoiseTable = [
  0x0004, 0x0008, 0x0010, 0x0020, 0x0040, 0x0060, 0x0080, 0x00A0,
  0x00CA, 0x00FE, 0x017C, 0x01FC, 0x02FA, 0x03F8, 0x07F2, 0x0FE4
]

function writecontrol!(noise::Noise, val::UInt8)
  noise.lengthEnabled = ((val >> 5) & 0x01) == 0x00
  noise.envelopeLoop = ((val >> 5) & 0x01) == 0x01
  noise.envelopeEnabled = ((val >> 4) & 0x01) == 0x00
  noise.envelopePeriod = val & 0x0F
  noise.constantVolume = val & 0x0F
  noise.envelopeStart = true
end

function writeperiod!(noise::Noise, val::UInt8)
  noise.mode = (val & 0x80) == 0x80
  noise.timerPeriod = NoiseTable[(val & 0x0F) + 1]
end

function writelength!(noise::Noise, val::UInt8)
  noise.lengthValue = LengthTable[(val >> 3) + 1]
  noise.envelopeStart = true
end

function steptimer!(noise::Noise)
  if noise.timerValue == 0
    noise.timerValue = noise.timerPeriod
    shift = noise.mode ? 0x06 : 0x01
    b1 = noise.shiftRegister & 0x01
    b2 = (noise.shiftRegister >> shift) & 0x01
    noise.shiftRegister >>= 1
    noise.shiftRegister |= (b1 ⊻ b2) << 14
  else
    noise.timerValue -= 1
  end
end

function stepenvelope!(noise::Noise)
  if noise.envelopeStart
    noise.envelopeVolume = 15
    noise.envelopeValue = noise.envelopePeriod
    noise.envelopeStart = false
  elseif noise.envelopeValue > 0
    noise.envelopeValue -= 1
  else
    if noise.envelopeVolume > 0
      noise.envelopeVolume -= 1
    elseif noise.envelopeLoop
      noise.envelopeVolume = 15
    end
    noise.envelopeValue = noise.envelopePeriod
  end
end

function steplength!(noise::Noise)
  if noise.lengthEnabled && noise.lengthValue > 0
    noise.lengthValue -= 1
  end
end

function output!(noise::Noise)::UInt8
  if !noise.enabled
    return 0x00
  end
  if noise.lengthValue == 0
    return 0x00
  end
  if (noise.shiftRegister & 0x01) == 0x01
    return 0x00
  end
  if noise.envelopeEnabled
    noise.envelopeVolume
  else
    noise.constantVolume
  end
end

mutable struct DMC
  enabled::Bool
  value::UInt8
  sampleAddress::UInt16
  sampleLength::UInt16
  currentAddress::UInt16
  currentLength::UInt16
  shiftRegister::UInt8
  bitCount::UInt8
  tickPeriod::UInt8
  tickValue::UInt8
  loop::Bool
  irq::Bool

  DMC() = new(false, 0, 0, 0, 0, 0, 0, 0, 0, 0, false, false)
end

const DMCTable = [
  0xD6, 0xBE, 0xAA, 0xA0, 0x8F, 0x7F, 0x71, 0x6B,
  0x5F, 0x50, 0x47, 0x40, 0x35, 0x2A, 0x24, 0x1B
]

function writecontrol!(dmc::DMC, val::UInt8)
  dmc.irq = (val & 0x80) == 0x80
  dmc.loop = (val & 0x40) == 0x40
  dmc.tickPeriod = DMCTable[(val & 0x0F) + 1]
end

function writevalue!(dmc::DMC, val::UInt8)
  dmc.value = val & 0x7F
end

function writeaddress!(dmc::DMC, val::UInt8)
  # Sample address = %11AAAAAA.AA000000
  dmc.sampleAddress = 0xC000 | (UInt16(val) << 6)
end

function writelength!(dmc::DMC, val::UInt8)
  # Sample length = %0000LLLL.LLLL0001
  dmc.sampleLength = (UInt16(val) << 4) | 0x01
end

function restart!(dmc::DMC)
  dmc.currentAddress = dmc.sampleAddress
  dmc.currentLength = dmc.sampleLength
end

function stepshifter!(dmc::DMC)
  if dmc.bitCount == 0
    return
  end
  if (dmc.shiftRegister & 0x01) == 0x01
    if dmc.value <= 125
      dmc.value += 2
    end
  else
    if dmc.value >= 2
      dmc.value -= 2
    end
  end
  dmc.shiftRegister >>= 1
  dmc.bitCount -= 1
end

function output!(dmc::DMC)::UInt8
  dmc.value
end

# Filter

mutable struct Filter
  B0::Float32
  B1::Float32
  A1::Float32
  prevX::Float32
  prevY::Float32

  Filter(b0::Float32, b1::Float32, a1::Float32) = new(b0, b1, a1, 0.0, 0.0)
  Filter() = Filter(0.0f0, 0.0f0, 0.0f0)
end

function highpassfilter(sampleRate::Float32, cutoffFreq::Float32)::Filter
  c = sampleRate / π / cutoffFreq
  a0i = 1.0f0 / (1.0f0 + c)
  Filter(c * a0i, -c * a0i, (1.0f0 - c) * a0i)
end

function lowpassfilter(sampleRate::Float32, cutoffFreq::Float32)::Filter
  c = sampleRate / π / cutoffFreq
  a0i = 1.0f0 / (1.0f0 + c)
  Filter(a0i, a0i, (1.0f0 - c) * a0i)
end

function step!(f::Filter, x::Float32)::Float32
  y = f.B0 * x + f.B1 * f.prevX - f.A1 * f.prevY
  f.prevY = y
  f.prevX = x
  y
end

# FilterChain

mutable struct FilterChain
  filter1::Filter
  filter2::Filter
  filter3::Filter
  initialized::Bool

  FilterChain() = new(Filter(), Filter(), Filter(), false)
end

function setsamplerate!(fc::FilterChain, sampleRate::Float32)
  if sampleRate == 0.0f0
    fc.filter1 = Filter()
    fc.filter2 = Filter()
    fc.filter3 = Filter()
    fc.initialized = false
  else
    fc.filter1 = highpassfilter(sampleRate, 90.0f0)
    fc.filter2 = highpassfilter(sampleRate, 440.0f0)
    fc.filter3 = lowpassfilter(sampleRate, 14000.0f0)
    fc.initialized = true
  end
end

function step!(fc::FilterChain, x::Float32)::Float32
  if fc.initialized
    x = step!(fc.filter1, x)
    x = step!(fc.filter2, x)
    x = step!(fc.filter3, x)
  end
  x 
end

# AudioChannel

mutable struct AudioChannel
  values::Vector{Float32}
  position::UInt32

  AudioChannel(length::Integer) = new(zeros(Float32, length), 0)
end

function write!(ac::AudioChannel, val::Float32)
  if ac.position < length(ac.values)
    ac.values[ac.position + 1] = val
    ac.position += 1
  end
end

function reset!(ac::AudioChannel)
  ac.position = 0
end
