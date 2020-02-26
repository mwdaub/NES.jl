using ColorTypes

const Palette = Vector{RGB24}

rgb24(x::UInt32) = RGB24(((x >> 16) & 0xFF) / 255.0, ((x >> 8) & 0xFF) / 255.0, (x & 0xFF) / 255.0)

const DefaultPalette = vcat(
  rgb24(0x666666), rgb24(0x002A88), rgb24(0x1412A7), rgb24(0x3B00A4),
  rgb24(0x5C007E), rgb24(0x6E0040), rgb24(0x6C0600), rgb24(0x561D00),
  rgb24(0x333500), rgb24(0x0B4800), rgb24(0x005200), rgb24(0x004F08),
  rgb24(0x00404D), rgb24(0x000000), rgb24(0x000000), rgb24(0x000000),
  rgb24(0xADADAD), rgb24(0x155FD9), rgb24(0x4240FF), rgb24(0x7527FE),
  rgb24(0xA01ACC), rgb24(0xB71E7B), rgb24(0xB53120), rgb24(0x994E00),
  rgb24(0x6B6D00), rgb24(0x388700), rgb24(0x0C9300), rgb24(0x008F32),
  rgb24(0x007C8D), rgb24(0x000000), rgb24(0x000000), rgb24(0x000000),
  rgb24(0xFFFEFF), rgb24(0x64B0FF), rgb24(0x9290FF), rgb24(0xC676FF),
  rgb24(0xF36AFF), rgb24(0xFE6ECC), rgb24(0xFE8170), rgb24(0xEA9E22),
  rgb24(0xBCBE00), rgb24(0x88D800), rgb24(0x5CE430), rgb24(0x45E082),
  rgb24(0x48CDDE), rgb24(0x4F4F4F), rgb24(0x000000), rgb24(0x000000),
  rgb24(0xFFFEFF), rgb24(0xC0DFFF), rgb24(0xD3D2FF), rgb24(0xE8C8FF),
  rgb24(0xFBC2FF), rgb24(0xFEC4EA), rgb24(0xFECCC5), rgb24(0xF7D8A5),
  rgb24(0xE4E594), rgb24(0xCFEF96), rgb24(0xBDF4AB), rgb24(0xB3F3CC),
  rgb24(0xB5EBF2), rgb24(0xB8B8B8), rgb24(0x000000), rgb24(0x000000)
)

const width = 256
const height = 240
const numcolors = 64

# Frame containing pixel IDs.
const Frame = Matrix{UInt8}
# Rendered frame containing pixel RGB values.
const Screen = Matrix{RGB24}

Frame() = zeros(UInt8, width, height)
Screen() = fill(RGB24(0x00), (width, height))

# Render the frame as a screen with RGB pixel values using the given palette.
function render!(f::Frame, s::Screen, p::Palette)
  @assert size(f) == (width, height)
  @assert size(s) == (width, height)
  @assert size(p) == (numcolors,)
  for i = 1:height, j = 1:width
    index = f[j, i] + 1
    s[j, i] = p[index]
  end
end

render!(f::Frame, s::Screen) = render!(f, s, DefaultPalette)

function Screen(f::Frame, p::Palette)
  s = Screen()
  render!(f, s, p)
  s
end

Screen(f::Frame) = Screen(f, DefaultPalette)
