# frozen_string_literal: true

require "nokogiri"

class HeadingPermalinkAfter
  def self.rewrite!(html)
    doc = Nokogiri::HTML.parse(html)
    doc.css("h1,h2,h3,h4,h5,h6").each do |h|
      a = h.at_css("> a[href^='#']")
      next unless a
      a.remove
      h.add_child(a)
    end
    doc.to_html
  end
end

Bridgetown::Hooks.register [:documents, :pages, :posts], :post_render do |resource|
  next unless resource.output_ext == ".html"
  resource.output = HeadingPermalinkAfter.rewrite!(resource.output)
end
