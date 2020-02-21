using Match
using Printf

function cpureset!(console::Console)
  cpu = console.cpu
  cpu.PC = cpuread16(console, 0xFFFC)
  cpu.SP = 0xFD
  setflags!(cpu, 0x0024)
end

function cpuread(console::Console, address::UInt16)::UInt8
  if address < 0x2000
    @inbounds console.RAM[(address & 0x07FF) + 1]
  elseif address < 0x4000
    ppureadregister(console, 0x2000 + (address & 0x0007))
  elseif address == 0x4014
    ppureadregister(console, address)
  elseif address == 0x4015
    readregister(console.apu, address)
  elseif address == 0x4016
    read(console.controller1)
  elseif address == 0x4017
    read(console.controller2)
  else
    read(console.mapper, console.cartridge, address)
  end
end

function cpuwrite!(console::Console, address::UInt16, val::UInt8)
  if address < 0x2000
    @inbounds console.RAM[address & 0x07FF + 1] = val
  elseif address < 0x4000
    ppuwriteregister!(console, 0x2000 + (address & 0x07), val)
  elseif address < 0x4014
    apuwriteregister!(console, address, val)
  elseif address == 0x4014
    ppuwriteregister!(console, address, val)
  elseif address == 0x4015
    apuwriteregister!(console, address, val)
  elseif address == 0x4016
    write!(console.controller1, val)
    write!(console.controller2, val)
  elseif address == 0x4017
    apuwriteregister!(console, address, val)
  elseif address < 0x6000
      # TODO: I/O registers
  else
    write!(console.mapper, console.cartridge, address, val)
  end
end

# PrintInstruction prints the current CPU state
function printinstruction(console::Console)
  cpu = console.cpu
  opcode = cpuread(console, cpu.PC)
  @inbounds bytes = InstructionSizes[opcode + 1]
  @inbounds name = InstructionNames[opcode + 1]
  w0 = @sprintf("%02X", cpuread(console, cpu.PC + 0x00))
  w1 = @sprintf("%02X", cpuread(console, cpu.PC + 0x01))
  w2 = @sprintf("%02X", cpuread(console, cpu.PC + 0x02))
  if bytes < 2
    w1 = "  "
  end
  if bytes < 3
    w2 = "  "
  end
  @sprintf("%4X  %s %s %s  %s %28s A:%02X X:%02X Y:%02X P:%02X SP:%02X CYC:%3d\n",
      cpu.PC, w0, w1, w2, name, "", cpu.A, cpu.X, cpu.Y, flags(cpu), cpu.SP,
      UInt32((cpu.cycles * 3) % 341))
end

# pagesDiffer returns true if the two addresses reference different pages
function pagesdiffer(a::UInt16, b::UInt16)::Bool
  return (a & 0xFF00) != (b & 0xFF00)
end

# addBranchCycles adds a cycle for taking a branch and adds another cycle
# if the branch jumps to a new page
function addbranchcycles!(cpu::CPU, address::UInt16, pc::UInt16)
  cpu.cycles += 1
  if pagesdiffer(pc, address)
    cpu.cycles += 1
  end
end

function compare(cpu::CPU, a::UInt8, b::UInt8)
  setzn!(cpu, a - b)
  if a >= b
    cpu.C = 1
  else
    cpu.C = 0
  end
end

# Read16 reads two bytes using Read to return a double-word value
function cpuread16(console::Console, address::UInt16)::UInt16
  lo = cpuread(console, address)
  hi = cpuread(console, address + 0x0001)
  return (UInt16(hi) << 8) | lo
end

# read16bug emulates a 6502 bug that caused the low byte to wrap without
# incrementing the high byte
function cpuread16bug(console::Console, address::UInt16)::UInt16
  a = address
  b = (a & 0xFF00) | ((a % UInt8) + 0x01)
  lo = cpuread(console, a)
  hi = cpuread(console, b)
  return (UInt16(hi) << 8) | lo
end

# push pushes a byte onto the stack
function push!(console::Console, val::UInt8)
  cpu = console.cpu
  cpuwrite!(console, 0x100 | cpu.SP, val)
  cpu.SP -= 0x01
end

# pull pops a byte from the stack
function pull!(console::Console)::UInt8
  cpu = console.cpu
  cpu.SP += 0x01
  return cpuread(console, 0x100 | cpu.SP)
end

# push16 pushes two bytes onto the stack
function push16!(console::Console, val::UInt16)
  cpu = console.cpu
  hi = UInt8(val >> 8)
  lo = val % UInt8
  push!(console, hi)
  push!(console, lo)
end

# pull16 pops two bytes from the stack
function pull16!(console::Console)::UInt16
  lo = pull!(console)
  hi = UInt16(pull!(console))
  return (hi << 8) | lo
end

# Flags returns the processor status flags
function flags(cpu::CPU)::UInt8
  flags = 0x00
  flags |= (cpu.C << 0)
  flags |= (cpu.Z << 1)
  flags |= (cpu.I << 2)
  flags |= (cpu.D << 3)
  flags |= (cpu.B << 4)
  flags |= (cpu.U << 5)
  flags |= (cpu.V << 6)
  flags |= (cpu.N << 7)
  flags
end

# SetFlags sets the processor status flags
function setflags!(cpu::CPU, flags::UInt16)
  cpu.C = (flags >> 0) & 1
  cpu.Z = (flags >> 1) & 1
  cpu.I = (flags >> 2) & 1
  cpu.D = (flags >> 3) & 1
  cpu.B = (flags >> 4) & 1
  cpu.U = (flags >> 5) & 1
  cpu.V = (flags >> 6) & 1
  cpu.N = (flags >> 7) & 1
end

# setZ sets the zero flag if the argument is zero
function setz!(cpu::CPU, val::UInt8)
  if val == 0
    cpu.Z = 1
  else
    cpu.Z = 0
  end
end

# setN sets the negative flag if the argument is negative (high bit is set)
function setn!(cpu::CPU, val::UInt8)
  if (val & 0x80) != 0
    cpu.N = 1
  else
    cpu.N = 0
  end
end

# setZN sets the zero flag and the negative flag
function setzn!(cpu::CPU, val::UInt8)
  setz!(cpu, val)
  setn!(cpu, val)
end

