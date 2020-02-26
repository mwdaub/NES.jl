using Test, ColorTypes, NES

@testset "Load Cartridge Test" begin
  c = loadgame("test/Super_Tilt_Bro.nes")
  actual = screen(c)
  expected = open("test/blank_screen.bin") do f
    reinterpret(RGB24, reinterpret(UInt32, reshape(read(f), 4 * 256, 240)))
  end
  @test actual == expected
end

@testset "Single CPU Instruction Test" begin
  c = loadgame("test/Super_Tilt_Bro.nes")
  step!(c)
  @test c.cpu.cycles == 2
  @test c.cpu.PC == 0x8036
  @test c.cpu.SP == 0xFD
  @test c.cpu.A == 0x00
  @test c.cpu.X == 0x00
  @test c.cpu.Y == 0x00
  @test c.cpu.C == 0x00
  @test c.cpu.Z == 0x00
  @test c.cpu.I == 0x01
  @test c.cpu.D == 0x00
  @test c.cpu.B == 0x00
  @test c.cpu.U == 0x01
  @test c.cpu.V == 0x00
  @test c.cpu.N == 0x00
  @test Int(c.cpu.interrupt) == 0
  @test c.cpu.stall == 0
end

@testset "Single CPU Frame Tests" begin
  c = loadgame("test/Super_Tilt_Bro.nes")
  stepframe!(c)
  @test c.cpu.cycles == 0x0000000000000955
  @test c.cpu.PC == 0x8050
  @test c.cpu.SP == 0xFF
  @test c.cpu.A == 0xFE
  @test c.cpu.X == 0x31
  @test c.cpu.Y == 0x00
  @test c.cpu.C == 0x00
  @test c.cpu.Z == 0x00
  @test c.cpu.I == 0x01
  @test c.cpu.D == 0x00
  @test c.cpu.B == 0x00
  @test c.cpu.U == 0x01
  @test c.cpu.V == 0x00
  @test c.cpu.N == 0x00
  @test Int(c.cpu.interrupt) == 0
  @test c.cpu.stall == 0
end

@testset "Screen Rendering Tests" begin
  c = loadgame("test/Super_Tilt_Bro.nes")
  stepframes!(c, 120)
  actual = screen(c)
  expected = open("test/screen.bin") do f
    reinterpret(RGB24, reinterpret(UInt32, reshape(read(f), 4 * 256, 240)))
  end
  @test actual == expected
end

@testset "Controller Input Tests" begin
  c = loadgame("test/Super_Tilt_Bro.nes")
  inputs = [(0x00, 0x60), (0x08, 0x05), (0x00, 0x60), (0x08, 0x05),
            (0x00, 0x60), (0x08, 0x05), (0x00, 0x60), (0x08, 0x05),
            (0x00, 0x50), (0x80, 0x15), (0x81, 0x05)]
  stepframes!(c, inputs)
  actual = screen(c)
  expected = open("test/inputs.bin") do f
    reinterpret(RGB24, reinterpret(UInt32, reshape(read(f), 4 * 256, 240)))
  end
  @test actual == expected
end
