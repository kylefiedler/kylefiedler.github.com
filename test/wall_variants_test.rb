# Checks that every wall photo has the smaller copies wall-tile.html lists in
# its srcset. A missing copy renders as a broken tile, not a fallback.
#
#   ruby test/wall_variants_test.rb

require "minitest/autorun"
require "yaml"

class WallVariantsTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def test_every_photo_has_its_smaller_copies
    missing = Dir.glob(File.join(ROOT, "_data", "walls", "*.yml")).flat_map do |file|
      (YAML.safe_load(File.read(file)) || []).select { |photo| photo["src"] }.flat_map do |photo|
        dir, name = File.split(photo["src"])
        [400, 600].select { |size| photo["width"] > size }.map { |size| File.join(dir, size.to_s, name) }
      end
    end.reject { |path| File.exist?(File.join(ROOT, path)) }
    assert_empty missing
  end
end