# Step executes a single CPU instruction
function cpustep!(console::Console, cpu::CPU)::Int32
  if cpu.stall > 0
    cpu.stall -= Int32(1)
    return Int32(1)
  end

  prevCycles = cpu.cycles

  interruptInt = UInt8(cpu.interrupt)
  if interruptInt == 0x01
    nmi!(console)
  elseif interruptInt == 0x02
    irq!(console)
  end
  cpu.interrupt = InterruptNone::InterruptTypes

  opcode = cpuread(console, cpu.PC)
  @inbounds mode = InstructionModes[opcode + 1]

  address = 0x0000
  pageCrossed = false
  modeInt = UInt8(mode)
  if modeInt == 0x01
    address = cpuread16(console, cpu.PC + 0x01)
  elseif modeInt == 0x02
    address = cpuread16(console, cpu.PC + 0x01) + cpu.X
    pageCrossed = pagesdiffer(address - cpu.X, address)
  elseif modeInt == 0x03
    address = cpuread16(console, cpu.PC + 0x01) + cpu.Y
    pageCrossed = pagesdiffer(address - cpu.Y, address)
  elseif modeInt == 0x04
    address = 0x0000
  elseif modeInt == 0x05
    address = cpu.PC + 0x01
  elseif modeInt == 0x06
    address = 0x0000
  elseif modeInt == 0x07
    address = cpuread16bug(console, UInt16(cpuread(console, cpu.PC + 0x01) + cpu.X))
  elseif modeInt == 0x08
    address = cpuread16bug(console, cpuread16(console, cpu.PC + 0x01))
  elseif modeInt == 0x09
    address = cpuread16bug(console, UInt16(cpuread(console, cpu.PC + 0x01))) + cpu.Y
    pageCrossed = pagesdiffer(address - cpu.Y, address)
  elseif modeInt == 0x0A
    offset = cpuread(console, cpu.PC + 0x01)
    if offset < 0x80
      address = cpu.PC + 0x02 + offset
    else
      address = cpu.PC + 0x02 + offset - 0x100
    end
  elseif modeInt == 0x0B
    address = UInt16(cpuread(console, cpu.PC + 0x01))
  elseif modeInt == 0x0C
    address = (UInt16(cpuread(console, cpu.PC + 0x01)) + cpu.X) & 0xff
  elseif modeInt == 0x0D
    address = (UInt16(cpuread(console, cpu.PC + 0x01)) + cpu.Y) & 0xff
  end

  @inbounds cpu.PC += InstructionSizes[opcode + 1]
  @inbounds cpu.cycles += InstructionCycles[opcode + 1]
  if pageCrossed
    @inbounds cpu.cycles += InstructionPageCycles[opcode + 1]
  end

  if opcode == 0
    brk!(console, address)
  elseif opcode == 1
    ora!(console, address)
  elseif opcode == 2
    kil!(console, address)
  elseif opcode == 3
    slo!(console, address)
  elseif opcode == 4
    nop!(console, address)
  elseif opcode == 5
    ora!(console, address)
  elseif opcode == 6
    asl!(console, address, mode)
  elseif opcode == 7
    slo!(console, address)
  elseif opcode == 8
    php!(console)
  elseif opcode == 9
    ora!(console, address)
  elseif opcode == 10
    asl!(console, address, mode)
  elseif opcode == 11
    anc!(console, address)
  elseif opcode == 12
    nop!(console, address)
  elseif opcode == 13
    ora!(console, address)
  elseif opcode == 14
    asl!(console, address, mode)
  elseif opcode == 15
    slo!(console, address)
  elseif opcode == 16
    bpl!(console, address, cpu.PC)
  elseif opcode == 17
    ora!(console, address)
  elseif opcode == 18
    kil!(console, address)
  elseif opcode == 19
    slo!(console, address)
  elseif opcode == 20
    nop!(console, address)
  elseif opcode == 21
    ora!(console, address)
  elseif opcode == 22
    asl!(console, address, mode)
  elseif opcode == 23
    slo!(console, address)
  elseif opcode == 24
    clc!(console, address)
  elseif opcode == 25
    ora!(console, address)
  elseif opcode == 26
    nop!(console, address)
  elseif opcode == 27
    slo!(console, address)
  elseif opcode == 28
    nop!(console, address)
  elseif opcode == 29
    ora!(console, address)
  elseif opcode == 30
    asl!(console, address, mode)
  elseif opcode == 31
    slo!(console, address)
  elseif opcode == 32
    jsr!(console, address)
  elseif opcode == 33
    and!(console, address)
  elseif opcode == 34
    kil!(console, address)
  elseif opcode == 35
    rla!(console, address)
  elseif opcode == 36
    bit!(console, address)
  elseif opcode == 37
    and!(console, address)
  elseif opcode == 38
    rol!(console, address, mode)
  elseif opcode == 39
    rla!(console, address)
  elseif opcode == 40
    plp!(console, address)
  elseif opcode == 41
    and!(console, address)
  elseif opcode == 42
    rol!(console, address, mode)
  elseif opcode == 43
    anc!(console, address)
  elseif opcode == 44
    bit!(console, address)
  elseif opcode == 45
    and!(console, address)
  elseif opcode == 46
    rol!(console, address, mode)
  elseif opcode == 47
    rla!(console, address)
  elseif opcode == 48
    bmi!(console, address, cpu.PC)
  elseif opcode == 49
    and!(console, address)
  elseif opcode == 50
    kil!(console, address)
  elseif opcode == 51
    rla!(console, address)
  elseif opcode == 52
    nop!(console, address)
  elseif opcode == 53
    and!(console, address)
  elseif opcode == 54
    rol!(console, address, mode)
  elseif opcode == 55
    rla!(console, address)
  elseif opcode == 56
    sec!(console, address)
  elseif opcode == 57
    and!(console, address)
  elseif opcode == 58
    nop!(console, address)
  elseif opcode == 59
    rla!(console, address)
  elseif opcode == 60
    nop!(console, address)
  elseif opcode == 61
    and!(console, address)
  elseif opcode == 62
    rol!(console, address, mode)
  elseif opcode == 63
    rla!(console, address)
  elseif opcode == 64
    rti!(console, address)
  elseif opcode == 65
    eor!(console, address)
  elseif opcode == 66
    kil!(console, address)
  elseif opcode == 67
    sre!(console, address)
  elseif opcode == 68
    nop!(console, address)
  elseif opcode == 69
    eor!(console, address)
  elseif opcode == 70
    lsr!(console, address, mode)
  elseif opcode == 71
    sre!(console, address)
  elseif opcode == 72
    pha!(console, address)
  elseif opcode == 73
    eor!(console, address)
  elseif opcode == 74
    lsr!(console, address, mode)
  elseif opcode == 75
    alr!(console, address)
  elseif opcode == 76
    jmp!(console, address)
  elseif opcode == 77
    eor!(console, address)
  elseif opcode == 78
    lsr!(console, address, mode)
  elseif opcode == 79
    sre!(console, address)
  elseif opcode == 80
    bvc!(console, address, cpu.PC)
  elseif opcode == 81
    eor!(console, address)
  elseif opcode == 82
    kil!(console, address)
  elseif opcode == 83
    sre!(console, address)
  elseif opcode == 84
    nop!(console, address)
  elseif opcode == 85
    eor!(console, address)
  elseif opcode == 86
    lsr!(console, address, mode)
  elseif opcode == 87
    sre!(console, address)
  elseif opcode == 88
    cli!(console, address)
  elseif opcode == 89
    eor!(console, address)
  elseif opcode == 90
    nop!(console, address)
  elseif opcode == 91
    sre!(console, address)
  elseif opcode == 92
    nop!(console, address)
  elseif opcode == 93
    eor!(console, address)
  elseif opcode == 94
    lsr!(console, address, mode)
  elseif opcode == 95
    sre!(console, address)
  elseif opcode == 96
    rts!(console, address)
  elseif opcode == 97
    adc!(console, address)
  elseif opcode == 98
    kil!(console, address)
  elseif opcode == 99
    rra!(console, address)
  elseif opcode == 100
    nop!(console, address)
  elseif opcode == 101
    adc!(console, address)
  elseif opcode == 102
    ror!(console, address, mode)
  elseif opcode == 103
    rra!(console, address)
  elseif opcode == 104
    pla!(console, address)
  elseif opcode == 105
    adc!(console, address)
  elseif opcode == 106
    ror!(console, address, mode)
  elseif opcode == 107
    arr!(console, address)
  elseif opcode == 108
    jmp!(console, address)
  elseif opcode == 109
    adc!(console, address)
  elseif opcode == 110
    ror!(console, address, mode)
  elseif opcode == 111
    rra!(console, address)
  elseif opcode == 112
    bvs!(console, address, cpu.PC)
  elseif opcode == 113
    adc!(console, address)
  elseif opcode == 114
    kil!(console, address)
  elseif opcode == 115
    rra!(console, address)
  elseif opcode == 116
    nop!(console, address)
  elseif opcode == 117
    adc!(console, address)
  elseif opcode == 118
    ror!(console, address, mode)
  elseif opcode == 119
    rra!(console, address)
  elseif opcode == 120
    sei!(console)
  elseif opcode == 121
    adc!(console, address)
  elseif opcode == 122
    nop!(console, address)
  elseif opcode == 123
    rra!(console, address)
  elseif opcode == 124
    nop!(console, address)
  elseif opcode == 125
    adc!(console, address)
  elseif opcode == 126
    ror!(console, address, mode)
  elseif opcode == 127
    rra!(console, address)
  elseif opcode == 128
    nop!(console, address)
  elseif opcode == 129
    sta!(console, address)
  elseif opcode == 130
    nop!(console, address)
  elseif opcode == 131
    sax!(console, address)
  elseif opcode == 132
    sty!(console, address)
  elseif opcode == 133
    sta!(console, address)
  elseif opcode == 134
    stx!(console, address)
  elseif opcode == 135
    sax!(console, address)
  elseif opcode == 136
    dey!(console, address)
  elseif opcode == 137
    nop!(console, address)
  elseif opcode == 138
    txa!(console, address)
  elseif opcode == 139
    xaa!(console, address)
  elseif opcode == 140
    sty!(console, address)
  elseif opcode == 141
    sta!(console, address)
  elseif opcode == 142
    stx!(console, address)
  elseif opcode == 143
    sax!(console, address)
  elseif opcode == 144
    bcc!(console, address, cpu.PC)
  elseif opcode == 145
    sta!(console, address)
  elseif opcode == 146
    kil!(console, address)
  elseif opcode == 147
    ahx!(console, address)
  elseif opcode == 148
    sty!(console, address)
  elseif opcode == 149
    sta!(console, address)
  elseif opcode == 150
    stx!(console, address)
  elseif opcode == 151
    sax!(console, address)
  elseif opcode == 152
    tya!(console, address)
  elseif opcode == 153
    sta!(console, address)
  elseif opcode == 154
    txs!(console, address)
  elseif opcode == 155
    tas!(console, address)
  elseif opcode == 156
    shy!(console, address)
  elseif opcode == 157
    sta!(console, address)
  elseif opcode == 158
    shx!(console, address)
  elseif opcode == 159
    ahx!(console, address)
  elseif opcode == 160
    ldy!(console, address)
  elseif opcode == 161
    lda!(console, address)
  elseif opcode == 162
    ldx!(console, address)
  elseif opcode == 163
    lax!(console, address)
  elseif opcode == 164
    ldy!(console, address)
  elseif opcode == 165
    lda!(console, address)
  elseif opcode == 166
    ldx!(console, address)
  elseif opcode == 167
    lax!(console, address)
  elseif opcode == 168
    tay!(console, address)
  elseif opcode == 169
    lda!(console, address)
  elseif opcode == 170
    tax!(console, address)
  elseif opcode == 171
    lax!(console, address)
  elseif opcode == 172
    ldy!(console, address)
  elseif opcode == 173
    lda!(console, address)
  elseif opcode == 174
    ldx!(console, address)
  elseif opcode == 175
    lax!(console, address)
  elseif opcode == 176
    bcs!(console, address, cpu.PC)
  elseif opcode == 177
    lda!(console, address)
  elseif opcode == 178
    kil!(console, address)
  elseif opcode == 179
    lax!(console, address)
  elseif opcode == 180
    ldy!(console, address)
  elseif opcode == 181
    lda!(console, address)
  elseif opcode == 182
    ldx!(console, address)
  elseif opcode == 183
    lax!(console, address)
  elseif opcode == 184
    clv!(console, address)
  elseif opcode == 185
    lda!(console, address)
  elseif opcode == 186
    tsx!(console, address)
  elseif opcode == 187
    las!(console, address)
  elseif opcode == 188
    ldy!(console, address)
  elseif opcode == 189
    lda!(console, address)
  elseif opcode == 190
    ldx!(console, address)
  elseif opcode == 191
    lax!(console, address)
  elseif opcode == 192
    cpy!(console, address)
  elseif opcode == 193
    cmp!(console, address)
  elseif opcode == 194
    nop!(console, address)
  elseif opcode == 195
    dcp!(console, address)
  elseif opcode == 196
    cpy!(console, address)
  elseif opcode == 197
    cmp!(console, address)
  elseif opcode == 198
    dec!(console, address)
  elseif opcode == 199
    dcp!(console, address)
  elseif opcode == 200
    iny!(console, address)
  elseif opcode == 201
    cmp!(console, address)
  elseif opcode == 202
    dex!(console, address)
  elseif opcode == 203
    axs!(console, address)
  elseif opcode == 204
    cpy!(console, address)
  elseif opcode == 205
    cmp!(console, address)
  elseif opcode == 206
    dec!(console, address)
  elseif opcode == 207
    dcp!(console, address)
  elseif opcode == 208
    bne!(console, address, cpu.PC)
  elseif opcode == 209
    cmp!(console, address)
  elseif opcode == 210
    kil!(console, address)
  elseif opcode == 211
    dcp!(console, address)
  elseif opcode == 212
    nop!(console, address)
  elseif opcode == 213
    cmp!(console, address)
  elseif opcode == 214
    dec!(console, address)
  elseif opcode == 215
    dcp!(console, address)
  elseif opcode == 216
    cld!(console, address)
  elseif opcode == 217
    cmp!(console, address)
  elseif opcode == 218
    nop!(console, address)
  elseif opcode == 219
    dcp!(console, address)
  elseif opcode == 220
    nop!(console, address)
  elseif opcode == 221
    cmp!(console, address)
  elseif opcode == 222
    dec!(console, address)
  elseif opcode == 223
    dcp!(console, address)
  elseif opcode == 224
    cpx!(console, address)
  elseif opcode == 225
    sbc!(console, address)
  elseif opcode == 226
    nop!(console, address)
  elseif opcode == 227
    isc!(console, address)
  elseif opcode == 228
    cpx!(console, address)
  elseif opcode == 229
    sbc!(console, address)
  elseif opcode == 230
    inc!(console, address)
  elseif opcode == 231
    isc!(console, address)
  elseif opcode == 232
    inx!(console, address)
  elseif opcode == 233
    sbc!(console, address)
  elseif opcode == 234
    nop!(console, address)
  elseif opcode == 235
    sbc!(console, address)
  elseif opcode == 236
    cpx!(console, address)
  elseif opcode == 237
    sbc!(console, address)
  elseif opcode == 238
    inc!(console, address)
  elseif opcode == 239
    isc!(console, address)
  elseif opcode == 240
    beq!(console, address, cpu.PC)
  elseif opcode == 241
    sbc!(console, address)
  elseif opcode == 242
    kil!(console, address)
  elseif opcode == 243
    isc!(console, address)
  elseif opcode == 244
    nop!(console, address)
  elseif opcode == 245
    sbc!(console, address)
  elseif opcode == 246
    inc!(console, address)
  elseif opcode == 247
    isc!(console, address)
  elseif opcode == 248
    sed!(console, address)
  elseif opcode == 249
    sbc!(console, address)
  elseif opcode == 250
    nop!(console, address)
  elseif opcode == 251
    isc!(console, address)
  elseif opcode == 252
    nop!(console, address)
  elseif opcode == 253
    sbc!(console, address)
  elseif opcode == 254
    inc!(console, address)
  elseif opcode == 255
    isc!(console, address)
  end

  return Int32(cpu.cycles - prevCycles)
