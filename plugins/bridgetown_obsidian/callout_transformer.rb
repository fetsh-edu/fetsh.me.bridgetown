# frozen_string_literal: true

require "nokogiri"
require "digest"

module BridgetownObsidian
  class CalloutTransformer
    SOFT = /(?:\u00AD|&shy;|&#173;)/.freeze # soft hyphen variants

    # Transform a full HTML document string, preserving doctype, <html>, <head>, etc.
    def self.transform(html)
      doc = Nokogiri::HTML::Document.parse(html)
      body = doc.at("body") || doc

      changed = false

      body.css("blockquote").each do |bq|
        first = bq.at_css("> :first-child")
        next unless first&.name == "p"

        first_html = first.inner_html.to_s

        # Sanitize only marker prefix for matching; leave the rest untouched
        if (raw_prefix = first_html[/\A\s*\[![^\]]+\]/m])
          cleaned_prefix = raw_prefix.gsub(SOFT, "")
          first_html_for_match = first_html.sub(raw_prefix, cleaned_prefix)
        else
          first_html_for_match = first_html
        end

        # [!type] … (capture remainder of first <p>)
        m = first_html_for_match.match(/\A\s*\[!([A-Za-z0-9_-]+)\]\s*(.*)\z/m)
        next unless m

        type = m[1].downcase

        # Remove marker from the ORIGINAL html (keep typography)
        original_remainder = first_html.sub(/\A\s*\[![^\]]+\][^\S\n]*/m, "").to_s

        # Compute title/body: only treat same-line title if there is an explicit separator
        sep_match = original_remainder.match(/<br\s*\/?>|\r?\n/)

        if sep_match
          br_start = sep_match.begin(0)
          br_end   = sep_match.end(0)
          title_raw = original_remainder[0...br_start].to_s.strip
          body_html = original_remainder[br_end..-1].to_s
          title_text = title_raw.empty? ? type.capitalize : title_raw
        else
          title_text = type.capitalize
          body_html  = original_remainder
        end

        id = generate_callout_id(original_remainder, type)

        # Build wrapper as semantic aside with accessible title
        wrapper = Nokogiri::XML::Node.new("aside", doc)
        wrapper["class"] = "callout #{type}"
        wrapper["data-callout"] = type
        wrapper["role"] = "note"
        wrapper["aria-labelledby"] = id

        title_shell = Nokogiri::XML::Node.new("h4", doc)
        title_shell["class"] = "callout-title"
        title_shell["id"] = id

        icon_el = Nokogiri::XML::Node.new("span", doc)
        icon_el["class"] = "callout-icon"
        icon_el["aria-hidden"] = "true"

        title_shell.add_child(icon_el)
        title_shell.add_child(title_text)
        wrapper.add_child(title_shell)

        # Replace first paragraph; re-add remainder as body if present
        first.remove

        unless body_html.strip.empty?
          remainder_fragment = Nokogiri::HTML::DocumentFragment.parse("<p>#{body_html}</p>")
          wrapper.add_child(remainder_fragment)
        end

        # Move remaining children (multi-paragraph support)
        bq.children.each { |child| wrapper.add_child(child) }

        bq.replace(wrapper)
        changed = true
      end

      changed ? doc.to_html : html
    end

    def self.generate_callout_id(content, type = "warning")
      hash = Digest::SHA256.hexdigest("#{type}:#{content}")
      "#{type}-#{hash[0, 12]}"
    end
  end
end
