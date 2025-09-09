# frozen_string_literal: true

require "nokogiri"
require "uri"

module ExternalLinks
  module Utils
    module_function

    def site_host(site)
      raw = site.config["url"].to_s.strip
      return nil if raw.empty?
      URI.parse(raw).host&.then { |h| normalize_host(h) }
    rescue URI::InvalidURIError
      nil
    end

    def normalize_host(host)
      return nil if host.nil? || host.empty?
      h = host.downcase
      h.start_with?("www.") ? h.sub(/\Awww\./, "") : h
    end

    def httpish?(href)                 = href.start_with?("http://", "https://")
    def protocol_relative?(href)       = href.start_with?("//")
    def fragment?(href)                = href.start_with?("#")
    def document_relative?(href)       = href.start_with?("./", "../")
    def root_relative?(href)           = href.start_with?("/")
    def special_scheme?(href)          = href.start_with?("mailto:", "tel:", "javascript:")

    def absolute_host(href)
      URI.parse(href).host
    rescue URI::InvalidURIError
      nil
    end

    def internal?(href, site_host_norm)
      return true if fragment?(href)
      return true if root_relative?(href) || document_relative?(href)

      if httpish?(href)
        host = normalize_host(absolute_host(href))
        return true if site_host_norm && host == site_host_norm
        return false
      end

      if protocol_relative?(href)
        host = normalize_host(absolute_host("http:#{href}"))
        return true if site_host_norm && host == site_host_norm
        return false
      end

      # Likely document-relative (e.g., "page.html", "assets/img.png")
      return true unless href.include?(":")

      false
    rescue StandardError
      true
    end

    def should_mark_external?(href, site_host_norm)
      return false if href.nil? || href.empty?
      return false if fragment?(href) || special_scheme?(href)

      if httpish?(href)
        host = normalize_host(absolute_host(href))
        return true if host.nil?                       # malformed absolute -> treat as external
        return host != site_host_norm if site_host_norm
        return true
      end

      if protocol_relative?(href)
        host = normalize_host(absolute_host("http:#{href}"))
        return true if host.nil?
        return host != site_host_norm if site_host_norm
        return true
      end

      false
    end

    def add_token_to_attr(element, attr_name, token)
      existing = element[attr_name].to_s
      parts = existing.split(/\s+/).reject(&:empty?)
      unless parts.include?(token)
        parts << token
        element[attr_name] = parts.join(" ").strip
      end
    end
  end

  module_function

  # Public API: transform a full HTML document string.
  # Preserves <!doctype> and <html> by parsing as a full document, not a fragment.
  def transform_html(html, site)
    return html if html.to_s.empty?

    # Use full-document parser to avoid losing <html>/<head>/<body>.
    # Nokogiri::HTML.parse preserves doctype if present.
    doc = Nokogiri::HTML.parse(html)

    site_host_norm = Utils.site_host(site)

    doc.css("a[href]").each do |a|
      href = a["href"].to_s.strip
      next if href.empty?
      next if a.attribute("download") # keep downloads untouched

      if Utils.should_mark_external?(href, site_host_norm)
        Utils.add_token_to_attr(a, "class", "external")
        a["target"] = "_blank" unless a["target"] && a["target"] != "_self"
        Utils.add_token_to_attr(a, "rel", "noopener")
        Utils.add_token_to_attr(a, "rel", "noreferrer")
        Utils.add_token_to_attr(a, "rel", "external")
      end
    end

    doc.to_html
  end
end

Bridgetown::Hooks.register [:documents, :pages, :posts], :post_render do |resource|
  next unless resource.output_ext == ".html"
  resource.output = ExternalLinks.transform_html(resource.output, resource.site)
end