end

# NMI - Non-Maskable Interrupt
function nmi!(console::Console)
  cpu = console.cpu
  push16!(console, cpu.PC)
  php!(console)
  cpu.PC = cpuread16(console, 0xFFFA)
  cpu.I = 1
  cpu.cycles += 7
end

# IRQ - IRQ Interrupt
function irq!(console::Console)
  cpu = console.cpu
  push16!(console, cpu.PC)
  php!(console)
  cpu.PC = cpuread16(console, 0xFFFE)
  cpu.I = 1
  cpu.cycles += 7
end

# ADC - Add with Carry
function adc!(console::Console, address::UInt16)
  cpu = console.cpu
  a = cpu.A
  b = cpuread(console, address)
  c = cpu.C
  sum = UInt16(a) + UInt16(b) + UInt16(c)
  cpu.A = sum % UInt8
  setzn!(cpu, cpu.A)
  if sum > 0xFF
    cpu.C = 1
  else
    cpu.C = 0
  end
  if ((a ⊻ b) & 0x80) == 0 && ((a ⊻ cpu.A) & 0x80) != 0
    cpu.V = 1
  else
    cpu.V = 0
  end
end

# AND - Logical AND
function and!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.A = cpu.A & cpuread(console, address)
  setzn!(cpu, cpu.A)
