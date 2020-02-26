using Match

const PulseTable = map(x -> 95.52f0 / (8128.0f0/Float32(x) + 100.0f0), 0:30)

const TNDTable = map(x -> 163.67f0 / (24329.0f0/Float32(x) + 100.0f0), 0:202)

function apustep!(console::Console, apu::APU)
  apu.cycle += 1
  steptimer!(console, apu)
  #f1 = floor(Int32, Float64(cycle1) / frameCounterRate)
  #f2 = floor(Int32, Float64(cycle2) / frameCounterRate)
  apu.frameCounter += 240
  if apu.frameCounter >= cpuFrequency
    stepframecounter!(console)
    apu.frameCounter -= cpuFrequency
  end
  apu.sampleCounter += 1.0
  if apu.sampleCounter >= apu.sampleRate
    sendsample!(apu)
    apu.sampleCounter -= apu.sampleRate
  end
  #s1 = floor(Int32, Float64(cycle1) / apu.sampleRate)
  #s2 = floor(Int32, Float64(cycle2) / apu.sampleRate)
  #if s1 != s2
    #sendsample!(apu)
  #end
end

# mode 0:    mode 1:       function
# ---------  -----------  -----------------------------
#  - - - f    - - - - -    IRQ (if bit 6 is clear)
#  - l - l    l - l - -    Length counter and sweep
#  e e e e    e e e e -    Envelope and linear counter
function stepframecounter!(console::Console)
  apu = console.apu
  @match apu.framePeriod begin
    0x04 => begin
      apu.frameValue = (apu.frameValue + 0x01) & 0x03
      @match apu.frameValue begin
        0x00 => begin
          stepenvelope!(apu)
        end
        0x01 => begin
          stepenvelope!(apu)
          stepsweep!(apu)
          steplength!(apu)
        end
        0x02 => begin
          stepenvelope!(apu)
        end
        0x03 => begin
          stepenvelope!(apu)
          stepsweep!(apu)
          steplength!(apu)
          fireirq!(console)
        end
      end
    end
    0x05 => begin
      apu.frameValue = (apu.frameValue + 0x01) % 0x05
      @match apu.frameValue begin
        0x00 => begin
          stepenvelope!(apu)
        end
        0x01 => begin
          stepenvelope!(apu)
          stepsweep!(apu)
          steplength!(apu)
        end
        0x02 => begin
          stepenvelope!(apu)
        end
        0x04 => begin
          stepenvelope!(apu)
          stepsweep!(apu)
          steplength!(apu)
        end
      end
    end
  end
end

function sendsample!(apu::APU)
  out = step!(apu.filterChain, output!(apu))
  write!(apu.channel, out)
end

function output!(apu::APU)::Float32
  p1 = output!(apu.pulse1)
  p2 = output!(apu.pulse2)
  t = output!(apu.triangle)
  n = output!(apu.noise)
  d = output!(apu.dmc)
  pulseOut = PulseTable[p1 + p2 + 1]
  tndOut = TNDTable[3 * t + 2 * n + d + 1]
  return pulseOut + tndOut
end

function stepenvelope!(apu::APU)
  stepenvelope!(apu.pulse1)
  stepenvelope!(apu.pulse2)
  stepcounter!(apu.triangle)
  stepenvelope!(apu.noise)
end

function stepsweep!(apu::APU)
  stepsweep!(apu.pulse1)
  stepsweep!(apu.pulse2)
end

function steplength!(apu::APU)
  steplength!(apu.pulse1)
  steplength!(apu.pulse2)
  steplength!(apu.triangle)
  steplength!(apu.noise)
end

function readregister(apu::APU, address::UInt16)::UInt8
  @match address begin
    0x4015 => readstatus(apu)
    _ => begin
      # default:
      # TODO: add logging.
      # log.Fatalf("unhandled apu register read at address: 0x%04X", address)
      0x00
    end
  end
end

function apuwriteregister!(console::Console, address::UInt16, val::UInt8)
  apu = console.apu
  @match address begin
    0x4000 => begin
      writecontrol!(apu.pulse1, val)
    end
    0x4001 => begin
      writesweep!(apu.pulse1, val)
    end
    0x4002 => begin
      writetimerlow!(apu.pulse1, val)
    end
    0x4003 => begin
      writetimerhigh!(apu.pulse1, val)
    end
    0x4004 => begin
      writecontrol!(apu.pulse2, val)
    end
    0x4005 => begin
      writesweep!(apu.pulse2, val)
    end
    0x4006 => begin
      writetimerlow!(apu.pulse2, val)
    end
    0x4007 => begin
      writetimerhigh!(apu.pulse2, val)
    end
    0x4008 => begin
      writecontrol!(apu.triangle, val)
    end
    0x4009 => begin
    end
    0x4010 => begin
      writecontrol!(apu.dmc, val)
    end
    0x4011 => begin
      writevalue!(apu.dmc, val)
    end
    0x4012 => begin
      writeaddress!(apu.dmc, val)
    end
    0x4013 => begin
      writelength!(apu.dmc, val)
    end
    0x400A => begin
      writetimerlow!(apu.triangle, val)
    end
    0x400B => begin
      writetimerhigh!(apu.triangle, val)
    end
    0x400C => begin
      writecontrol!(apu.noise, val)
    end
    0x400D => begin
    end
    0x400E => begin
      writeperiod!(apu.noise, val)
    end
    0x400F => begin
      writelength!(apu.noise, val)
    end
    0x4015 => begin
      writecontrol!(apu, val)
    end
    0x4017 => begin
      writeframecounter!(apu, val)
    end
    _ => begin
      # default:
      #   log.Fatalf("unhandled apu register write at address: 0x%04X", address)
    end
  end
end

function readstatus(apu::APU)::UInt8
  result = 0x00
  if apu.pulse1.lengthValue > 0
    result |= 0x01
  end
  if apu.pulse2.lengthValue > 0
    result |= 0x02
  end
  if apu.triangle.lengthValue > 0
    result |= 0x04
  end
  if apu.noise.lengthValue > 0
    result |= 0x08
  end
  if apu.dmc.currentLength > 0
    result |= 0x10
  end
  return result
end

function writecontrol!(apu::APU, val::UInt8)
  pulse1 = apu.pulse1
  pulse1.enabled = (val & 1) == 1
  if !pulse1.enabled
    pulse1.lengthValue = 0
  end
  pulse2 = apu.pulse2
  pulse2.enabled = (val & 2) == 2
  if !pulse2.enabled
    pulse2.lengthValue = 0
  end
  triangle = apu.triangle
  triangle.enabled = (val & 4) == 4
  if !triangle.enabled
    triangle.lengthValue = 0
  end
  noise = apu.noise
  noise.enabled = (val & 8) == 8
  if !noise.enabled
    noise.lengthValue = 0
  end
  dmc = apu.dmc
  dmc.enabled = (val & 16) == 16
  if !dmc.enabled
    dmc.currentLength = 0
  else
    if dmc.currentLength == 0
      restart!(dmc)
    end
  end
end

function writeframecounter!(apu::APU, val::UInt8)
  apu.framePeriod = 0x04 + ((val >> 7) & 0x01)
  apu.frameIRQ = ((val >> 6) & 0x01) == 0x00
  # frameValue = 0
  if apu.framePeriod == 0x05
    stepenvelope!(apu)
    stepsweep!(apu)
    steplength!(apu)
  end
end
