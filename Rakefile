desc 'Create new post. Args: title'

task :post do
  require 'rubygems'

  STDOUT.puts "Title?"
  title = STDIN.gets.strip

  TARGET_DIR = "_posts"

  filename = "#{Time.new.strftime('%Y-%m-%d')}-#{title}.markdown"
  path = File.join(TARGET_DIR, filename)
  post = <<-HTML
---
layout: post
title: "TITLE"
date: DATE
---

HTML
  post.gsub!('TITLE', title).gsub!('DATE', Time.new.to_s)
  File.open(path, 'w') do |file|
    file.puts post
  end
  puts "#{title} generated in #{path}"
  system "mvim #{path}"
end