end

# ASL - Arithmetic Shift Left
function asl!(console::Console, address::UInt16, mode::AddressingModes)
  cpu = console.cpu
  if mode == ModeAccumulator::AddressingModes
    cpu.C = (cpu.A >> 7) & 1
    cpu.A <<= 1
    setzn!(cpu, cpu.A)
  else
    val = cpuread(console, address)
    cpu.C = (val >> 7) & 1
    val <<= 1
    cpuwrite!(console, address, val)
    setzn!(cpu, val)
  end
end

# BCC - Branch if Carry Clear
function bcc!(console::Console, address::UInt16, pc::UInt16)
  cpu = console.cpu
  if cpu.C == 0
    cpu.PC = address
    addbranchcycles!(cpu, address, pc)
  end
end

# BCS - Branch if Carry Set
function bcs!(console::Console, address::UInt16, pc::UInt16)
  cpu = console.cpu
  if cpu.C != 0
    cpu.PC = address
    addbranchcycles!(cpu, address, pc)
  end
end

# BEQ - Branch if Equal
function beq!(console::Console, address::UInt16, pc::UInt16)
  cpu = console.cpu
  if cpu.Z != 0
    cpu.PC = address
    addbranchcycles!(cpu, address, pc)
  end
end

# BIT - Bit Test
function bit!(console::Console, address::UInt16)
  cpu = console.cpu
  val = cpuread(console, address)
  cpu.V = (val >> 6) & 1
  setz!(cpu, val & cpu.A)
  setn!(cpu, val)
end

# BMI - Branch if Minus
function bmi!(console::Console, address::UInt16, pc::UInt16)
  cpu = console.cpu
  if cpu.N != 0
    cpu.PC = address
    addbranchcycles!(cpu, address, pc)
  end
end

# BNE - Branch if Not Equal
function bne!(console::Console, address::UInt16, pc::UInt16)
  cpu = console.cpu
  if cpu.Z == 0
    cpu.PC = address
    addbranchcycles!(cpu, address, pc)
  end
