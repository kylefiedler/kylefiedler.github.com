# Runs script/book-covers against a local stand-in for Open Library, in a
# scratch copy of the repo layout. Needs macOS (sips).
#
#   ruby test/book_covers_test.rb

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "socket"
require "tmpdir"
require "uri"
require "yaml"
require_relative "jpeg_fixture"

class BookCoversTest < Minitest::Test
  include JpegFixture

  SCRIPTS = %w[book-covers wall-photos].map { |name| File.expand_path("../script/#{name}", __dir__) }.freeze

  # Newest first, as lists/books.html lists them.
  BOOKS = [
    ["Why We Sleep", "Matthew Walker"],
    ["The Confident Mind", "Nate Zinsser"],
    ["Scythe (Arc of a Scythe, #1)", "Shusterman, Neal"],
    ["Kitchen Confidential", "Anthony Bourdain"],
    ["The Arm", "Jeff Passan"]
  ].freeze

  # The stand-in's search results (title, cover id) by searched title and
  # author. The Confident Mind only turns up a different book, Scythe is only
  # found without its series suffix and with the author's first name dropped,
  # and the first covers for Why We Sleep and Kitchen Confidential are a
  # thumbnail and a banner. Why We Sleep's usable cover is nearly square.
  SEARCH = {
    ["Why We Sleep", "Matthew Walker"] => [["Why We Sleep", 8], ["Why We Sleep", 1]],
    ["The Confident Mind", "Nate Zinsser"] => [["The Confident Mind Workbook", 6]],
    ["Scythe", "Shusterman"] => [["Scythe", 2]],
    ["Kitchen Confidential", "Anthony Bourdain"] => [["Kitchen confidential", 7], ["Kitchen Confidential", 3]],
    ["The Arm", "Jeff Passan"] => [["The Arm", 4]],
    ["Ancillary Justice", "Ann Leckie"] => [["Ancillary Justice", 5]]
  }.freeze

  def setup
    @root = Dir.mktmpdir
    FileUtils.mkdir_p([File.join(@root, "script"), File.join(@root, "lists")])
    FileUtils.cp(SCRIPTS, File.join(@root, "script"))
    write_books(BOOKS)
    # Cover id => [width, height]; every other id is 300×450.
    @sizes = Hash.new([300, 450]).merge(1 => [400, 320], 7 => [500, 74], 8 => [160, 240])
    @covers = [@sizes.default, *@sizes.values].to_h do |size|
      path = File.join(@root, "cover-#{size.join('x')}.jpg")
      write_jpeg(path, *size)
      [size, path]
    end
    # Cover files that fail before they load, as Open Library's sometimes do:
    # a status line, or :drop to close the connection without a response.
    @outages = {
      "/files/1.jpg" => ["429 Too Many Requests"],
      "/files/2.jpg" => ["502 Bad Gateway", "503 Service Unavailable"],
      "/files/3.jpg" => %i[drop drop]
    }
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new { loop { serve(@server.accept) } }
  end

  def teardown
    @thread.kill
    @server.close
    FileUtils.rm_rf(@root)
  end

  def test_takes_the_newest_books_with_covers_and_reports_misses
    output = run_script!("3")

    assert_includes output, "skipped The Confident Mind by Nate Zinsser: no usable Open Library cover " \
      "(commit one as _book-covers/the-confident-mind-nate-zinsser.jpg)"
    assert_equal %w[why-we-sleep-matthew-walker.jpg kitchen-confidential-anthony-bourdain.jpg
      scythe-arc-of-a-scythe-1-shusterman-neal.jpg].sort, Dir.children(out_dir).sort
    assert_equal [
      { "src" => src("why-we-sleep-matthew-walker"), "width" => 400, "height" => 320,
        "alt" => "Cover of Why We Sleep by Matthew Walker" },
      { "src" => src("scythe-arc-of-a-scythe-1-shusterman-neal"), "width" => 300, "height" => 450,
        "alt" => "Cover of Scythe (Arc of a Scythe, #1) by Shusterman, Neal" },
      { "src" => src("kitchen-confidential-anthony-bourdain"), "width" => 300, "height" => 450,
        "alt" => "Cover of Kitchen Confidential by Anthony Bourdain" }
    ], data
    assert_equal 3, Dir.children(File.join(@root, ".cache", "book-covers")).size
  end

  def test_rerun_downloads_nothing_and_keeps_edited_alt_text
    run_script!("3")
    edited = data
    edited[1]["alt"] = "Scythe, with a blade on the cover"
    File.write(File.join(@root, "_data", "walls", "books.yml"), edited.to_yaml)
    mtimes = Dir.children(out_dir).to_h { |name| [name, File.mtime(File.join(out_dir, name))] }
    @requests.clear

    run_script!("3")

    assert @requests.all? { |path| path.start_with?("/search.json") && path.include?("Confident") }, @requests.inspect
    assert_equal(mtimes, Dir.children(out_dir).to_h { |name| [name, File.mtime(File.join(out_dir, name))] })
    assert_equal edited, data
  end

  def test_a_newer_book_pushes_the_oldest_cover_out
    run_script!("3")
    write_books([["Ancillary Justice", "Ann Leckie"], *BOOKS])

    run_script!("3")

    srcs = %w[ancillary-justice-ann-leckie why-we-sleep-matthew-walker scythe-arc-of-a-scythe-1-shusterman-neal]
    assert_equal srcs.map { |slug| src(slug) }, data.map { |cover| cover["src"] }
    refute File.exist?(File.join(out_dir, "kitchen-confidential-anthony-bourdain.jpg"))
  end

  def test_committed_covers_win_over_the_cache_and_the_lookup
    run_script!("3")
    overrides = File.join(@root, "_book-covers")
    FileUtils.mkdir_p(overrides)
    write_jpeg(File.join(overrides, "why-we-sleep-matthew-walker.jpg"), 350, 500)
    write_jpeg(File.join(overrides, "the-confident-mind-nate-zinsser.jpg"), 400, 600)
    # As in a fresh checkout: the committed covers, but no cache.
    FileUtils.rm_rf(File.join(@root, ".cache"))
    @requests.clear

    run_script!("3")

    assert @requests.all? { |path| path.include?("Scythe") || path.match?(%r{/2(-L)?\.jpg}) }, @requests.inspect
    assert_equal [src("why-we-sleep-matthew-walker"), src("the-confident-mind-nate-zinsser"),
      src("scythe-arc-of-a-scythe-1-shusterman-neal")], data.map { |cover| cover["src"] }
    assert_equal [[350, 500], [400, 600]], data.first(2).map { |cover| cover.values_at("width", "height") }
  end

  def test_rejects_a_bad_count
    %w[0 -2 ten].each do |count|
      _output, status = Open3.capture2e(env, "ruby", script, count)
      refute status.success?, count
    end
  end

  private

  def script = File.join(@root, "script", "book-covers")
  def out_dir = File.join(@root, "images", "wall", "books")
  def data = YAML.safe_load(File.read(File.join(@root, "_data", "walls", "books.yml")))
  def src(slug) = "/images/wall/books/#{slug}.jpg"

  def env
    url = "http://127.0.0.1:#{@server.addr[1]}"
    { "OPEN_LIBRARY_URL" => url, "OPEN_LIBRARY_COVERS_URL" => url, "BOOK_COVERS_DELAY" => "0" }
  end

  def run_script!(*args)
    output, status = Open3.capture2e(env, "ruby", script, *args)
    assert status.success?, output
    output
  end

  def write_books(books)
    items = books.map { |title, author| "      <li>\n        <h4>#{title}</h4>\n        <p>#{author}</p>\n      </li>\n" }
    File.write(File.join(@root, "lists", "books.html"), <<~HTML)
      <ol class="books">
        <li>
          <h3 class="title--secondary">2026</h3>
          <ul>
      #{items.join}    </ul>
        </li>
      </ol>
    HTML
  end

  def serve(client)
    path = client.gets.split[1]
    nil until client.gets == "\r\n"
    @requests << path
    uri = URI(path)
    failure = @outages.fetch(uri.path, []).shift
    return if failure == :drop

    status, headers, body = failure ? [failure, {}, ""] : respond(uri)
    headers = headers.merge("Content-Length" => body.bytesize, "Connection" => "close")
    client.write("HTTP/1.1 #{status}\r\n#{headers.map { |name, value| "#{name}: #{value}\r\n" }.join}\r\n", body)
  ensure
    client.close
  end

  # Cover images redirect to their file, as covers.openlibrary.org does.
  def respond(uri)
    case uri.path
    when "/search.json"
      query = URI.decode_www_form(uri.query).to_h
      docs = SEARCH.fetch(query.values_at("title", "author"), []).map { |title, id| { title: title, cover_i: id } }
      ["200 OK", { "Content-Type" => "application/json" }, JSON.generate(docs: docs)]
    when %r{\A/b/id/(\d+)-L\.jpg\z} then ["302 Found", { "Location" => "/files/#{$1}.jpg" }, ""]
    when %r{\A/files/(\d+)\.jpg\z} then ["200 OK", { "Content-Type" => "image/jpeg" }, File.binread(@covers[@sizes[$1.to_i]])]
    else ["404 Not Found", {}, ""]
    end
  end
end
