# Reading lists/books.html and searching Open Library, shared by
# script/book-covers and script/bookshop-links.

require "cgi"
require "json"
require "net/http"
require "uri"

module OpenLibrary
  SEARCH_URL = ENV.fetch("OPEN_LIBRARY_URL", "https://openlibrary.org")
  # Open Library asks for no more than about one request a second.
  DELAY = Float(ENV.fetch("BOOK_COVERS_DELAY", 1))
  # A book on the Books page: its title and author headings.
  ENTRY = %r{<h4[^>]*>(?<title>.*?)</h4>(?<space>\s*)<p>(?<author>.*?)</p>}m

  Book = Struct.new(:title, :author) do
    def self.from_html(title, author)
      new(*[title, author].map { |text| CGI.unescapeHTML(text.gsub(/<[^>]+>/, "")).strip })
    end

    def slug = "#{title} #{author}".downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")
    def to_s = "#{title} by #{author}"
  end

  module_function

  def books(html) = html.scan(ENTRY).map { |title, _space, author| Book.from_html(title, author) }

  def throttle
    sleep([@last_request.to_f + DELAY - Process.clock_gettime(Process::CLOCK_MONOTONIC), 0].max)
    @last_request = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Follows redirects, and retries what Open Library's servers sometimes do:
  # drop the connection, fail with a 5xx, or rate-limit with a 429.
  def get(url)
    redirects = retries = 0
    loop do
      throttle
      begin
        response = Net::HTTP.get_response(URI(url), { "User-Agent" => "kylefiedler.com script/#{File.basename($PROGRAM_NAME)}" })
      rescue IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => error
        failure = "failed: #{error.message}"
      end
      case response
      when Net::HTTPRedirection
        abort "too many redirects from #{url}" if (redirects += 1) > 5
        url = URI.join(url, response["location"]).to_s
        next
      when Net::HTTPSuccess, Net::HTTPNotFound then return response
      when Net::HTTPServerError, Net::HTTPTooManyRequests then failure = "returned #{response.code}"
      when Net::HTTPResponse then abort "#{url} returned #{response.code}"
      end
      abort "#{url} #{failure}" if (retries += 1) > 2
      sleep(DELAY * 5)
    end
  end

  # Series suffixes like "(The Poppy War, #1)" and subtitles stop title searches
  # from matching, and author search wants one name, not "Greger, M.D." or a
  # list. Strictest query first; title and author always both apply, so a miss
  # is skipped rather than matched to some other book with the same title.
  def queries(book)
    title = book.title.sub(/\s*\([^)]*#[^)]*\)\z/, "")
    titles = [title, title.split(":").first.strip].uniq
    authors = [book.author, book.author.split(",").first.strip].uniq
    titles.product(authors)
  end

  def comparable(title) = title.to_s.downcase.gsub(/[^a-z0-9]/, "")

  # Results with the searched title, in search order, for each of the book's
  # queries in turn. Lazy, so a caller that stops early skips the looser
  # queries. `fields` names the Open Library fields each result carries.
  def search(book, fields)
    queries(book).lazy.flat_map do |title, author|
      query = URI.encode_www_form(title: title, author: author, limit: 5, fields: fields)
      response = get("#{SEARCH_URL}/search.json?#{query}")
      next [] unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)["docs"].select { |doc| comparable(doc["title"]) == comparable(title) }
    end
  end
end