end

# BPL - Branch if Positive
function bpl!(console::Console, address::UInt16, pc::UInt16)
  cpu = console.cpu
  if cpu.N == 0
    cpu.PC = address
    addbranchcycles!(cpu, address, pc)
  end
end

# BRK - Force Interrupt
function brk!(console::Console, address::UInt16)
  cpu = console.cpu
  push16!(console, cpu.PC)
  php!(console)
  sei!(console)
  cpu.PC = cpuread16(console, 0xFFFE)
end

# BVC - Branch if Overflow Clear
function bvc!(console::Console, address::UInt16, pc::UInt16)
  cpu = console.cpu
  if cpu.V == 0
    cpu.PC = address
    addbranchcycles!(cpu, address, pc)
  end
end

# BVS - Branch if Overflow Set
function bvs!(console::Console, address::UInt16, pc::UInt16)
  cpu = console.cpu
  if cpu.V != 0
    cpu.PC = address
    addbranchcycles!(cpu, address, pc)
  end
end

# CLC - Clear Carry Flag
function clc!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.C = 0
end

# CLD - Clear Decimal Mode
function cld!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.D = 0
end

# CLI - Clear Interrupt Disable
function cli!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.I = 0
end

# CLV - Clear Overflow Flag
function clv!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.V = 0
end

# CMP - Compare
function cmp!(console::Console, address::UInt16)
  cpu = console.cpu
  val = cpuread(console, address)
  compare(cpu, cpu.A, val)
end

# CPX - Compare X Register
function cpx!(console::Console, address::UInt16)
  cpu = console.cpu
  val = cpuread(console, address)
  compare(cpu, cpu.X, val)
end

# CPY - Compare Y Register
function cpy!(console::Console, address::UInt16)
  cpu = console.cpu
  val = cpuread(console, address)
  compare(cpu, cpu.Y, val)
end

# DEC - Decrement Memory
function dec!(console::Console, address::UInt16)
  cpu = console.cpu
  val = cpuread(console, address) - 0x01
  cpuwrite!(console, address, val)
  setzn!(cpu, val)
end

# DEX - Decrement X Register
function dex!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.X -= 0x01
  setzn!(cpu, cpu.X)
end

# DEY - Decrement Y Register
function dey!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.Y -= 0x01
  setzn!(cpu, cpu.Y)
end

# EOR - Exclusive OR
function eor!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.A = cpu.A ⊻ cpuread(console, address)
  setzn!(cpu, cpu.A)
end

# INC - Increment Memory
function inc!(console::Console, address::UInt16)
  cpu = console.cpu
  val = cpuread(console, address) + 0x01
  cpuwrite!(console, address, val)
  setzn!(cpu, val)
end

# INX - Increment X Register
function inx!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.X += 0x01
  setzn!(cpu, cpu.X)
end

# INY - Increment Y Register
function iny!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.Y += 0x01
  setzn!(cpu, cpu.Y)
end

# JMP - Jump
function jmp!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.PC = address
end

# JSR - Jump to Subroutine
function jsr!(console::Console, address::UInt16)
  cpu = console.cpu
  push16!(console, cpu.PC - 0x01)
  cpu.PC = address
end

# LDA - Load Accumulator
function lda!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.A = cpuread(console, address)
  setzn!(cpu, cpu.A)
end

# LDX - Load X Register
function ldx!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.X = cpuread(console, address)
  setzn!(cpu, cpu.X)
end

# LDY - Load Y Register
function ldy!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.Y = cpuread(console, address)
  setzn!(cpu, cpu.Y)
end

# LSR - Logical Shift Right
function lsr!(console::Console, address::UInt16, mode::AddressingModes)
  cpu = console.cpu
  if mode == ModeAccumulator::AddressingModes
    cpu.C = cpu.A & 1
    cpu.A >>= 1
    setzn!(cpu, cpu.A)
  else
    val = cpuread(console, address)
    cpu.C = val & 1
    val >>= 1
    cpuwrite!(console, address, val)
    setzn!(cpu, val)
  end
end

# NOP - No Operation
function nop!(console::Console, address::UInt16)
end

# ORA - Logical Inclusive OR
function ora!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.A = cpu.A | cpuread(console, address)
  setzn!(cpu, cpu.A)
end

# PHA - Push Accumulator
function pha!(console::Console, address::UInt16)
  cpu = console.cpu
  push!(console, cpu.A)
end

# PHP - Push Processor Status
function php!(console::Console)
  cpu = console.cpu
  push!(console, flags(cpu) | 0x10)
end

# PLA - Pull Accumulator
function pla!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.A = pull!(console)
  setzn!(cpu, cpu.A)
end

# PLP - Pull Processor Status
function plp!(console::Console, address::UInt16)
  cpu = console.cpu
  setflags!(cpu, (pull!(console)&0x00EF) | 0x20)
end

# ROL - Rotate Left
function rol!(console::Console, address::UInt16, mode::AddressingModes)
  cpu = console.cpu
  if mode == ModeAccumulator::AddressingModes
    c = cpu.C
    cpu.C = (cpu.A >> 7) & 1
    cpu.A = (cpu.A << 1) | c
    setzn!(cpu, cpu.A)
  else
    c = cpu.C
    val = cpuread(console, address)
    cpu.C = (val >> 7) & 1
    val = (val << 1) | c
    cpuwrite!(console, address, val)
    setzn!(cpu, val)
  end
end

# ROR - Rotate Right
function ror!(console::Console, address::UInt16, mode::AddressingModes)
  cpu = console.cpu
  if mode == ModeAccumulator::AddressingModes
    c = cpu.C
    cpu.C = cpu.A & 1
    cpu.A = (cpu.A >> 1) | (c << 7)
    setzn!(cpu, cpu.A)
  else
    c = cpu.C
    val = cpuread(console, address)
    cpu.C = val & 1
    val = (val >> 1) | (c << 7)
    cpuwrite!(console, address, val)
    setzn!(cpu, val)
  end
end

# RTI - Return from Interrupt
function rti!(console::Console, address::UInt16)
  cpu = console.cpu
  setflags!(cpu, (pull!(console)&0x00EF) | 0x20)
  cpu.PC = pull16!(console)
end

# RTS - Return from Subroutine
function rts!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.PC = pull16!(console) + 1
end

