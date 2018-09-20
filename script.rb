#!/usr/bin/env ruby

require "open-uri"
require "nokogiri"
require "addressable/uri"

module WikiBookMaker
  @sources_path = "sources"
  @results_path = "results"

  def self.compile_all
    Dir.each_child(@sources_path) do |file_name|
      compile(File.join(@sources_path, file_name))
    end
  end

  def self.compile(file_path)
    pages = []

    File.open(file_path).read.split("\n").each do |wiki_page_url|
      pages << clean_page(fetch(wiki_page_url))
    end

    style = create_style

    save(pages, style, file_path)
  end

  def self.create_style
    %{
      <style>
        .thumbinner {
          text-align: center;
        }
        table {
          width: 100%;
          margin: 1em 0;
          border: 1px solid #a2a9b1;
          border-collapse: collapse;
        }
        th {
          background-color: #eaecf0;
          text-align: center;
          border: 1px solid #a2a9b1;
          padding: 0.2em 0.4em;
        }
        td {
          border: 1px solid #a2a9b1;
          padding: 0.2em 0.4em;
        }
        ul {
          display: block;
          list-style-type: disc;
        }
        li {
          display: list-item;
          text-align: -webkit-match-parent;
        }
        dt {
          font-weight: bold;
          margin-bottom: 0.1em;
        }
        h1, h2 {
          border-bottom: 1px solid #a2a9b1;
        }
      </style>
    }
  end

  def self.clean_page(nokogiri_page)
    content = nokogiri_page.at("#content")

    remove_inline_styles!(content)
    remove_footnotes!(content)
    remove_bad_nodes!(content)
    remove_links!(content)
    flatten_images!(content, nokogiri_page)
    create_local_images!(content)

    content.to_s
  end

  def self.remove_inline_styles!(node)
    node.traverse do |child|
      child.remove_attribute("style")
      child.remove_attribute("align")
    end

    node.search(".thumbinner").each do |thumb|
      thumb.remove_attribute("style")
    end
  end

  # Fetch images from Wikipedia and store locally. Wiki allows resizing on the fly.
  def self.create_local_images!(node)
    image_size = "1920px"

    node.search("img").each do |img|
      remote_src = "https:#{img.attr('src')}".sub(/\d\d\d\d?px/, image_size)
      basename = File.basename(remote_src)
      save_path = "#{@results_path}/#{URI.unescape(basename)}"

      unless File.exists?(save_path)
        File.open(save_path, "wb") do |file|
          file << open(remote_src).read
        end
      end

      img.set_attribute("src", File.join("./", basename))
      img.remove_attribute("width")
      img.remove_attribute("height")
    end
  end

  # Replace links because they don't work well in mobile readers.
  def self.remove_links!(node)
    node.search("a").each do |link|
      link.name = "span"
      link.remove_attribute("href")
    end
  end

  # Extracts images (typically top page right navbar images) from the box and places to the parent.
  def self.flatten_images!(node, nokogiri_page)
    node.search(".vertical-navbox").each do |navbox|
      parent = navbox.parent
      images = navbox.search("img")

      images.each do |img| 
        thumbinner = nokogiri_page.create_element("div", class: "thumbinner")
        thumbinner.prepend_child(img)
        parent.prepend_child(thumbinner)
      end

      navbox.remove
    end
  end

  def self.remove_bad_nodes!(node)
    bad_nodes = %w(
      .navbox
      .noprint
      .ambox
      .reference
      .mw-editsection
      .mw-jump-link
      .Template-Fact
      .Inline-Template
      .rellink
      .printfooter
      .reflist
      .infobox
      #siteSub
      #contentSub
      #jump-to-nav
      #toc
      #mw-navigation
      #footer
      #catlinks
      #mw-indicator-semiprotect
      #mw-indicator-protect
      script
      noscript
      br
    )

    node.search(*bad_nodes).remove
  end

  # Removes everything after the footnote ids.
  def self.remove_footnotes!(node)
    footnote_ids = %w(
      References
      Sources
      External_links
      See_also
      Notes
      脚注
      注釈
      出典
      参考文献
      関連項目
      外部リンク
    )

    footnote_ids.each do |footnote_id|
      footnote_header = node.at("\##{footnote_id}")&.parent

      next unless footnote_header

      footnote_header.xpath("following-sibling::*").remove
      footnote_header.remove
    end
  end

  def self.fetch(url)
    Nokogiri::HTML(open(Addressable::URI.escape(url)))
  end

  def self.save(pages, style, source_file_path)
    file_name = "%<name>s.html" % { name: File.basename(source_file_path, ".txt") }
    save_path = File.join(@results_path, file_name)

    File.open(save_path, "w") do |file|
      file << pages.join + style
    end
  end
end

WikiBookMaker.compile_all
