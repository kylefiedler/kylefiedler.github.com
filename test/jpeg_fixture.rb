# Generated JPEGs for the script tests. Needs macOS (sips).

require "open3"

module JpegFixture
  def dimensions(path)
    output, = Open3.capture2e("sips", "-g", "pixelWidth", "-g", "pixelHeight", path)
    output.scan(/pixel(?:Width|Height): (\d+)/).flatten.map(&:to_i)
  end

  # sips can't draw, so write a flat 24-bit BMP and convert it.
  def write_jpeg(path, width, height)
    row = ("\x60\x90\xc0".b * width).ljust((width * 3 + 3) / 4 * 4, "\0")
    pixels = row * height
    header = ["BM", 54 + pixels.bytesize, 0, 0, 54].pack("a2Vv2V") +
      [40, width, height, 1, 24, 0, pixels.bytesize, 2835, 2835, 0, 0].pack("Vl<l<v2V6")
    bmp = "#{path}.bmp"
    File.binwrite(bmp, header + pixels)
    _output, status = Open3.capture2e("sips", "-s", "format", "jpeg", bmp, "--out", path)
    assert status.success?
    File.delete(bmp)
  end
end