# SBC - Subtract with Carry
function sbc!(console::Console, address::UInt16)
  cpu = console.cpu
  a = cpu.A
  b = cpuread(console, address)
  c = cpu.C
  sum = Int16(a) - Int16(b) - (1 - Int16(c))
  cpu.A = sum % UInt8
  setzn!(cpu, cpu.A)
  if sum >= 0
    cpu.C = 1
  else
    cpu.C = 0
  end
  if ((a ⊻ b) & 0x80) != 0 && ((a ⊻ cpu.A) & 0x80) != 0
    cpu.V = 1
  else
    cpu.V = 0
  end
end

# SEC - Set Carry Flag
function sec!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.C = 1
end

# SED - Set Decimal Flag
function sed!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.D = 1
end

# SEI - Set Interrupt Disable
function sei!(console::Console)
  cpu = console.cpu
  cpu.I = 1
end

# STA - Store Accumulator
function sta!(console::Console, address::UInt16)
  cpu = console.cpu
  cpuwrite!(console, address, cpu.A)
end

# STX - Store X Register
function stx!(console::Console, address::UInt16)
  cpu = console.cpu
  cpuwrite!(console, address, cpu.X)
end

# STY - Store Y Register
function sty!(console::Console, address::UInt16)
  cpu = console.cpu
  cpuwrite!(console, address, cpu.Y)
end

# TAX - Transfer Accumulator to X
function tax!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.X = cpu.A
  setzn!(cpu, cpu.X)
end

# TAY - Transfer Accumulator to Y
function tay!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.Y = cpu.A
  setzn!(cpu, cpu.Y)
end

# TSX - Transfer Stack Pointer to X
function tsx!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.X = cpu.SP
  setzn!(cpu, cpu.X)
end

# TXA - Transfer X to Accumulator
function txa!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.A = cpu.X
  setzn!(cpu, cpu.A)
end

# TXS - Transfer X to Stack Pointer
function txs!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.SP = cpu.X
end

# TYA - Transfer Y to Accumulator
function tya!(console::Console, address::UInt16)
  cpu = console.cpu
  cpu.A = cpu.Y
  setzn!(cpu, cpu.A)
end

# illegal opcodes below

function ahx!(console::Console, address::UInt16)
end

function alr!(console::Console, address::UInt16)
end

function anc!(console::Console, address::UInt16)
end

function arr!(console::Console, address::UInt16)
end

function axs!(console::Console, address::UInt16)
end

function dcp!(console::Console, address::UInt16)
end

function isc!(console::Console, address::UInt16)
end

function kil!(console::Console, address::UInt16)
end

function las!(console::Console, address::UInt16)
end

function lax!(console::Console, address::UInt16)
end

function rla!(console::Console, address::UInt16)
end

function rra!(console::Console, address::UInt16)
end

function sax!(console::Console, address::UInt16)
end

function shx!(console::Console, address::UInt16)
end

function shy!(console::Console, address::UInt16)
end

function slo!(console::Console, address::UInt16)
end

function sre!(console::Console, address::UInt16)
end

function tas!(console::Console, address::UInt16)
end

function xaa!(console::Console, address::UInt16)
end

# function table for each instruction
const InstructionTable = [
  brk!, ora!, kil!, slo!, nop!, ora!, asl!, slo!,
  php!, ora!, asl!, anc!, nop!, ora!, asl!, slo!,
  bpl!, ora!, kil!, slo!, nop!, ora!, asl!, slo!,
  clc!, ora!, nop!, slo!, nop!, ora!, asl!, slo!,
  jsr!, and!, kil!, rla!, bit!, and!, rol!, rla!,
  plp!, and!, rol!, anc!, bit!, and!, rol!, rla!,
  bmi!, and!, kil!, rla!, nop!, and!, rol!, rla!,
  sec!, and!, nop!, rla!, nop!, and!, rol!, rla!,
  rti!, eor!, kil!, sre!, nop!, eor!, lsr!, sre!,
  pha!, eor!, lsr!, alr!, jmp!, eor!, lsr!, sre!,
  bvc!, eor!, kil!, sre!, nop!, eor!, lsr!, sre!,
  cli!, eor!, nop!, sre!, nop!, eor!, lsr!, sre!,
  rts!, adc!, kil!, rra!, nop!, adc!, ror!, rra!,
  pla!, adc!, ror!, arr!, jmp!, adc!, ror!, rra!,
  bvs!, adc!, kil!, rra!, nop!, adc!, ror!, rra!,
  sei!, adc!, nop!, rra!, nop!, adc!, ror!, rra!,
  nop!, sta!, nop!, sax!, sty!, sta!, stx!, sax!,
  dey!, nop!, txa!, xaa!, sty!, sta!, stx!, sax!,
  bcc!, sta!, kil!, ahx!, sty!, sta!, stx!, sax!,
  tya!, sta!, txs!, tas!, shy!, sta!, shx!, ahx!,
  ldy!, lda!, ldx!, lax!, ldy!, lda!, ldx!, lax!,
  tay!, lda!, tax!, lax!, ldy!, lda!, ldx!, lax!,
  bcs!, lda!, kil!, lax!, ldy!, lda!, ldx!, lax!,
  clv!, lda!, tsx!, las!, ldy!, lda!, ldx!, lax!,
  cpy!, cmp!, nop!, dcp!, cpy!, cmp!, dec!, dcp!,
  iny!, cmp!, dex!, axs!, cpy!, cmp!, dec!, dcp!,
  bne!, cmp!, kil!, dcp!, nop!, cmp!, dec!, dcp!,
  cld!, cmp!, nop!, dcp!, nop!, cmp!, dec!, dcp!,
  cpx!, sbc!, nop!, isc!, cpx!, sbc!, inc!, isc!,
  inx!, sbc!, nop!, sbc!, cpx!, sbc!, inc!, isc!,
  beq!, sbc!, kil!, isc!, nop!, sbc!, inc!, isc!,
  sed!, sbc!, nop!, isc!, nop!, sbc!, inc!, isc!
]

