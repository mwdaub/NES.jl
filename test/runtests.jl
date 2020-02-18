using Test, NES

@testset "Load Cartridge Test" begin
  c = loadgame("test/Super_Tilt_Bro.nes")
  actual = screen(c)
  expected = open("test/blank_screen.bin") do f
    reshape(read(f), 3, 256, 240)
  end
  @test actual == expected
end
