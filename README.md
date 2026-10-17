# Kyle Fiedler Dot COM

It follows the [thoughtbot styleguide](https://github.com/thoughtbot/guides)

About Jekyll
---------------
Jekyll is a static site generator built in Ruby. This makes it a great fit
for projects that may end up as a Ruby on Rails app.

Getting Started
---------------
Install dependencies
```
bundle install
```

Run the server and watch for changes in your files
```
jekyll serve -w
```

Photo walls
---------------
Split pages show a drifting photo wall. To add a set, export the graded photos
to a folder (originals stay out of the repo), then run (macOS only, uses `sips`)
```
script/wall-photos ~/path/to/photos <set>
```
and add `wall: <set>` to the page's front matter. Fill in alt text in
`_data/walls/<set>.yml`; re-runs keep it. Test the script with
```
ruby test/wall_photos_test.rb
```