# InstructionModes indicates the addressing mode for each instruction
const InstructionModes = [
  AddressingModes(6), AddressingModes(7), AddressingModes(6), AddressingModes(7),
  AddressingModes(11), AddressingModes(11), AddressingModes(11), AddressingModes(11),
  AddressingModes(6), AddressingModes(5), AddressingModes(4), AddressingModes(5),
  AddressingModes(1), AddressingModes(1), AddressingModes(1), AddressingModes(1),
  AddressingModes(10), AddressingModes(9), AddressingModes(6), AddressingModes(9),
  AddressingModes(12), AddressingModes(12), AddressingModes(12), AddressingModes(12),
  AddressingModes(6), AddressingModes(3), AddressingModes(6), AddressingModes(3),
  AddressingModes(2), AddressingModes(2), AddressingModes(2), AddressingModes(2),
  AddressingModes(1), AddressingModes(7), AddressingModes(6), AddressingModes(7),
  AddressingModes(11), AddressingModes(11), AddressingModes(11), AddressingModes(11),
  AddressingModes(6), AddressingModes(5), AddressingModes(4), AddressingModes(5),
  AddressingModes(1), AddressingModes(1), AddressingModes(1), AddressingModes(1),
  AddressingModes(10), AddressingModes(9), AddressingModes(6), AddressingModes(9),
  AddressingModes(12), AddressingModes(12), AddressingModes(12), AddressingModes(12),
  AddressingModes(6), AddressingModes(3), AddressingModes(6), AddressingModes(3),
  AddressingModes(2), AddressingModes(2), AddressingModes(2), AddressingModes(2),
  AddressingModes(6), AddressingModes(7), AddressingModes(6), AddressingModes(7),
  AddressingModes(11), AddressingModes(11), AddressingModes(11), AddressingModes(11),
  AddressingModes(6), AddressingModes(5), AddressingModes(4), AddressingModes(5),
  AddressingModes(1), AddressingModes(1), AddressingModes(1), AddressingModes(1),
  AddressingModes(10), AddressingModes(9), AddressingModes(6), AddressingModes(9),
  AddressingModes(12), AddressingModes(12), AddressingModes(12), AddressingModes(12),
  AddressingModes(6), AddressingModes(3), AddressingModes(6), AddressingModes(3),
  AddressingModes(2), AddressingModes(2), AddressingModes(2), AddressingModes(2),
  AddressingModes(6), AddressingModes(7), AddressingModes(6), AddressingModes(7),
  AddressingModes(11), AddressingModes(11), AddressingModes(11), AddressingModes(11),
  AddressingModes(6), AddressingModes(5), AddressingModes(4), AddressingModes(5),
  AddressingModes(8), AddressingModes(1), AddressingModes(1), AddressingModes(1),
  AddressingModes(10), AddressingModes(9), AddressingModes(6), AddressingModes(9),
  AddressingModes(12), AddressingModes(12), AddressingModes(12), AddressingModes(12),
  AddressingModes(6), AddressingModes(3), AddressingModes(6), AddressingModes(3),
  AddressingModes(2), AddressingModes(2), AddressingModes(2), AddressingModes(2),
  AddressingModes(5), AddressingModes(7), AddressingModes(5), AddressingModes(7),
  AddressingModes(11), AddressingModes(11), AddressingModes(11), AddressingModes(11),
  AddressingModes(6), AddressingModes(5), AddressingModes(6), AddressingModes(5),
  AddressingModes(1), AddressingModes(1), AddressingModes(1), AddressingModes(1),
  AddressingModes(10), AddressingModes(9), AddressingModes(6), AddressingModes(9),
  AddressingModes(12), AddressingModes(12), AddressingModes(13), AddressingModes(13),
  AddressingModes(6), AddressingModes(3), AddressingModes(6), AddressingModes(3),
  AddressingModes(2), AddressingModes(2), AddressingModes(3), AddressingModes(3),
  AddressingModes(5), AddressingModes(7), AddressingModes(5), AddressingModes(7),
  AddressingModes(11), AddressingModes(11), AddressingModes(11), AddressingModes(11),
  AddressingModes(6), AddressingModes(5), AddressingModes(6), AddressingModes(5),
  AddressingModes(1), AddressingModes(1), AddressingModes(1), AddressingModes(1),
  AddressingModes(10), AddressingModes(9), AddressingModes(6), AddressingModes(9),
  AddressingModes(12), AddressingModes(12), AddressingModes(13), AddressingModes(13),
  AddressingModes(6), AddressingModes(3), AddressingModes(6), AddressingModes(3),
  AddressingModes(2), AddressingModes(2), AddressingModes(3), AddressingModes(3),
  AddressingModes(5), AddressingModes(7), AddressingModes(5), AddressingModes(7),
  AddressingModes(11), AddressingModes(11), AddressingModes(11), AddressingModes(11),
  AddressingModes(6), AddressingModes(5), AddressingModes(6), AddressingModes(5),
  AddressingModes(1), AddressingModes(1), AddressingModes(1), AddressingModes(1),
  AddressingModes(10), AddressingModes(9), AddressingModes(6), AddressingModes(9),
  AddressingModes(12), AddressingModes(12), AddressingModes(12), AddressingModes(12),
  AddressingModes(6), AddressingModes(3), AddressingModes(6), AddressingModes(3),
  AddressingModes(2), AddressingModes(2), AddressingModes(2), AddressingModes(2),
  AddressingModes(5), AddressingModes(7), AddressingModes(5), AddressingModes(7),
  AddressingModes(11), AddressingModes(11), AddressingModes(11), AddressingModes(11),
  AddressingModes(6), AddressingModes(5), AddressingModes(6), AddressingModes(5),
  AddressingModes(1), AddressingModes(1), AddressingModes(1), AddressingModes(1),
  AddressingModes(10), AddressingModes(9), AddressingModes(6), AddressingModes(9),
  AddressingModes(12), AddressingModes(12), AddressingModes(12), AddressingModes(12),
  AddressingModes(6), AddressingModes(3), AddressingModes(6), AddressingModes(3),
  AddressingModes(2), AddressingModes(2), AddressingModes(2), AddressingModes(2)
]

# InstructionSizes indicates the size of each instruction in bytes
const InstructionSizes = [
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x02, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x03, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x03, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x02, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x03, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x01, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x02, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x03, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x01, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x02, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x03, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x00, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x03, 0x01, 0x00, 0x00, 0x03, 0x00, 0x00,
  0x02, 0x02, 0x02, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x02, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x03, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x02, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x03, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x02, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00,
  0x02, 0x02, 0x00, 0x00, 0x02, 0x02, 0x02, 0x00, 0x01, 0x03, 0x01, 0x00, 0x03, 0x03, 0x03, 0x00
 ]

