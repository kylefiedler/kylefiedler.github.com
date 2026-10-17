# Runs script/wall-photos against generated photos in a scratch copy of the
# repo layout. Needs macOS (sips).
#
#   ruby test/wall_photos_test.rb

require "fileutils"
require "minitest/autorun"
require "open3"
require "tmpdir"
require "yaml"
require_relative "jpeg_fixture"

class WallPhotosTest < Minitest::Test
  include JpegFixture

  SCRIPT = File.expand_path("../script/wall-photos", __dir__)

  # name => [width, height] of the source photo
  PHOTOS = {
    "Beach Day.JPG" => [1600, 1200],
    "dog.jpg" => [1200, 1600],
    "garden.jpeg" => [1000, 1000],
    "ridge.jpg" => [2400, 900],
    "tiny.jpg" => [640, 480]
  }.freeze

  def setup
    @root = Dir.mktmpdir
    @source = File.join(@root, "originals")
    FileUtils.mkdir_p([File.join(@root, "script"), @source])
    FileUtils.cp(SCRIPT, File.join(@root, "script"))
    PHOTOS.each { |name, (width, height)| write_jpeg(File.join(@source, name), width, height) }
  end

  def teardown
    FileUtils.rm_rf(@root)
  end

  def test_writes_fixed_width_jpegs_and_matching_data
    run_script!

    expected = {
      "beach-day.jpg" => [800, 600],
      "dog.jpg" => [800, 1066],
      "garden.jpg" => [800, 800],
      "ridge.jpg" => [800, 300],
      "tiny.jpg" => [640, 480]
    }
    assert_equal expected.keys, Dir.children(out_dir).sort
    expected.each { |name, size| assert_equal size, dimensions(File.join(out_dir, name)), name }

    assert_equal(expected.map do |name, (width, height)|
      { "src" => "/images/wall/trip/#{name}", "width" => width, "height" => height, "alt" => "" }
    end, data)
  end

  def test_rerun_keeps_alt_text_order_and_untouched_files
    run_script!
    edited = data.reverse
    edited.first["alt"] = "A small photo"
    File.write(data_file, edited.to_yaml)
    mtimes = Dir.children(out_dir).to_h { |name| [name, File.mtime(File.join(out_dir, name))] }

    run_script!

    assert_equal edited, data
    assert_equal(mtimes, Dir.children(out_dir).to_h { |name| [name, File.mtime(File.join(out_dir, name))] })
  end

  def test_rerun_adds_new_photos_last_and_drops_removed_ones
    run_script!
    File.delete(File.join(@source, "dog.jpg"))
    write_jpeg(File.join(@source, "aardvark.jpg"), 900, 600)

    run_script!

    refute File.exist?(File.join(out_dir, "dog.jpg"))
    assert_equal %w[beach-day garden ridge tiny aardvark].map { |name| "/images/wall/trip/#{name}.jpg" },
      data.map { |photo| photo["src"] }
  end

  def test_alts_file_sets_order_and_alt_text
    run_script!
    alts = File.join(@root, "alts.yml")
    File.write(alts, [
      { "src" => "/images/wall/trip/tiny.jpg", "alt" => "A small photo" },
      { "src" => "/images/wall/trip/dog.jpg", "alt" => "A dog" }
    ].to_yaml)

    run_script!("--alts", alts)

    assert_equal %w[tiny dog beach-day garden ridge].map { |name| "/images/wall/trip/#{name}.jpg" },
      data.map { |photo| photo["src"] }
    assert_equal ["A small photo", "A dog", "", "", ""], data.map { |photo| photo["alt"] }
  end

  def test_rejects_reserved_set_names
    %w[placeholder static].each do |set|
      _output, status = Open3.capture2e("ruby", script, @source, set)
      refute status.success?, set
    end
    refute Dir.exist?(File.join(@root, "images"))
  end

  private

  def script = File.join(@root, "script", "wall-photos")
  def out_dir = File.join(@root, "images", "wall", "trip")
  def data_file = File.join(@root, "_data", "walls", "trip.yml")
  def data = YAML.safe_load(File.read(data_file))

  def run_script!(*options)
    output, status = Open3.capture2e("ruby", script, *options, @source, "trip")
    assert status.success?, output
  end
end
