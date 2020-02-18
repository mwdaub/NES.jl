const Palette = Matrix{UInt8}

Pixel(x::UInt32) = [UInt8((x & 0xff0000) >> 16), UInt8((x & 0xff00) >> 8), UInt8(x & 0xff)]

const DefaultPalette = hcat(
  Pixel(0x666666), Pixel(0x002A88), Pixel(0x1412A7), Pixel(0x3B00A4),
  Pixel(0x5C007E), Pixel(0x6E0040), Pixel(0x6C0600), Pixel(0x561D00),
  Pixel(0x333500), Pixel(0x0B4800), Pixel(0x005200), Pixel(0x004F08),
  Pixel(0x00404D), Pixel(0x000000), Pixel(0x000000), Pixel(0x000000),
  Pixel(0xADADAD), Pixel(0x155FD9), Pixel(0x4240FF), Pixel(0x7527FE),
  Pixel(0xA01ACC), Pixel(0xB71E7B), Pixel(0xB53120), Pixel(0x994E00),
  Pixel(0x6B6D00), Pixel(0x388700), Pixel(0x0C9300), Pixel(0x008F32),
  Pixel(0x007C8D), Pixel(0x000000), Pixel(0x000000), Pixel(0x000000),
  Pixel(0xFFFEFF), Pixel(0x64B0FF), Pixel(0x9290FF), Pixel(0xC676FF),
  Pixel(0xF36AFF), Pixel(0xFE6ECC), Pixel(0xFE8170), Pixel(0xEA9E22),
  Pixel(0xBCBE00), Pixel(0x88D800), Pixel(0x5CE430), Pixel(0x45E082),
  Pixel(0x48CDDE), Pixel(0x4F4F4F), Pixel(0x000000), Pixel(0x000000),
  Pixel(0xFFFEFF), Pixel(0xC0DFFF), Pixel(0xD3D2FF), Pixel(0xE8C8FF),
  Pixel(0xFBC2FF), Pixel(0xFEC4EA), Pixel(0xFECCC5), Pixel(0xF7D8A5),
  Pixel(0xE4E594), Pixel(0xCFEF96), Pixel(0xBDF4AB), Pixel(0xB3F3CC),
  Pixel(0xB5EBF2), Pixel(0xB8B8B8), Pixel(0x000000), Pixel(0x000000)
)

const width = 256
const height = 240
const numchannels = 3
const numcolors = 64

# Frame containing pixel IDs.
const Frame = Matrix{UInt8}
# Rendered frame containing pixel RGB values.
const Screen = Array{UInt8, 3}

Frame() = zeros(UInt8, width, height)
Screen() = zeros(UInt8, numchannels, width, height)

# Render the frame as a screen with RGB pixel values using the given palette.
function render!(f::Frame, s::Screen, p::Palette)
  @assert size(f) == (width, height)
  @assert size(s) == (numchannels, width, height)
  @assert size(p) == (numchannels, numcolors)
  for i = 1:height, j = 1:width
    index = f[j, i] + 1
    s[1, j, i] = p[1, index]
    s[2, j, i] = p[2, index]
    s[3, j, i] = p[3, index]
  end
end

render!(f::Frame, s::Screen) = render!(f, s, DefaultPalette)

function Screen(f::Frame, p::Palette)
  s = Screen()
  render!(f, s, p)
  s
end

Screen(f::Frame) = Screen(f, DefaultPalette)