# InstructionCycles indicates the number of cycles used by each instruction,
# not including conditional cycles
const InstructionCycles = [
  0x07, 0x06, 0x02, 0x08, 0x03, 0x03, 0x05, 0x05, 0x03, 0x02, 0x02, 0x02, 0x04, 0x04, 0x06, 0x06,
  0x02, 0x05, 0x02, 0x08, 0x04, 0x04, 0x06, 0x06, 0x02, 0x04, 0x02, 0x07, 0x04, 0x04, 0x07, 0x07,
  0x06, 0x06, 0x02, 0x08, 0x03, 0x03, 0x05, 0x05, 0x04, 0x02, 0x02, 0x02, 0x04, 0x04, 0x06, 0x06,
  0x02, 0x05, 0x02, 0x08, 0x04, 0x04, 0x06, 0x06, 0x02, 0x04, 0x02, 0x07, 0x04, 0x04, 0x07, 0x07,
  0x06, 0x06, 0x02, 0x08, 0x03, 0x03, 0x05, 0x05, 0x03, 0x02, 0x02, 0x02, 0x03, 0x04, 0x06, 0x06,
  0x02, 0x05, 0x02, 0x08, 0x04, 0x04, 0x06, 0x06, 0x02, 0x04, 0x02, 0x07, 0x04, 0x04, 0x07, 0x07,
  0x06, 0x06, 0x02, 0x08, 0x03, 0x03, 0x05, 0x05, 0x04, 0x02, 0x02, 0x02, 0x05, 0x04, 0x06, 0x06,
  0x02, 0x05, 0x02, 0x08, 0x04, 0x04, 0x06, 0x06, 0x02, 0x04, 0x02, 0x07, 0x04, 0x04, 0x07, 0x07,
  0x02, 0x06, 0x02, 0x06, 0x03, 0x03, 0x03, 0x03, 0x02, 0x02, 0x02, 0x02, 0x04, 0x04, 0x04, 0x04,
  0x02, 0x06, 0x02, 0x06, 0x04, 0x04, 0x04, 0x04, 0x02, 0x05, 0x02, 0x05, 0x05, 0x05, 0x05, 0x05,
  0x02, 0x06, 0x02, 0x06, 0x03, 0x03, 0x03, 0x03, 0x02, 0x02, 0x02, 0x02, 0x04, 0x04, 0x04, 0x04,
  0x02, 0x05, 0x02, 0x05, 0x04, 0x04, 0x04, 0x04, 0x02, 0x04, 0x02, 0x04, 0x04, 0x04, 0x04, 0x04,
  0x02, 0x06, 0x02, 0x08, 0x03, 0x03, 0x05, 0x05, 0x02, 0x02, 0x02, 0x02, 0x04, 0x04, 0x06, 0x06,
  0x02, 0x05, 0x02, 0x08, 0x04, 0x04, 0x06, 0x06, 0x02, 0x04, 0x02, 0x07, 0x04, 0x04, 0x07, 0x07,
  0x02, 0x06, 0x02, 0x08, 0x03, 0x03, 0x05, 0x05, 0x02, 0x02, 0x02, 0x02, 0x04, 0x04, 0x06, 0x06,
  0x02, 0x05, 0x02, 0x08, 0x04, 0x04, 0x06, 0x06, 0x02, 0x04, 0x02, 0x07, 0x04, 0x04, 0x07, 0x07
]

# InstructionPageCycles indicates the number of cycles used by each
# instruction when a page is crossed
const InstructionPageCycles = [
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x01, 0x01, 0x01, 0x01, 0x01,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x01, 0x01, 0x00, 0x00
]

# InstructionNames indicates the name of each instruction
const InstructionNames = [
  "BRK", "ORA", "KIL", "SLO", "NOP", "ORA", "ASL", "SLO",
  "PHP", "ORA", "ASL", "ANC", "NOP", "ORA", "ASL", "SLO",
  "BPL", "ORA", "KIL", "SLO", "NOP", "ORA", "ASL", "SLO",
  "CLC", "ORA", "NOP", "SLO", "NOP", "ORA", "ASL", "SLO",
  "JSR", "AND", "KIL", "RLA", "BIT", "AND", "ROL", "RLA",
  "PLP", "AND", "ROL", "ANC", "BIT", "AND", "ROL", "RLA",
  "BMI", "AND", "KIL", "RLA", "NOP", "AND", "ROL", "RLA",
  "SEC", "AND", "NOP", "RLA", "NOP", "AND", "ROL", "RLA",
  "RTI", "EOR", "KIL", "SRE", "NOP", "EOR", "LSR", "SRE",
  "PHA", "EOR", "LSR", "ALR", "JMP", "EOR", "LSR", "SRE",
  "BVC", "EOR", "KIL", "SRE", "NOP", "EOR", "LSR", "SRE",
  "CLI", "EOR", "NOP", "SRE", "NOP", "EOR", "LSR", "SRE",
  "RTS", "ADC", "KIL", "RRA", "NOP", "ADC", "ROR", "RRA",
  "PLA", "ADC", "ROR", "ARR", "JMP", "ADC", "ROR", "RRA",
  "BVS", "ADC", "KIL", "RRA", "NOP", "ADC", "ROR", "RRA",
  "SEI", "ADC", "NOP", "RRA", "NOP", "ADC", "ROR", "RRA",
  "NOP", "STA", "NOP", "SAX", "STY", "STA", "STX", "SAX",
  "DEY", "NOP", "TXA", "XAA", "STY", "STA", "STX", "SAX",
  "BCC", "STA", "KIL", "AHX", "STY", "STA", "STX", "SAX",
  "TYA", "STA", "TXS", "TAS", "SHY", "STA", "SHX", "AHX",
  "LDY", "LDA", "LDX", "LAX", "LDY", "LDA", "LDX", "LAX",
  "TAY", "LDA", "TAX", "LAX", "LDY", "LDA", "LDX", "LAX",
  "BCS", "LDA", "KIL", "LAX", "LDY", "LDA", "LDX", "LAX",
  "CLV", "LDA", "TSX", "LAS", "LDY", "LDA", "LDX", "LAX",
  "CPY", "CMP", "NOP", "DCP", "CPY", "CMP", "DEC", "DCP",
  "INY", "CMP", "DEX", "AXS", "CPY", "CMP", "DEC", "DCP",
  "BNE", "CMP", "KIL", "DCP", "NOP", "CMP", "DEC", "DCP",
  "CLD", "CMP", "NOP", "DCP", "NOP", "CMP", "DEC", "DCP",
  "CPX", "SBC", "NOP", "ISC", "CPX", "SBC", "INC", "ISC",
  "INX", "SBC", "NOP", "SBC", "CPX", "SBC", "INC", "ISC",
  "BEQ", "SBC", "KIL", "ISC", "NOP", "SBC", "INC", "ISC",
  "SED", "SBC", "NOP", "ISC", "NOP", "SBC", "INC", "ISC"
]

