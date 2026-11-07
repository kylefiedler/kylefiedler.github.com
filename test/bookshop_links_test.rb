# Runs script/bookshop-links against a local stand-in for Open Library, in a
# scratch copy of the repo layout.
#
#   ruby test/bookshop_links_test.rb

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "socket"
require "tmpdir"
require "uri"

class BookshopLinksTest < Minitest::Test
  SCRIPTS = %w[bookshop-links open_library.rb].map { |name| File.expand_path("../script/#{name}", __dir__) }.freeze

  BOOKS = [
    ["Why We Sleep", "Matthew Walker"],
    ["The Confident Mind", "Nate Zinsser"],
    ["Scythe (Arc of a Scythe, #1)", "Shusterman, Neal"],
    ["Salt, Fat, Acid, Heat", "Samin Nosrat"],
    ["Bread &amp; Wine", "Shauna Niequist"]
  ].freeze

  # The stand-in's search results (title, ISBNs) by searched title and author.
  # The Confident Mind only turns up a different book, Scythe is only found
  # without its series suffix and with the author's first name dropped, and
  # Salt, Fat, Acid, Heat only has an ISBN-10 and a Spanish edition's ISBN-13.
  SEARCH = {
    ["Why We Sleep", "Matthew Walker"] => [["Why We Sleep", %w[1501144316 9788412064551 9781501144318 9781501144325]]],
    ["The Confident Mind", "Nate Zinsser"] => [["The Confident Mind Workbook", %w[9780063051287]]],
    ["Scythe", "Shusterman"] => [["Scythe", %w[9781442472433]]],
    ["Salt, Fat, Acid, Heat", "Samin Nosrat"] => [["Salt, Fat, Acid, Heat", %w[1476753830 9788416895113]]],
    ["Bread & Wine", "Shauna Niequist"] => [["Bread & Wine", %w[9780310328179]]],
    ["Ancillary Justice", "Ann Leckie"] => [["Ancillary Justice", %w[9780316246620]]]
  }.freeze

  def setup
    @root = Dir.mktmpdir
    FileUtils.mkdir_p([File.join(@root, "script"), File.join(@root, "lists")])
    FileUtils.cp(SCRIPTS, File.join(@root, "script"))
    write_books(BOOKS)
    @requests = []
    @server = TCPServer.new("127.0.0.1", 0)
    @thread = Thread.new { loop { serve(@server.accept) } }
  end

  def teardown
    @thread.kill
    @server.close
    FileUtils.rm_rf(@root)
  end

  def test_links_books_to_their_isbn_and_misses_to_a_search
    output = run_script!

    assert_equal [
      %(<h4><a href="{{ bookshop }}/9781501144318">Why We Sleep</a></h4>),
      %(<h4><a href="{{ bookshop_search }}The+Confident+Mind+Nate+Zinsser">The Confident Mind</a></h4>),
      %(<h4><a href="{{ bookshop }}/9781442472433">Scythe (Arc of a Scythe, #1)</a></h4>),
      %(<h4><a href="{{ bookshop_search }}Salt%2C+Fat%2C+Acid%2C+Heat+Samin+Nosrat">Salt, Fat, Acid, Heat</a></h4>),
      %(<h4><a href="{{ bookshop }}/9780310328179">Bread &amp; Wine</a></h4>)
    ], titles
    assert_includes output, "search link: The Confident Mind by Nate Zinsser"
    assert_includes output, "search link: Salt, Fat, Acid, Heat by Samin Nosrat"
    assert_includes output, "3 linked to a book, 2 to a search, 0 already linked"
  end

  def test_changes_nothing_outside_the_titles
    before = File.read(page)

    run_script!

    strip = ->(html) { html.gsub(%r{<h4>.*?</h4>}, "") }
    assert_equal strip[before], strip[File.read(page)]
  end

  def test_rerun_changes_nothing_and_looks_nothing_up
    run_script!
    linked = File.read(page)
    @requests.clear

    output = run_script!

    assert_equal linked, File.read(page)
    assert_empty @requests
    assert_includes output, "0 linked to a book, 0 to a search, 5 already linked"
  end

  def test_leaves_edited_links_alone_and_links_new_books
    run_script!
    edited = File.read(page).sub("9781501144318", "9781501144325")
    File.write(page, edited.sub("<ul>\n", "<ul>\n#{item('Ancillary Justice', 'Ann Leckie')}"))
    @requests.clear

    run_script!

    assert_equal %(<h4><a href="{{ bookshop }}/9780316246620">Ancillary Justice</a></h4>), titles.first
    assert_equal %(<h4><a href="{{ bookshop }}/9781501144325">Why We Sleep</a></h4>), titles[1]
    assert(@requests.all? { |path| path.include?("Ancillary") }, @requests.inspect)
  end

  def test_links_a_title_heading_with_a_class
    File.write(page, File.read(page)
      .sub("<h4>Why We Sleep</h4>", %(<h4 class="mb--none">Why We Sleep</h4>)))

    run_script!

    assert_includes File.read(page), %(<h4 class="mb--none"><a href="{{ bookshop }}/9781501144318">Why We Sleep</a></h4>)
  end

  def test_an_interrupted_run_keeps_the_links_it_made
    @failing = "Scythe"

    _output, status = Open3.capture2e(env, "ruby", script)

    refute status.success?
    linked = titles.select { |title| title.include?("<a href") }
    assert_equal ["Why We Sleep", "The Confident Mind"], linked.map { |title| title[/">(.*)<\/a>/, 1] }
    @failing = nil
    @requests.clear

    run_script!

    assert_equal 5, titles.count { |title| title.include?("<a href") }
    refute(@requests.any? { |path| path.include?("Sleep") || path.include?("Confident") }, @requests.inspect)
  end

  private

  def page = File.join(@root, "lists", "books.html")
  def script = File.join(@root, "script", "bookshop-links")
  def titles = File.read(page).scan(%r{<h4[^>]*>.*?</h4>})

  def env = { "OPEN_LIBRARY_URL" => "http://127.0.0.1:#{@server.addr[1]}", "BOOK_COVERS_DELAY" => "0" }

  def run_script!
    output, status = Open3.capture2e(env, "ruby", script)
    assert status.success?, output
    output
  end

  def item(title, author) = "      <li>\n        <h4>#{title}</h4>\n        <p>#{author}</p>\n      </li>\n"

  def write_books(books)
    File.write(page, <<~HTML)
      <ol class="books">
        <li>
          <h2 class="books__year" id="y2026">2026</h2>
          <ul>
      #{books.map { |title, author| item(title, author) }.join}    </ul>
        </li>
      </ol>
    HTML
  end

  def serve(client)
    path = client.gets.split[1]
    nil until client.gets == "\r\n"
    @requests << path
    uri = URI(path)
    status, body = if @failing && uri.query.to_s.include?(@failing)
      ["500 Internal Server Error", ""]
    elsif uri.path == "/search.json"
      query = URI.decode_www_form(uri.query).to_h
      docs = SEARCH.fetch(query.values_at("title", "author"), []).map { |title, isbns| { title: title, isbn: isbns } }
      ["200 OK", JSON.generate(docs: docs)]
    else
      ["404 Not Found", ""]
    end
    client.write("HTTP/1.1 #{status}\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\n" \
      "Connection: close\r\n\r\n", body)
  ensure
    client.close
  end
end
